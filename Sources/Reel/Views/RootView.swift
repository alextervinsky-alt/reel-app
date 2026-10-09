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
    @State private var path = NavigationPath()
    /// The desk's search while Cinema mode has the field (put back when Cinema mode ends).
    @State private var deskSearch = ""

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
                CinemaView(searchText: $searchText, query: query).transition(.opacity)
            }
            if let trailer = model.trailer {
                TrailerOverlay(request: trailer) { if model.trailer == trailer { model.trailer = nil } }
                    .transition(.opacity)
            }
        }
        // Cinema mode fills the screen: the toolbar (window buttons and search) slides in over it
        // when the pointer reaches the top, like any full-screen app, and is see-through there.
        // A trailer filling the screen does the same.
        .toolbarBackgroundVisibility(model.cinemaMode || model.trailerFillsScreen ? .hidden : .automatic, for: .windowToolbar)
        .windowToolbarFullScreenVisibility(model.cinemaMode || model.trailerFillsScreen ? .onHover : .automatic)
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
        .sheet(item: Binding(get: { model.ratingPrompt }, set: { model.ratingPrompt = $0 })) { prompt in
            HowWasItSheet(prompt: prompt)
        }
    }

    private var desk: some View {
        NavigationSplitView {
            SidebarView(selection: shelf, onSelect: select)
                .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 300)
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
                            LibraryGridView(shelf: shelf, searchText: $searchText, query: query, sort: $sort,
                                            moods: $moods, length: $length, language: $language, path: $path)
                        }
                    }
                }
                .background(Theme.background)
                .navigationDestination(for: FilmRoute.self) { route in
                    FilmPage(filmID: route.id)
                }
                .navigationDestination(for: PersonRoute.self) { route in
                    PersonPage(route: route)
                }
                .navigationDestination(for: DiscoverRoute.self) { route in
                    DiscoverListPage(list: route.list, mood: route.mood)
                }
                .navigationDestination(for: ListRoute.self) { route in
                    ListPage(kind: route.kind)
                }
                .navigationDestination(for: FranchiseRoute.self) { route in
                    FranchisePage(route: route)
                }
                .navigationDestination(for: SimilarRoute.self) { route in
                    MoreLikeThisPage(route: route)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let notice = model.notice {
                    NoticeBar(text: notice) { model.notice = nil }
                }
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
        .onChange(of: searchText) {
            guard !searchText.isEmpty, !model.cinemaMode else { return }
            if !path.isEmpty { path = NavigationPath() }
            if !shelf.isLibrary { shelf = .all }
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
                VStack(alignment: .leading, spacing: 24) {
                    brand
                    // In the order you use them: choosing tonight's film, your library, finding more.
                    section("Tonight") {
                        row(.recommended, "Recommended", icon: "wand.and.stars")
                        row(.tonight, "Tonight", icon: "moon", highlightCount: true)
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
                        VStack(alignment: .leading, spacing: 2) {
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
                    if !model.drives.isEmpty {
                        section("Drives") {
                            ForEach(model.drives) { drive in
                                driveRow(drive)
                            }
                            // Only when something needs fixing.
                            if model.checkCount > 0 {
                                row(.needsCheck, "Check Matches", icon: "questionmark.circle", tint: .orange)
                            }
                            if model.count(.notOnBackup) > 0 {
                                row(.notOnBackup, "Not on Backup", icon: "exclamationmark.triangle", tint: .orange)
                                    .help("Films on your main drive without a full copy on the Backup")
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            SidebarStatus { onSelect(.newArrivals) }
            footer
        }
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

    private var brand: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "film")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .shadow(color: Theme.brand.opacity(0.35), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Reel")
                    .font(.system(size: 19, weight: .bold))
                Text(model.count(.all) == 1 ? "1 film" : "\(model.count(.all)) films")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(.tertiary)
            .padding(.leading, 10)
            .padding(.bottom, 4)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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
        return SidebarRow(title: drive.name, icon: "externaldrive", tint: nil, count: nil,
                          badge: drive.isBackup ? "Backup" : nil, isSelected: selection == .drive(drive.id), status: online) {
            onSelect(.drive(drive.id))
        }
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
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

/// What Reel is doing in the background ("Reading Films…", "Finding film info… 3 of 20"),
/// then what it found ("3 new films on Films"). Its own view, so progress updates redraw
/// only this line.
struct SidebarStatus: View {
    @Environment(AppModel.self) private var model
    let showArrivals: () -> Void

    private var isIdle: Bool { model.reading.isEmpty && model.work == nil && model.finished == nil }

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
    /// A small tag after the title ("Backup").
    var badge: String? = nil
    let isSelected: Bool
    /// Connected / not connected dot for drives.
    var status: Bool? = nil
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
                if let badge {
                    Text(badge.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().strokeBorder(Color.secondary.opacity(0.45)))
                        .fixedSize()
                }
                Spacer(minLength: 4)
                if let status {
                    Circle()
                        .fill(status ? Color.green : Color.white.opacity(0.25))
                        .frame(width: 7, height: 7)
                } else if let count, count > 0 {
                    if let countTint {
                        Text("\(count)")
                            .font(.system(size: 10.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 18, minHeight: 17)
                            .background(Capsule().fill(countTint))
                    } else {
                        Text("\(count)")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(tint ?? Color.secondary.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.11) : (hovering ? Color.white.opacity(0.05) : Color.clear))
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
