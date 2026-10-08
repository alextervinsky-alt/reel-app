#if os(macOS)
import SwiftUI
import ReelCore

/// Cinema mode's home: mood chips and rows of large posters (Tonight, Recommended, New Arrivals,
/// a row per genre…). The chip narrows every row to that mood. Pointer first: everything is a
/// large click target, and the poster under the pointer shows its end time, verdict and a
/// Tonight button. Arrow keys move the highlight too, Return opens.
/// The rows are worked out once, the highlight lives below, so moving the pointer never sorts
/// the library again, and nor does a trailer or film page opening over it.
struct CinemaHome: View {
    /// False while something is open over it (its keys then belong to that).
    let active: Bool
    let open: (String) -> Void

    var body: some View {
        CinemaHomeRows(open: open)
            .environment(\.cinemaHomeActive, active)
    }
}

/// The rows (kept by the model until what they show changes: the library, Tonight, the mood).
private struct CinemaHomeRows: View {
    @Environment(AppModel.self) private var model
    let open: (String) -> Void

    var body: some View {
        CinemaHomeContent(rows: model.cinemaRows(for: model.recommendedChoice), open: open)
    }
}

private struct CinemaHomeActiveKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    /// Whether Cinema mode's home has the keys (nothing open over it).
    var cinemaHomeActive: Bool {
        get { self[CinemaHomeActiveKey.self] }
        set { self[CinemaHomeActiveKey.self] = newValue }
    }
}

private struct CinemaHomeContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.cinemaHomeActive) private var active
    let rows: [CinemaRow]
    let open: (String) -> Void
    /// The highlighted poster, by row and film (not position, so rows coming and going, or a
    /// film leaving Tonight, never move the highlight to another film).
    @State private var selection: (row: String, item: String)?
    /// True when the arrow keys moved the highlight: only then do the rows scroll to it. The
    /// pointer only highlights, so nothing moves away from under it.
    @State private var followSelection = false

    var body: some View {
        Group {
            if isSnapshot {
                VStack(alignment: .leading, spacing: 40) { content }
                    .padding(.top, 130)
                    .snapshotPage()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Lazy: only the rows in view are built when the highlight moves.
                        LazyVStack(alignment: .leading, spacing: 40) { content }
                            .padding(.top, 130)
                            .padding(.bottom, 80)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: selection?.row) { _, row in
                        guard followSelection, let row else { return }
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(row, anchor: .center) }
                    }
                }
            }
        }
        .onReelKey { key in active && move(key) }
    }

    @ViewBuilder
    private var content: some View {
        header
        if rows.isEmpty {
            Text("Films show up here once Reel has found their info.")
                .font(.system(size: Cinema.body))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Cinema.gutter)
        }
        ForEach(rows) { row in
            CinemaRowView(title: row.title, items: row.items,
                          selected: selection?.row == row.id ? row.items.firstIndex { $0.id == selection?.item } : nil,
                          followSelection: followSelection,
                          showsReasons: row.id == "recommended" || row.id == "loved",
                          hover: { index in
                              guard row.items.indices.contains(index) else { return }
                              followSelection = false
                              selection = (row.id, row.items[index].id)
                          },
                          open: { open($0.main.id) })
                .id(row.id)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("What shall we watch?")
                .font(.system(size: Cinema.title, weight: .bold))
            if model.recommendedChoices.count > 1 {
                CinemaMoodRow(choices: model.recommendedChoices, selected: model.recommendedChoice) { choice in
                    withAnimation(.easeOut(duration: 0.25)) { model.chooseRecommended(choice) }
                }
            }
        }
        .padding(.horizontal, Cinema.gutter)
    }

    /// Arrow keys move the highlight (the first press shows it). On the highlighted poster:
    /// Return opens it, Space plays its trailer (or opens it), T adds it to Tonight.
    private func move(_ key: ReelKey) -> Bool {
        guard !rows.isEmpty else { return false }
        var row = selection.flatMap { s in rows.firstIndex { $0.id == s.row } }
        let item = selection.flatMap { s in row.flatMap { rows[$0].items.firstIndex { $0.id == s.item } } }
        var index = item ?? 0
        let shown = row != nil && item != nil
        switch key {
        case .left where shown: index -= 1
        case .right where shown: index += 1
        case .up where shown: row = row.map { $0 - 1 }
        case .down where shown: row = row.map { $0 + 1 }
        case .left, .right, .up, .down: break
        case .enter, .space, .tonight:
            guard shown, let row else { return false }
            return CinemaActions.perform(key, on: rows[row].items[index], model: model, open: open)
        case .escape, .fullScreen: return false
        }
        let r = min(max(row ?? 0, 0), rows.count - 1)
        let i = min(max(index, 0), rows[r].items.count - 1)
        followSelection = true
        selection = (rows[r].id, rows[r].items[i].id)
        return true
    }
}

