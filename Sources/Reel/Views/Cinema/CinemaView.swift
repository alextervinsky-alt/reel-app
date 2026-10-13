#if os(macOS)
import SwiftUI
import ReelCore

/// Cinema mode's three places, as tabs at the top.
enum CinemaTab: Hashable {
    case home, tonight, library
}

/// Cinema mode: Reel as a 10-foot view for the TV. Separate from the desk views, so turning it on
/// or off never changes them; the desk keeps its place, search and filters. All Films has its
/// own search field (⌘F goes to it from anywhere).
struct CinemaView: View {
    @Environment(AppModel.self) private var model
    /// Cinema mode's search (RootView keeps the desk's aside meanwhile).
    @Binding var searchText: String
    /// Set by ⌘F: All Films comes up with its search field focused.
    @Binding var focusSearch: Bool
    let query: String
    @State private var tab: CinemaTab
    /// Film pages opened on top of the tab (film IDs), most recent last.
    @State private var path: [String]
    /// The top bar's share of the arrow keys.
    @State private var bar = CinemaBar()

    init(searchText: Binding<String>, focusSearch: Binding<Bool> = .constant(false), query: String,
         tab: CinemaTab = .home, path: [String] = []) {
        _searchText = searchText
        _focusSearch = focusSearch
        self.query = query
        _tab = State(initialValue: tab)
        _path = State(initialValue: path)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            // Home stays alive under the other places, and the open tab under a film page, so
            // coming back keeps its place, filters and scroll position.
            CinemaHome(active: path.isEmpty && tab == .home && pageHasKeys, open: open)
                .opacity(path.isEmpty && tab == .home ? 1 : 0)
                .allowsHitTesting(path.isEmpty && tab == .home)
            Group {
                switch tab {
                case .home: EmptyView()
                case .tonight: CinemaTonight(active: path.isEmpty && pageHasKeys, open: open)
                case .library:
                    CinemaLibrary(searchText: $searchText, focusSearch: $focusSearch, query: query,
                                  active: path.isEmpty && pageHasKeys, open: open)
                }
            }
            .opacity(path.isEmpty ? 1 : 0)
            .allowsHitTesting(path.isEmpty)
            .transition(.opacity)
            if let id = path.last {
                CinemaFilmPage(filmID: id, active: pageHasKeys, open: open)
                    .id(id)
                    .transition(.opacity)
            }
        }
        // Edge to edge: nothing of the window shows above it.
        .ignoresSafeArea()
        // The bar itself stays clear of the window buttons.
        .overlay(alignment: .top) { topBar }
        // After a film: did you finish it, and how was it, large.
        .overlay {
            if let prompt = model.ratingPrompt {
                CinemaHowWasIt(prompt: prompt).id(prompt.id).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.ratingPrompt?.id)
        .environment(bar)
        .onChange(of: barLanding, initial: true) { _, landing in bar.landing = landing }
        .animation(.easeOut(duration: 0.22), value: path)
        .animation(.easeOut(duration: 0.22), value: tab)
        .onChange(of: model.filmToOpen) { _, id in
            // Open Film under a trailer.
            guard let id else { return }
            model.filmToOpen = nil
            open(id)
        }
        .onChange(of: focusSearch) { _, wanted in
            // ⌘F: to All Films, where the field takes the focus.
            guard wanted else { return }
            path = []
            tab = .library
        }
        .onReelKey { key in
            // A trailer, a filter panel or the questions after a film take the keys first.
            guard model.trailer == nil, !model.cinemaPanelOpen, model.ratingPrompt == nil else { return false }
            if let index = bar.index { return barKey(key, at: index) }
            guard key == .escape else { return false }
            if !path.isEmpty {
                path.removeLast()
            } else if tab != .home {
                tab = .home
            } else {
                return false
            }
            return true
        }
    }

