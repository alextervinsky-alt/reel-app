#if os(macOS)
import SwiftUI
import ReelCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var shelf: Shelf = .all
    /// What's typed in the search field; `query` follows it after a short pause so the grid
    /// isn't re-filtered on every keystroke.
    @State private var searchText = ""
    @State private var query = ""
    @State private var sort: LibrarySort = .random
    @State private var moods: Set<Mood> = []
    @State private var length: LengthBand = .any
    @State private var language: String?
    @State private var shotOn: ShotOn?
    /// Poster width in the grids, and posters or a list (for this session).
    @State private var posterSize = 168.0
    @State private var asList = false
    @State private var path = NavigationPath()
    /// The desk's search while Cinema mode has the field (put back when Cinema mode ends).
    @State private var deskSearch = ""
    /// ⌘F: the search field showing (desk or Cinema mode) takes the focus.
    @State private var focusSearch = false

    /// Cinema mode or a trailer is over the desk: its Back (drawn above everything, in the
    /// toolbar) steps aside, so it can't move the page underneath.
    private var coveredDesk: Bool { model.cinemaMode || model.trailer != nil }

    /// The desk library, with Cinema mode over it when on, and what can open over either: a
    /// trailer, and the "How was it?" sheet. The desk stays in place (hidden) under Cinema mode,
    /// so its page, scroll position, search and sidebar are exactly as they were afterwards.
    var body: some View {
        ZStack {
            desk
                .opacity(model.cinemaMode ? 0 : 1)
                .allowsHitTesting(!model.cinemaMode)
                .accessibilityHidden(model.cinemaMode)
            if model.cinemaMode {
                CinemaView(searchText: $searchText, focusSearch: $focusSearch, query: query).transition(.opacity)
            }
            if let trailer = model.trailer {
                TrailerOverlay(request: trailer) { if model.trailer == trailer { model.trailer = nil } }
                    .transition(.opacity)
            }
        }
        // ⌘F, as in any Mac app: to the search under All Films (Cinema mode's, when it's on).
        .background {
            Button("") {
                if !model.cinemaMode {
                    path = NavigationPath()
                    if !shelf.isLibrary { shelf = .all }
                }
                focusSearch = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        }
        // No gray strip: the toolbar stays (it holds the window buttons and Back) but is see-through,
        // so pictures reach the top of the window; in full screen it slides in at the top.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .windowToolbarFullScreenVisibility(.onHover)
        .onChange(of: model.cinemaMode) { _, on in
            // Cinema mode searches on its own: the desk keeps its search, list and page.
            if on {
                deskSearch = searchText
                searchText = ""
            } else {
                searchText = deskSearch
                query = deskSearch
            }
        }
        .onChange(of: model.filmToOpen) { _, id in
            // Open Film under a trailer, on the desk (Cinema mode opens it on its own page).
            guard let id, !model.cinemaMode else { return }
            model.filmToOpen = nil
            path.append(FilmRoute(id: id))
        }
        .animation(.easeOut(duration: 0.3), value: model.cinemaMode)
        .animation(.easeOut(duration: 0.2), value: model.trailer)
        // Cinema mode asks on the TV, large (see `CinemaHowWasIt`).
        .sheet(item: Binding(get: { model.cinemaMode ? nil : model.ratingPrompt }, set: { model.ratingPrompt = $0 })) { prompt in
            HowWasItSheet(prompt: prompt)
        }
    }

    private var desk: some View {
        NavigationSplitView {
            SidebarView(selection: shelf, onSelect: select)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 300)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if !model.isLoaded {
                        // A moment at most: the library is read in the background.
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if needsSetup {
                        WelcomeView()
                    } else {
                        switch shelf {
                        case .forYou: ForYouView()
                        case .explore: ExploreView(path: $path)
                        case .lists: ListsView()
                        case .recommended: RecommendedView()
                        case .tonight: TonightView()
                        case .wishlist: WishlistView()
                        case .yearInFilm: YearInFilmView()
                        default:
                            // The desk's field doesn't take ⌘F while Cinema mode is over it.
                            LibraryGridView(shelf: shelf, searchText: $searchText,
                                            focusSearch: model.cinemaMode ? .constant(false) : $focusSearch, query: query, sort: $sort,
                                            moods: $moods, length: $length, language: $language, shotOn: $shotOn,
                                            posterSize: $posterSize, asList: $asList, path: $path)
                        }
                    }
                }
                .background(Theme.background)
                .navigationDestination(for: FilmRoute.self) { route in
                    FilmPage(filmID: route.id)
                        .navigationBarBackButtonHidden(coveredDesk)
                }
                .navigationDestination(for: PersonRoute.self) { route in
                    PersonPage(route: route)
                        .navigationBarBackButtonHidden(coveredDesk)
                }
                .navigationDestination(for: DiscoverRoute.self) { route in
                    DiscoverListPage(list: route.list, mood: route.mood)
                        .navigationBarBackButtonHidden(coveredDesk)
                }
                .navigationDestination(for: ListRoute.self) { route in
                    ListPage(kind: route.kind)
                        .navigationBarBackButtonHidden(coveredDesk)
                }
                .navigationDestination(for: FranchiseRoute.self) { route in
                    FranchisePage(route: route)
                        .navigationBarBackButtonHidden(coveredDesk)
                }
                .navigationDestination(for: SimilarRoute.self) { route in
                    MoreLikeThisPage(route: route)
                        .navigationBarBackButtonHidden(coveredDesk)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let notice = model.notice {
                    NoticeBar(text: notice) { model.notice = nil }
                }
            }
            // A scan that would remove many films asks first (a drive half-read looks like this too).
            .confirmationDialog(
                model.pendingRemoval.map { "\($0.count) films are no longer on \($0.driveName)" } ?? "",
                isPresented: Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.keepPendingRemoval() } }),
                presenting: model.pendingRemoval
            ) { pending in
                Button("Remove Them from Reel", role: .destructive) { model.confirmPendingRemoval(pending) }
                Button("Keep Them", role: .cancel) { model.keepPendingRemoval() }
            } message: { pending in
                Text("Reel read all of \(pending.driveName) but didn't find them. If you deleted them, remove them. If the drive "
                     + "had a problem, keep them and press ⌘R later. Nothing on the drive is touched, and your notes are kept.")
            }
            // ⌘[ goes back too (not while Cinema mode or a trailer covers the desk).
            .background {
                Button("") { if !path.isEmpty { path.removeLast() } }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(path.isEmpty || coveredDesk)
                    .hidden()
            }
        }
        .task(id: searchText) {
            // Clearing the field shows everything again at once; typing waits for a pause.
            if !searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
            }
            query = searchText
        }
    }

    /// Choosing a sidebar item always lands on that list. All Films works as Home: it also clears
    /// the search and filters.
    private func select(_ newShelf: Shelf) {
        path = NavigationPath()
        if newShelf == .all {
            // Random shows other films first each time.
            model.shuffleSeed = UUID().uuidString
            searchText = ""
            query = ""
            moods = []
            length = .any
            language = nil
            shotOn = nil
        }
        shelf = newShelf
    }

    private var needsSetup: Bool {
        model.drives.isEmpty || (!model.hasToken && !model.hasFilms)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    let selection: Shelf
    let onSelect: (Shelf) -> Void
    @State private var showGenres = false
    @State private var driveToRemove: Drive?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // In the order you use them: choosing tonight's film, your library, finding more.
                    section("Tonight") {
                        row(.recommended, "Recommended", icon: "wand.and.stars")
                        if model.tonightItems.isEmpty {
                            row(.tonight, "Tonight", icon: "moon")
                        } else {
                            TonightCard(isSelected: selection == .tonight) { onSelect(.tonight) }
                                .padding(.vertical, 2)
                        }
                        row(.newArrivals, "New Arrivals", icon: "shippingbox", highlightCount: true)
                    }
                    section("Library") {
                        row(.all, "All Films", icon: "film.stack")
                        row(.unwatched, "Unwatched", icon: "eye.slash")
                        row(.watchlist, "Watchlist", icon: "bookmark")
                        row(.favorites, "Favorites", icon: "heart")
                        row(.watched, "Watched", icon: "checkmark.circle")
                    }
                    if !model.genres.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { showGenres.toggle() }
                            } label: {
                                HStack(spacing: 5) {
                                    sectionTitle("Genres")
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                        .rotationEffect(.degrees(showGenres ? 90 : 0))
                                        .padding(.bottom, 4)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if showGenres {
                                ForEach(model.genres, id: \.self) { genre in
                                    row(.genre(genre), genre, icon: nil)
                                }
                            }
                        }
                    }
                    section("Discover") {
                        row(.forYou, "For You", icon: "sparkles")
                        row(.explore, "Explore", icon: "safari")
                        row(.lists, "Lists", icon: "list.number")
                        row(.wishlist, "Wishlist", icon: "star")
                        row(.yearInFilm, "Year in Film", icon: "calendar")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .clipped()
            if !model.drives.isEmpty {
                drivesCard
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            SidebarStatus { onSelect(.newArrivals) }
            footer
        }
        // A floating panel, inset from the window's edges and starting under the window's
        // close, minimise and full-screen buttons (never behind them).
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.sidebar)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
                .padding(EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 2))
                .ignoresSafeArea(edges: .bottom)
        }
        .padding(.leading, 6)
        .background(Theme.background.ignoresSafeArea())
        .confirmationDialog(
            "Remove \(driveToRemove?.name ?? "drive") from Reel?",
            isPresented: Binding(get: { driveToRemove != nil }, set: { if !$0 { driveToRemove = nil } })
        ) {
            Button("Remove", role: .destructive) {
                if let drive = driveToRemove { model.removeDrive(drive.id) }
                driveToRemove = nil
            }
        } message: {
            Text("Reel forgets this drive's files. Nothing on the drive is touched, and your notes are kept.")
        }
    }

    /// The drives at the foot of the sidebar: each with whether it's connected and its free
    /// space or role, then what needs fixing (matches to check, films not on the Backup).
    private var drivesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.drives) { drive in
                driveRow(drive)
            }
            if model.checkCount > 0 {
                fixLink(model.checkCount == 1 ? "1 match to check" : "\(model.checkCount) matches to check", shelf: .needsCheck)
            }
            if model.count(.notOnBackup) > 0 {
                fixLink("\(model.count(.notOnBackup)) not on Backup", shelf: .notOnBackup)
                    .help("Films on your main drive without a full copy on the Backup")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 8) }
    }

    private func fixLink(_ text: String, shelf: Shelf) -> some View {
        Button {
            onSelect(shelf)
        } label: {
            HStack {
                Text(text)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 11.5, weight: selection == shelf ? .semibold : .medium))
            .foregroundStyle(Theme.brand)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.leading, 10)
            .padding(.bottom, 4)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            sectionTitle(title)
            content()
        }
    }

    private func row(_ shelf: Shelf, _ title: String, icon: String?, tint: Color? = nil, highlightCount: Bool = false) -> some View {
        let counted = ![.forYou, .explore, .lists, .recommended, .yearInFilm, .tonight].contains(shelf)
        let count = shelf == .tonight ? model.tonightItems.count : (counted ? model.count(shelf) : nil)
        return SidebarRow(title: title, icon: icon, tint: tint, count: count,
                          countTint: highlightCount && (count ?? 0) > 0 ? Theme.brand : nil,
                          isSelected: selection == shelf) {
            onSelect(shelf)
        }
    }

    private func driveRow(_ drive: Drive) -> some View {
        let online = model.mounted[drive.id] != nil
        let free = online ? model.freeSpace[drive.id].map { Format.bytes($0) + " free" } : nil
        let detail = [drive.isBackup ? "Backup" : nil, online ? free : "off"].compactMap { $0 }.joined(separator: " · ")
        return Button {
            onSelect(.drive(drive.id))
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(online ? Color.green : Color.white.opacity(0.25))
                    .frame(width: 6, height: 6)
                Text(drive.name)
                    .font(.system(size: 11.5, weight: selection == .drive(drive.id) ? .semibold : .regular))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(detail)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selection == .drive(drive.id) ? Color.white.opacity(0.08) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help((online ? "Connected" : "Not connected. Its films stay in the library.")
              + (drive.isBackup ? " A copy of your main drive." : ""))
        .contextMenu {
            Button("Rescan") { Task { await model.scan(drive) } }
                .disabled(!online)
            Picker("Drive Role", selection: Binding(get: { drive.isBackup }, set: { model.setBackup(drive.id, $0) })) {
                Text("Main Drive").tag(false)
                Text("Backup (a copy of the main drive)").tag(true)
            }
            Divider()
            Button("Remove from Reel…") { driveToRemove = drive }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                model.chooseDrive()
            } label: {
                Label("Add Drive", systemImage: "plus")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.setCinemaMode(true)
            } label: {
                Image(systemName: "tv")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Cinema Mode: the library for the TV (⇧⌘C)")
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 18)
        }
    }
}