/// What Return, Space and T do on a highlighted poster, the same on every Cinema page.
@MainActor
enum CinemaActions {
    static func perform(_ key: ReelKey, on item: LibraryItem, model: AppModel, open: (String) -> Void) -> Bool {
        switch key {
        case .enter:
            open(item.main.id)
        case .space:
            if model.offersTrailer(for: item.main) {
                model.showTrailer(for: item.main, offersFilmPage: true)
            } else {
                open(item.main.id)
            }
        case .tonight:
            model.toggleTonight(item.id)
        default:
            return false
        }
        return true
    }
}

/// One row: a title and large posters that scroll sideways.
struct CinemaRowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    let title: String
    let items: [LibraryItem]
    /// The highlighted poster (keys or pointer).
    let selected: Int?
    /// Scroll to the highlighted poster (it was moved with the keys).
    var followSelection = false
    /// Recommended and Like the Films You Loved: each poster says why it's there.
    var showsReasons = false
    /// A line under a poster in place of the year ("Director · Yorgos Lanthimos").
    var captions: [String: String] = [:]
    let hover: (Int) -> Void
    let open: (LibraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: Cinema.rowTitle, weight: .bold))
                .padding(.horizontal, Cinema.gutter)
            if isSnapshot {
                tiles.padding(.horizontal, Cinema.gutter).snapshotRow()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        tiles
                            .padding(.horizontal, Cinema.gutter)
                            .padding(.vertical, 14)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: selected) { _, index in
                        guard followSelection, let index, items.indices.contains(index) else { return }
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(items[index].id, anchor: .center) }
                    }
                }
            }
        }
    }

    /// Lazy on screen; all at once when drawn to an image.
    @ViewBuilder
    private var tiles: some View {
        if isSnapshot {
            HStack(alignment: .top, spacing: 26) { tileViews }
        } else {
            LazyHStack(alignment: .top, spacing: 26) { tileViews }
        }
    }

    /// Each poster is known by its film, never by its place: a row whose films change (Tonight,
    /// as films are added) then shows its own films. (Known by place, a new Tonight row took the
    /// posters that were first in the row below it.)
    private var tileViews: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            CinemaPosterTile(item: item, marks: CinemaTileMarks(model: model, key: item.id),
                             reason: showsReasons ? model.pickReason(forKey: item.id)?.short : nil,
                             caption: captions[item.id], selected: selected == index) {
                open(item)
            }
            .equatable()
            .onHover { if $0 { hover(index) } }
        }
    }
}

/// A row that keeps its own pointer highlight (rows on a film page).
struct CinemaHoverRow: View {
    let title: String
    let items: [LibraryItem]
    var captions: [String: String] = [:]
    let open: (String) -> Void
    /// By film, so films arriving in the row never move the highlight to another one.
    @State private var selected: String?

    var body: some View {
        CinemaRowView(title: title, items: items, selected: items.firstIndex { $0.id == selected }, captions: captions,
                      hover: { index in if items.indices.contains(index) { selected = items[index].id } },
                      open: { open($0.main.id) })
    }
}

/// What a tile shows about your own notes: on Tonight, on the watchlist, watched.
struct CinemaTileMarks: Equatable {
    let tonight: Bool
    let watchlist: Bool
    let watched: Bool

    @MainActor
    init(model: AppModel, key: String) {
        let record = model.record(forKey: key)
        tonight = model.isTonight(key)
        watchlist = record.watchlist
        watched = record.watched
    }
}

/// A large poster with two quiet lines under it: title, and year · running time. Highlighted
/// (pointer or keys) the ratings take the second line, and the poster shows when it would end,
/// the moon for Tonight and a trailer bar along its bottom edge.
struct CinemaPosterTile: View, Equatable {
    let item: LibraryItem
    let marks: CinemaTileMarks
    /// Why it's offered, short ("Director of Her"), on the poster's bottom edge.
    let reason: String?
    /// Replaces the year line ("Director · Yorgos Lanthimos").
    let caption: String?
    let selected: Bool
    let open: () -> Void

