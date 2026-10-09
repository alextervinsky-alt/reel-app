#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import ReelCore

// MARK: - Trailer

/// One YouTube player for the whole app, kept ready: the web engine and YouTube's player script
/// load once (`warm`, when Cinema mode or a film page opens), so a trailer starts in about a
/// second. Only official videos are ever loaded (see `Trailers`). Nothing is kept on disk.
/// The trailer on screen owns the player through a token, so a closing trailer can't stop the
/// next one. If YouTube's script can't load or the web engine quits, the page is thrown away and
/// loaded afresh for the next trailer, and the films aren't blamed.
@MainActor
final class TrailerEngine: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = TrailerEngine()

    private var webView: WKWebView?
    private var pageReady = false
    /// YouTube's player script has loaded: from here a video that won't start is the video's fault.
    private(set) var apiReady = false
    private var pending: String?
    /// The trailer on screen.
    private(set) var owner: UUID?
    /// "playing", "ended", "error" or "unavailable" (the player itself failed), for the owner.
    private var onEvent: ((String) -> Void)?
    /// Where the owner's video is: seconds in, seconds long, playing.
    private var onTime: ((TrailerTime) -> Void)?

    func warm() {
        _ = view()
    }

    func view() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "reel")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.underPageBackgroundColor = .black
        view.navigationDelegate = self
        // YouTube's embedded player expects an https page around it.
        view.loadHTMLString(Self.page, baseURL: URL(string: "https://reel.local/"))
        webView = view
        return view
    }

    /// Hands the player to a new trailer.
    func begin(onEvent: @escaping (String) -> Void, onTime: @escaping (TrailerTime) -> Void) -> UUID {
        let token = UUID()
        owner = token
        self.onEvent = onEvent
        self.onTime = onTime
        return token
    }

    /// Starts a video (a YouTube key from TMDB's official list).
    func play(_ key: String, owner token: UUID?) {
        guard token != nil, token == owner else { return }
        let safe = key.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard pageReady else {
            pending = safe
            _ = view()
            return
        }
        webView?.evaluateJavaScript("loadVideo('\(safe)')", completionHandler: nil)
    }

    /// Stops the owner's video; a trailer that has already handed the player on changes nothing.
    func stop(owner token: UUID?) {
        guard token != nil, token == owner else { return }
        owner = nil
        onEvent = nil
        onTime = nil
        pending = nil
        if pageReady { webView?.evaluateJavaScript("stopVideo()", completionHandler: nil) }
    }

    /// Jumps to a point of the owner's video.
    func seek(to seconds: Double, owner token: UUID?) {
        guard token != nil, token == owner, pageReady, seconds.isFinite else { return }
        webView?.evaluateJavaScript("seekTo(\(max(0, seconds)))", completionHandler: nil)
    }

    func togglePause(owner token: UUID?) {
        guard token != nil, token == owner, pageReady else { return }
        webView?.evaluateJavaScript("togglePause()", completionHandler: nil)
    }

    /// Throws the page away; the next trailer loads it afresh.
    func restart() {
        let event = onEvent
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "reel")
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        pageReady = false
        apiReady = false
        pending = nil
        event?("unavailable")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === webView,
              let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
        switch event {
        case "page":
            pageReady = true
            if let pending {
                self.pending = nil
                webView?.evaluateJavaScript("loadVideo('\(pending)')", completionHandler: nil)
            }
        case "api":
            apiReady = true
        case "apiError":
            restart()
        case "time":
            guard let t = body["t"] as? Double, let d = body["d"] as? Double else { return }
            onTime?(TrailerTime(current: t, duration: d, playing: (body["s"] as? Int) == 1))
        default:
            onEvent?(event)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        restart()
    }

    private static let page = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width">
    <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
    </head><body><div id="p"></div><script>
    var player=null,ready=false,queued=null,cancelled=false;
    function post(e){window.webkit.messageHandlers.reel.postMessage({event:e})}
    function onYouTubeIframeAPIReady(){post('api');if(queued){var k=queued;queued=null;loadVideo(k)}}
    function loadVideo(k){
      cancelled=false;
      if(!window.YT||!YT.Player||(player&&!ready)){queued=k;return}
      if(player){player.loadVideoById({videoId:k,suggestedQuality:'hd1080'});return}
      player=new YT.Player('p',{host:'https://www.youtube-nocookie.com',videoId:k,
        playerVars:{autoplay:0,rel:0,playsinline:1,iv_load_policy:3,fs:0,controls:0,disablekb:1,vq:'hd1080'},
        events:{onReady:function(e){ready=true;if(queued){var q=queued;queued=null;loadVideo(q)}else if(!cancelled){e.target.setPlaybackQuality('hd1080');e.target.playVideo()}},
          onStateChange:function(e){if(cancelled)return;if(e.data==1)post('playing');if(e.data==0)post('ended')},
          onError:function(){if(!cancelled)post('error')}}});
    }
    function stopVideo(){queued=null;cancelled=true;if(ready)player.stopVideo()}
    function togglePause(){if(!ready)return;if(player.getPlayerState()==1)player.pauseVideo();else player.playVideo()}
    function seekTo(t){if(ready){player.seekTo(t,true)}}
    setInterval(function(){if(!ready||cancelled||!player.getDuration)return;var d=player.getDuration();if(!(d>0))return;
      window.webkit.messageHandlers.reel.postMessage({event:'time',t:player.getCurrentTime(),d:d,s:player.getPlayerState()})},250);
    post('page');
    </script><script src="https://www.youtube.com/iframe_api" onerror="post('apiError')"></script></body></html>
    """
}

/// The shared player's web view, placed in the trailer that owns the player.
private struct TrailerWebView: NSViewRepresentable {
    let owner: UUID?

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        if owner != nil, owner == TrailerEngine.shared.owner { attach(to: host) }
        return host
    }

    func updateNSView(_ host: NSView, context: Context) {
        // Only the trailer that owns the player takes it: one fading out never pulls it back.
        guard owner != nil, owner == TrailerEngine.shared.owner else { return }
        if TrailerEngine.shared.view().superview !== host { attach(to: host) }
    }

    static func dismantleNSView(_ host: NSView, coordinator: ()) {
        host.subviews.forEach { $0.removeFromSuperview() }
    }

    private func attach(to host: NSView) {
        let web = TrailerEngine.shared.view()
        web.removeFromSuperview()
        web.frame = host.bounds
        web.autoresizingMask = [.width, .height]
        host.addSubview(web)
    }
}

/// A trailer over the page. It grows from the poster it was started from, shows the film's
/// backdrop until the video plays, and tries the film's next official video if one won't play
/// inside Reel. Under it: what you need to decide, Tonight and Full Screen. Esc closes (or
/// leaves full screen first), Space pauses, T adds to Tonight, F fills the screen. Cinema mode
/// never leaves for a browser.
struct TrailerOverlay: View {
    @Environment(AppModel.self) private var model
    let request: TrailerRequest
    let close: () -> Void
    @State private var expanded = false
    @State private var phase = Phase.loading
    @State private var index = 0
    @State private var watchdog: Task<Void, Never>?
    /// This trailer's hold on the shared player.
    @State private var token: UUID?
    /// The player fills the whole screen (the window goes full screen too if it wasn't).
    @State private var filling = false
    @State private var madeWindowFullScreen = false
    /// The controls (and Exit Full Screen) show while the pointer moves, then step aside.
    @State private var controlsShown = true
    @State private var hideControls: Task<Void, Never>?
    /// Where the video is, from the player.
    @State private var time = TrailerTime()
    /// Where the timeline is being dragged to (the player goes there on release).
    @State private var scrub: Double?

    /// `unavailable`: the player itself couldn't load (no connection), not the film's videos.
    private enum Phase { case loading, playing, ended, failed, unavailable }

    /// How long a video may take to start before the next one is tried.
    private static let patience: Duration = .seconds(10)

    var body: some View {
        GeometryReader { geometry in
            let target = Self.target(in: geometry.size, cinema: model.cinemaMode)
            let base = geometry.frame(in: .global).origin
            let start = request.origin.map { $0.offsetBy(dx: -base.x, dy: -base.y) }
            let rect = filling ? CGRect(origin: .zero, size: geometry.size) : (expanded ? target : (start ?? target))
            ZStack(alignment: .topLeading) {
                Color.black.opacity(filling ? 1 : (expanded ? 0.9 : 0))
                    .contentShape(Rectangle())
                    .onTapGesture { if !filling { dismiss() } }
                screen
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: filling ? 0 : (model.cinemaMode ? 18 : 14), style: .continuous))
                    .shadow(color: Color.black.opacity(filling ? 0 : 0.6), radius: 30)
                    .position(x: rect.midX, y: rect.midY)
                panel
                    .frame(width: target.width, alignment: .leading)
                    .position(x: target.midX, y: target.maxY + (model.cinemaMode ? 84 : 64))
                    .opacity(expanded && !filling ? 1 : 0)
                    .allowsHitTesting(!filling)
                if filling {
                    button("Exit Full Screen", symbol: "arrow.down.right.and.arrow.up.left") { toggleFill() }
                        .padding(24)
                        .frame(width: geometry.size.width, alignment: .trailing)
                        .opacity(controlsShown ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: controlsShown)
                }
            }
            .onContinuousHover { hover in
                if case .active = hover { revealControls() }
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: begin)
        .onDisappear(perform: end)
        // Left full screen another way (the green button): the player goes back to its place.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            madeWindowFullScreen = false
            guard filling else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { filling = false }
            model.trailerFillsScreen = false
        }
        .onReelKey { key in
            switch key {
            case .escape: if filling { toggleFill() } else { dismiss() }
            case .fullScreen: toggleFill()
            case .space: if phase == .ended { playAgain() } else { TrailerEngine.shared.togglePause(owner: token) }
            // Ten seconds back or on.
            case .left, .right:
                guard phase == .playing || phase == .ended, time.duration > 0 else { return false }
                seek(to: time.current + (key == .left ? -10 : 10))
                revealControls()
            case .tonight:
                guard let id = request.filmID, let film = model.film(id: id) else { return false }
                model.toggleTonight(film.personalKey)
            default: return false
            }
            return true
        }
    }

    /// The player's place: centred, 16:9, leaving room for the panel under it.
    private static func target(in size: CGSize, cinema: Bool) -> CGRect {
        let panel: CGFloat = cinema ? 190 : 140
        let width = min(size.width * (cinema ? 0.82 : 0.84), (size.height - panel - 70) * 16 / 9, 1800)
        let height = width * 9 / 16
        return CGRect(x: (size.width - width) / 2, y: max(40, (size.height - height - panel) / 2), width: width, height: height)
    }

    private var screen: some View {
        ZStack {
            Color.black
            // At the end YouTube shows other videos to play next: the film's backdrop covers them.
            TrailerWebView(owner: token)
                .opacity(phase == .playing ? 1 : 0)
            if phase == .playing {
                // Over the video: a click pauses or plays, and moving the pointer shows the controls.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { TrailerEngine.shared.togglePause(owner: token) }
                TrailerControls(time: time, scrub: $scrub, large: model.cinemaMode) {
                    TrailerEngine.shared.togglePause(owner: token)
                } seek: { seconds in
                    seek(to: seconds)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(controlsShown || !time.playing || scrub != nil ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: controlsShown || !time.playing || scrub != nil)
            }
            if phase != .playing {
                FocusedBackdrop(path: request.backdropPath)
                    .overlay(Color.black.opacity(phase == .loading ? 0.35 : 0.7))
            }
            if phase == .ended {
                button("Play Again", symbol: "arrow.counterclockwise", primary: true) { playAgain() }
            }
            if phase == .loading {
                ProgressView().controlSize(.large).tint(.white)
            }
            if phase == .failed || phase == .unavailable { failure }
        }
    }

    private var failure: some View {
        VStack(spacing: 16) {
            Text(phase == .unavailable ? "Trailers can't load right now. Check the internet connection." : "No trailer plays inside Reel for this film.")
                .font(.system(size: model.cinemaMode ? Cinema.body : 16, weight: .semibold))
            // A deliberate way out, on the desk only: Cinema mode never leaves full screen.
            if !model.cinemaMode, let key = request.videos.first, let url = URL(string: "https://www.youtube.com/watch?v=\(key)") {
                Button("Watch on YouTube") {
                    NSWorkspace.shared.open(url)
                    dismiss()
                }
                .buttonStyle(SecondaryCapsuleStyle())
            }
        }
        .foregroundStyle(Color.white)
    }

    /// Title, year · running time · when it would end, ratings; Tonight, Open Film, Close.
    @ViewBuilder
    private var panel: some View {
        let film = request.filmID.flatMap { model.film(id: $0) }
        let cinema = model.cinemaMode
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(request.title)
                    .font(.system(size: cinema ? 28 : 20, weight: .bold))
                    .lineLimit(1)
                if let film {
                    Text(Format.decisionLine(film))
                        .font(.system(size: cinema ? Cinema.body : 13.5))
                        .foregroundStyle(Theme.secondaryText)
                    if cinema { CinemaRatings(film: film) } else { RatingStrip(film: film) }
                }
            }
            Spacer(minLength: 20)
            if let film {
                let onTonight = model.isTonight(film.personalKey)
                button(onTonight ? "On Tonight" : "Tonight", symbol: onTonight ? "moon.fill" : "moon") {
                    model.toggleTonight(film.personalKey)
                }
                if request.offersFilmPage {
                    button("Open Film", symbol: "info.circle") {
                        model.filmToOpen = film.id
                        dismiss()
                    }
                }
            }
            button("Full Screen", symbol: "arrow.up.left.and.arrow.down.right") { toggleFill() }
            button("Close", symbol: "xmark", primary: true) { dismiss() }
        }
        .foregroundStyle(Color.white)
    }

    /// Fills the screen with the player, or goes back. The window goes full screen for it when
    /// it wasn't already, and back again after.
    private func toggleFill() {
        let window = AppModel.libraryWindow
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { filling.toggle() }
        model.trailerFillsScreen = filling
        if filling {
            revealControls()
            if let window, !window.styleMask.contains(.fullScreen) {
                madeWindowFullScreen = true
                window.toggleFullScreen(nil)
            }
        } else {
            leaveWindowFullScreen()
        }
    }

    private func leaveWindowFullScreen() {
        guard madeWindowFullScreen else { return }
        madeWindowFullScreen = false
        // Cinema mode came on meanwhile: the full screen is its now, to undo when it goes off.
        if model.cinemaMode {
            model.enteredFullScreen = true
            return
        }
        if let window = AppModel.libraryWindow, window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }

    /// From the start, after the end.
    private func playAgain() {
        seek(to: 0)
        TrailerEngine.shared.togglePause(owner: token)
    }

    /// Jumps to a point of the video (shown there at once, before the player catches up).
    private func seek(to seconds: Double) {
        let target = min(max(0, seconds), max(0, time.duration - 0.5))
        time.current = target
        TrailerEngine.shared.seek(to: target, owner: token)
    }

    private func revealControls() {
        controlsShown = true
        hideControls?.cancel()
        hideControls = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { controlsShown = false }
        }
    }

    @ViewBuilder
    private func button(_ title: String, symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        if model.cinemaMode {
            Button(action: action) { Label(title, systemImage: symbol) }
                .buttonStyle(CinemaButtonStyle(primary: primary, compact: true))
        } else if primary {
            Button(action: action) { Label(title, systemImage: symbol) }
                .buttonStyle(PrimaryCapsuleStyle())
        } else {
            Button(action: action) { Label(title, systemImage: symbol) }
                .buttonStyle(SecondaryCapsuleStyle())
        }
    }

    private func begin() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { expanded = true }
        token = TrailerEngine.shared.begin { event in handle(event) } onTime: { now in
            time = now
        }
        play()
    }

    private func play() {
        guard request.videos.indices.contains(index) else { return }
        phase = .loading
        TrailerEngine.shared.play(request.videos[index], owner: token)
        watchdog?.cancel()
        watchdog = Task {
            // Each video gets its full patience once YouTube's script is there. Without the
            // script nothing could have played, so the film isn't blamed: after half a minute
            // the player starts afresh.
            var scriptWasReady = TrailerEngine.shared.apiReady
            var waited: Duration = .zero
            while true {
                try? await Task.sleep(for: Self.patience)
                guard !Task.isCancelled, phase == .loading else { return }
                waited += Self.patience
                if TrailerEngine.shared.apiReady {
                    if scriptWasReady { return tryNext() }
                    scriptWasReady = true
                } else if waited >= .seconds(30) {
                    return TrailerEngine.shared.restart()
                }
            }
        }
    }

    private func handle(_ event: String) {
        switch event {
        case "playing":
            watchdog?.cancel()
            if phase == .loading { model.trailerResult(tmdbID: request.tmdbID, played: true) }
            withAnimation(.easeOut(duration: 0.25)) { phase = .playing }
            // The controls show at first, then step aside until the pointer moves.
            revealControls()
        case "ended":
            phase = .ended
        case "error":
            if phase == .loading { tryNext() }
        case "unavailable":
            watchdog?.cancel()
            TrailerEngine.shared.stop(owner: token)
            withAnimation(.easeOut(duration: 0.2)) { phase = .unavailable }
        default:
            break
        }
    }

    /// The next official video, or the note that none plays here.
    private func tryNext() {
        index += 1
        if request.videos.indices.contains(index) {
            play()
        } else {
            watchdog?.cancel()
            TrailerEngine.shared.stop(owner: token)
            model.trailerResult(tmdbID: request.tmdbID, played: false)
            withAnimation(.easeOut(duration: 0.2)) { phase = .failed }
        }
    }

    private func end() {
        watchdog?.cancel()
        hideControls?.cancel()
        TrailerEngine.shared.stop(owner: token)
        if filling { model.trailerFillsScreen = false }
        leaveWindowFullScreen()
    }

    /// Shrinks back into the poster, then closes.
    private func dismiss() {
        end()
        withAnimation(.easeIn(duration: 0.24)) {
            expanded = false
            filling = false
        }
        Task {
            try? await Task.sleep(for: .milliseconds(240))
            close()
        }
    }
}

/// Where a trailer is: seconds in, seconds long, and whether it's playing.
struct TrailerTime: Equatable {
    var current: Double = 0
    var duration: Double = 0
    var playing = false
}

/// Under the trailer: play or pause, how far in, and a timeline to click or drag to any point.
private struct TrailerControls: View {
    let time: TrailerTime
    @Binding var scrub: Double?
    let large: Bool
    let togglePause: () -> Void
    let seek: (Double) -> Void
    @State private var hovering = false

    var body: some View {
        let shown = scrub ?? time.current
        HStack(spacing: large ? 18 : 14) {
            Button(action: togglePause) {
                Image(systemName: time.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: large ? 24 : 16, weight: .semibold))
                    .frame(width: large ? 44 : 28, height: large ? 44 : 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(time.playing ? "Pause (Space)" : "Play (Space)")
            Text(Self.clock(shown))
                .font(.system(size: large ? Cinema.body : 12.5, weight: .medium))
                .monospacedDigit()
            timeline(shown)
            Text("−" + Self.clock(max(0, time.duration - shown)))
                .font(.system(size: large ? Cinema.body : 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, large ? 26 : 18)
        .padding(.top, large ? 40 : 30)
        .padding(.bottom, large ? 20 : 14)
        .background(LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
    }

    /// Click anywhere on it to go there, or drag; the line thickens under the pointer.
    private func timeline(_ shown: Double) -> some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let fraction = time.duration > 0 ? min(max(shown / time.duration, 0), 1) : 0
            let thick: CGFloat = (hovering || scrub != nil) ? (large ? 10 : 7) : (large ? 6 : 4)
            let knob: CGFloat = large ? 22 : 14
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.28)).frame(height: thick)
                Capsule().fill(Color.white).frame(width: width * fraction, height: thick)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: Color.black.opacity(0.4), radius: 3)
                    .offset(x: width * fraction - knob / 2)
                    .opacity(hovering || scrub != nil ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard time.duration > 0 else { return }
                    scrub = min(max(value.location.x / width, 0), 1) * time.duration
                }
                .onEnded { value in
                    guard time.duration > 0 else { return }
                    seek(min(max(value.location.x / width, 0), 1) * time.duration)
                    scrub = nil
                })
            .animation(.easeOut(duration: 0.15), value: thick)
        }
        .frame(height: large ? 36 : 24)
        .onHover { hovering = $0 }
    }

    /// "1:05"
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Quick preview

/// Enough to decide without leaving the grid: Space on a poster under the pointer, or
/// right-click › Quick Look. A click outside it or Esc closes it.
struct QuickPreview: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem
    let close: () -> Void
    let openFilm: () -> Void

    var body: some View {
        let film = item.main
        VStack(alignment: .leading, spacing: 16) {
            FocusedBackdrop(path: film.tmdb?.backdropPath)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            // The same order as the film page: title, year line, ratings, verdict, why, when it ends.
            VStack(alignment: .leading, spacing: 6) {
                Text(film.displayTitle).font(.system(size: 24, weight: .bold))
                Text(Format.metaLine(film)).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            RatingStrip(film: film)
            if let verdict = ReceptionVerdict.sentence(ratings: film.ratings, tmdbVote: film.tmdb?.voteAverage,
                                                       reception: film.reception, cinemaScore: film.funFacts?.cinemaScore) {
                Text(verdict)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.brand)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reason = model.pickReason(forKey: item.id) {
                Text(reason.long)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
            if let ends = Format.endsLine(film, runtime: item.runtime) {
                Label(ends, systemImage: "clock")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            if let overview = film.tmdb?.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if item.isOnline {
                    Button {
                        model.play(film)
                        close()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryCapsuleStyle())
                }
                Button("Open Film") {
                    close()
                    openFilm()
                }
                .buttonStyle(SecondaryCapsuleStyle())
                if model.offersTrailer(for: film) {
                    Button(model.trailerLabel(for: film)) {
                        close()
                        model.showTrailer(for: film, offersFilmPage: true)
                    }
                    .buttonStyle(SecondaryCapsuleStyle())
                }
                RoundToggle(symbol: "moon", onSymbol: "moon.fill", isOn: model.isTonight(item.id),
                            help: model.isTonight(item.id) ? "On tonight's shortlist" : "Add to Tonight") {
                    model.toggleTonight(item.id)
                }
                Spacer()
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

// MARK: - More Like This

/// Films in the library most like this one, as a full page.
struct SimilarRoute: Hashable {
    let filmID: String
}

struct MoreLikeThisPage: View {
    @Environment(AppModel.self) private var model
    let route: SimilarRoute
    @State private var scroll = ScrollState()

    var body: some View {
        let film = model.film(id: route.filmID)
        let items = film.map { model.similarItems(for: $0, limit: 60) } ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("More Like \(film?.displayTitle ?? "This")").font(.system(size: 30, weight: .bold))
                    Text("Films in your library that share moods, people, themes or genres with it, closest first.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                if items.isEmpty {
                    ContentUnavailableView("Nothing close enough yet", systemImage: "square.stack",
                                           description: Text("More films with info make better matches."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(columns: LibraryGridView.columns, alignment: .leading, spacing: 32) {
                        ForEach(items) { item in
                            NavigationLink(value: FilmRoute(id: item.main.id)) {
                                PosterCard(item: item).equatable()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
        }
        .environment(scroll)
        .background(Theme.background)
        .navigationTitle("More Like This")
    }
}
#endif