/// Tonight in the sidebar, once something is on it: how many films, with their posters and
/// titles. Opens Tonight.
struct TonightCard: View {
    @Environment(AppModel.self) private var model
    let isSelected: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        let items = model.tonightItems
        Button(action: open) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                    Text("Tonight").font(.system(size: 13.5, weight: .semibold))
                    Spacer()
                    Text(items.count == 1 ? "1 film" : "\(items.count) films")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .center, spacing: 6) {
                    ForEach(items.prefix(3)) { item in
                        Poster(path: item.main.tmdb?.posterPath, title: item.main.displayTitle, cornerRadius: 4)
                            .frame(width: 30)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(items.prefix(2)) { item in
                            Text(item.main.displayTitle).lineLimit(1)
                        }
                        if items.count > 2 { Text("and \(items.count - 2) more").foregroundStyle(.tertiary) }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.1) : (hovering ? Color.white.opacity(0.07) : Theme.sidebarCard)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Theme.brand.opacity(0.5) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Tonight's shortlist")
    }
}

/// What Reel is doing in the background ("Reading Films…", "Finding film info… 3 of 20"),
/// then what it found ("3 new films on Films"). Its own view, so progress updates redraw
/// only this line.
struct SidebarStatus: View {
    @Environment(AppModel.self) private var model
    let showArrivals: () -> Void