    /// The page has the arrow keys: nothing is open over it and the top bar doesn't have them.
    private var pageHasKeys: Bool {
        model.trailer == nil && model.ratingPrompt == nil && bar.index == nil
    }

    /// The page showing, as `CinemaBar` names it.
    private var page: String {
        if let id = path.last { return "film:" + id }
        switch tab {
        case .home: return "home"
        case .tonight: return "tonight"
        case .library: return "library"
        }
    }

    /// What the bar shows, left to right.
    private enum BarItem: Equatable {
        case back, tab(CinemaTab), exit
    }

    private var barItems: [BarItem] {
        path.isEmpty ? [.tab(.home), .tab(.tonight), .tab(.library), .exit] : [.back, .exit]
    }

    /// Up from a page lands on its own tab (or Back).
    private var barLanding: Int {
        barItems.firstIndex(of: path.isEmpty ? .tab(tab) : .back) ?? 0
    }

    /// The keys in the bar: left and right along it, Return to choose, Down back to the page.
    private func barKey(_ key: ReelKey, at index: Int) -> Bool {
        let items = barItems
        switch key {
        case .left: bar.index = max(index - 1, 0)
        case .right: bar.index = min(index + 1, items.count - 1)
        case .down, .escape: bar.giveBack(to: page)
        case .up: break
        case .enter, .space:
            guard items.indices.contains(index) else { return false }
            switch items[index] {
            case .back:
                path.removeLast()
                bar.index = barLanding
            case .tab(let place):
                show(place)
                bar.index = barLanding
            case .exit:
                bar.index = nil
                model.setCinemaMode(false)
            }
        case .tonight, .fullScreen: return false
        }
        return true
    }

    private func open(_ filmID: String) {
        // Opening the page you're on (a film from its own More Like This) does nothing.
        if path.last != filmID { path.append(filmID) }
        bar.index = nil
    }

    private func show(_ place: CinemaTab) {
        path = []
        tab = place
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            let items = barItems
            if !path.isEmpty {
                Button {
                    path.removeLast()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(CinemaButtonStyle(focused: bar.index == items.firstIndex(of: .back)))
            } else {
                CinemaChip(title: "For You", symbol: "sparkles", isOn: tab == .home,
                           focused: bar.index == items.firstIndex(of: .tab(.home))) { show(.home) }
                let count = model.tonightItems.count
                CinemaChip(title: count == 0 ? "Tonight" : "Tonight · \(count)", symbol: "moon", isOn: tab == .tonight,
                           focused: bar.index == items.firstIndex(of: .tab(.tonight))) { show(.tonight) }
                CinemaChip(title: "All Films", symbol: "square.grid.3x3", isOn: tab == .library,
                           focused: bar.index == items.firstIndex(of: .tab(.library))) { show(.library) }
            }
            Spacer()
            ExitCinemaButton(focused: bar.index == items.firstIndex(of: .exit)) { model.setCinemaMode(false) }
        }
        .padding(.horizontal, Cinema.gutter)
        .padding(.top, 34)
        .padding(.bottom, 40)
        // The bar sits on solid ground: what scrolls under it is hidden behind it, and only
        // fades in below its buttons. A film page keeps its picture showing through.
        .background(alignment: .top) {
            LinearGradient(stops: path.isEmpty
                           ? [.init(color: Theme.background, location: 0), .init(color: Theme.background, location: 0.74),
                              .init(color: Theme.background.opacity(0), location: 1)]
                           : [.init(color: Theme.background.opacity(0.55), location: 0),
                              .init(color: Theme.background.opacity(0.3), location: 0.6),
                              .init(color: Theme.background.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}
/// Leaves Cinema mode: a quiet round button in the corner that brightens under the pointer.
private struct ExitCinemaButton: View {
    var focused = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(hovering ? 1 : 0.7))
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.2 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .cinemaFocus(focused, circle: true)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Exit Cinema (⇧⌘C)")
        .accessibilityLabel("Exit Cinema")
    }
}
#endif