    nonisolated static func == (lhs: CinemaPosterTile, rhs: CinemaPosterTile) -> Bool {
        lhs.item.id == rhs.item.id && lhs.item.stamp == rhs.item.stamp && lhs.selected == rhs.selected
            && lhs.marks == rhs.marks && lhs.reason == rhs.reason && lhs.caption == rhs.caption
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                Poster(path: item.main.tmdb?.posterPath, title: item.main.displayTitle, cornerRadius: 14,
                       monochrome: !item.isOnline)
                    .overlay(alignment: .bottom) {
                        if selected {
                            CinemaTileHighlight(item: item).transition(.opacity)
                        } else if let reason {
                            reasonLabel(reason)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            TonightButton(key: item.id, size: 46).padding(10).transition(.opacity)
                        } else {
                            markBadges
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: selected ? 4 : 0)
                    }
                    .scaleEffect(selected ? 1.05 : 1)
                    .shadow(color: Color.black.opacity(selected ? 0.55 : 0), radius: 18, y: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.main.displayTitle)
                        .font(.system(size: Cinema.body, weight: .semibold))
                        .lineLimit(1)
                    // Highlighted, the ratings take the year line's place, clear of the poster.
                    Group {
                        if selected, PosterRatings.has(item.main) {
                            PosterRatings(film: item.main, spacing: 10)
                                .environment(\.ratingScale, 1.2)
                        } else {
                            Text(caption ?? Format.glanceLine(year: item.main.displayYear, runtime: item.runtime))
                                .font(.system(size: Cinema.body))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: 30, alignment: .leading)
                }
            }
            .frame(width: Cinema.posterWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }

    private func reasonLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Cinema.body, weight: .semibold))
            .foregroundStyle(Theme.brand)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.78))
    }

    @ViewBuilder
    private var markBadges: some View {
        if marks.tonight || marks.watchlist || marks.watched {
            HStack(spacing: 7) {
                if marks.tonight { Image(systemName: "moon.fill") }
                if marks.watchlist && !marks.watched { Image(systemName: "bookmark.fill") }
                if marks.watched { Image(systemName: "checkmark") }
            }
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .padding(10)
        }
    }
}

/// Over the highlighted poster: when it would end (and its subtitles), then a full-width
/// trailer bar when the film has an official trailer that plays here. Only exists for the one
/// highlighted poster.
private struct CinemaTileHighlight: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem

    var body: some View {
        let film = item.main
        let trailer = model.offersTrailer(for: film)
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                if let ends = Format.endsLine(film, runtime: item.runtime, quality: false) {
                    Text(ends)
                        .font(.system(size: Cinema.body, weight: .semibold))
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .padding(.top, 44)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.9)],
                                                   startPoint: .top, endPoint: .bottom))
                }
                if trailer {
                    // Grows into the player from this poster; takes the click before the poster.
                    let frame = geometry.frame(in: .global)
                    Label(model.trailerLabel(for: film), systemImage: "play.fill")
                        .font(.system(size: Cinema.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white)
                        .foregroundStyle(Color.black)
                        .contentShape(Rectangle())
                        .highPriorityGesture(TapGesture().onEnded {
                            model.showTrailer(for: film, from: frame, offersFilmPage: true)
                        })
                        .accessibilityAddTraits(.isButton)
                }
            }
            .foregroundStyle(Color.white)
        }
    }
}

/// Any · Feel-good · Dark…, as large chips.
struct CinemaMoodRow: View {
    @Environment(\.isSnapshot) private var isSnapshot
    let choices: [MoodChoiceCount]
    let selected: MoodChoice
    let choose: (MoodChoice) -> Void

    var body: some View {
        if isSnapshot {
            chips.snapshotRow()
        } else {
            ScrollView(.horizontal) { chips }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
        }
    }

    private var chips: some View {
        HStack(spacing: 12) {
            ForEach(choices) { entry in
                CinemaChip(title: entry.choice.title, symbol: entry.choice.symbol, isOn: entry.choice == selected) {
                    choose(entry.choice)
                }
            }
        }
    }
}
#endif