    private var isIdle: Bool { model.reading.isEmpty && model.work == nil && model.finished == nil && model.craftPending == 0 }

    var body: some View {
        Group {
            if let reading = model.reading.sorted(by: { $0.key < $1.key }).first?.value {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(reading).monospacedDigit()
                }
                .transition(.opacity)
            } else if let work = model.work {
                VStack(alignment: .leading, spacing: 5) {
                    Text(work.text).monospacedDigit()
                    ProgressView(value: work.fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .tint(Theme.brand)
                        .animation(.easeOut(duration: 0.3), value: work.done)
                }
                .transition(.opacity)
            } else if let finished = model.finished {
                Button(action: showArrivals) {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                        Text(finished)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.count(.newArrivals) == 0)
                .help(model.count(.newArrivals) > 0 ? "Show New Arrivals" : "")
                .transition(.opacity)
            } else if model.craftPending > 0 {
                // Quietly, after everything else: how each film was shot, for searching by craft.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("Reading how films were shot · \(model.craftPending) to go").monospacedDigit()
                }
                .help("For searching by craft (anamorphic, 16mm, Steadicam…) and the Shot on filter")
                .transition(.opacity)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, isIdle ? 0 : 10)
        .animation(.easeOut(duration: 0.2), value: isIdle)
    }
}

struct SidebarRow: View {
    let title: String
    let icon: String?
    let tint: Color?
    let count: Int?
    /// Draws attention to the count (New Arrivals).
    var countTint: Color? = nil
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: isSelected ? filled(icon) : icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Theme.brand : (tint ?? Color.secondary))
                        .frame(width: 18)
                }
                Text(title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.82))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    if let countTint {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(countTint)
                    } else {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(tint ?? Color.secondary.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : (hovering ? Color.white.opacity(0.045) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func filled(_ symbol: String) -> String {
        ["bookmark", "heart", "checkmark.circle", "questionmark.circle", "externaldrive", "star", "safari", "shippingbox",
         "exclamationmark.triangle", "moon"].contains(symbol) ? symbol + ".fill" : symbol
    }
}
#endif
