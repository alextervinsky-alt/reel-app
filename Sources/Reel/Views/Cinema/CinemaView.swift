#if os(macOS)
import SwiftUI
import ReelCore

/// Cinema mode's three places, as tabs at the top.
enum CinemaTab: Hashable {
    case home, tonight, library
}

/// Cinema mode: Reel as a 10-foot view for the TV. Separate from the desk views, so turning it on
/// or off never changes them; the desk keeps its place, search and filters. The search field
/// (in the toolbar that appears at the top of the screen) searches All Films here.
struct CinemaView: View {
    @Environment(AppModel.self) private var model
    /// The desk's search, shared: typing in Cinema mode shows the matches in All Films.
    @Binding var searchText: String
    let query: String
    @State private var tab: CinemaTab
    /// Film pages opened on top of the tab (film IDs), most recent last.
    @State private var path: [String]

    init(searchText: Binding<String>, query: String, tab: CinemaTab = .home, path: [String] = []) {
        _searchText = searchText
        self.query = query
        _tab = State(initialValue: tab)
        _path = State(initialValue: path)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            // Home stays alive under the other places, and the open tab under a film page, so
            // coming back keeps its place, filters and scroll position.
            CinemaHome(active: path.isEmpty && tab == .home && model.trailer == nil, open: open)
                .opacity(path.isEmpty && tab == .home ? 1 : 0)
                .allowsHitTesting(path.isEmpty && tab == .home)
            Group {
                switch tab {
                case .home: EmptyView()
                case .tonight: CinemaTonight(open: open)
                case .library:
                    CinemaLibrary(searchText: $searchText, query: query,
                                  active: path.isEmpty && model.trailer == nil, open: open)
                }
            }
            .opacity(path.isEmpty ? 1 : 0)
            .allowsHitTesting(path.isEmpty)
            .transition(.opacity)
            if let id = path.last {
                CinemaFilmPage(filmID: id, active: model.trailer == nil, open: open)
                    .id(id)
                    .transition(.opacity)
            }
        }
        // Edge to edge: nothing of the window shows above it (in full screen the toolbar slides
        // over it when the pointer reaches the top of the screen).
        .ignoresSafeArea()
        // The bar itself stays clear of a toolbar that's showing.
        .overlay(alignment: .top) { topBar }
        .animation(.easeOut(duration: 0.22), value: path)
        .animation(.easeOut(duration: 0.22), value: tab)
        .onChange(of: model.filmToOpen) { _, id in
            // Open Film under a trailer.
            guard let id else { return }
            model.filmToOpen = nil
            open(id)
        }
        .onChange(of: query) { _, new in
            // Typing a search shows the matches.
            if !new.isEmpty {
                path = []
                tab = .library
            }
        }
        .onReelKey { key in
            // A trailer or a filter panel on top takes Esc first.
            guard key == .escape, model.trailer == nil, !model.cinemaPanelOpen else { return false }
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

    private func open(_ filmID: String) {
        // Opening the page you're on (a film from its own More Like This) does nothing.
        if path.last != filmID { path.append(filmID) }
    }

    private func show(_ place: CinemaTab) {
        path = []
        tab = place
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            if !path.isEmpty {
                Button {
                    path.removeLast()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(CinemaButtonStyle())
            } else {
                CinemaChip(title: "For You", symbol: "sparkles", isOn: tab == .home) { show(.home) }
                let count = model.tonightItems.count
                CinemaChip(title: count == 0 ? "Tonight" : "Tonight · \(count)",
                           symbol: "moon", isOn: tab == .tonight) { show(.tonight) }
                CinemaChip(title: "All Films", symbol: "square.grid.3x3", isOn: tab == .library) { show(.library) }
            }
            Spacer()
            ExitCinemaButton { model.setCinemaMode(false) }
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
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Exit Cinema (⇧⌘C)")
        .accessibilityLabel("Exit Cinema")
    }
}
#endif
