#if os(macOS)
import SwiftUI
import ReelCore

extension Format {
    /// The corner of a poster: "4K DV", "4K HDR", "1080p" (from the file name; nil when it says nothing).
    static func posterTag(_ film: FilmEntry) -> String? {
        let resolution = film.parsed.resolution.map { $0 == "2160p" ? "4K" : $0 }
        let range: String? = switch film.parsed.dynamicRange {
        case .dolbyVision: "DV"
        case .sdr: nil
        default: "HDR"
        }
        let parts = [resolution, range].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// A small dark label on a poster ("4K HDR").
struct QualityTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black.opacity(0.6)))
    }
}

/// "IMDb 8.5  RT 77%  MC 66": each source's name in its own colour, small, the number plain.
/// TMDB's score when there are none of those.
struct RatingsLine: View {
    let film: FilmEntry
    var size: CGFloat = 11

    private struct Part: Identifiable {
        let name: String
        let tint: Color
        let value: String
        var id: String { name }
    }

    var body: some View {
        HStack(spacing: 9) {
            ForEach(parts) { part in
                (Text(part.name).foregroundStyle(part.tint).fontWeight(.semibold) + Text(" " + part.value))
            }
        }
        .font(.system(size: size))
        .monospacedDigit()
        .foregroundStyle(Color.white.opacity(0.88))
        .lineLimit(1)
    }

    private var parts: [Part] {
        let r = film.ratings
        var list: [Part] = []
        if let imdb = r?.imdb { list.append(Part(name: "IMDb", tint: Theme.imdb, value: Format.rating(imdb))) }
        if let rt = r?.rottenTomatoes { list.append(Part(name: "RT", tint: Theme.rottenTomatoes, value: "\(rt)%")) }
        if let mc = r?.metacritic { list.append(Part(name: "MC", tint: Theme.metacritic, value: "\(mc)")) }
        if list.isEmpty, let vote = film.tmdb?.voteAverage, vote > 0 {
            list.append(Part(name: "TMDB", tint: Color(red: 0.01, green: 0.71, blue: 0.89), value: Format.rating(vote)))
        }
        return list
    }
}

/// Over a poster under the pointer: the premise, when it would end (and its subtitles), and
/// Play and the trailer. Only built for the one poster under the pointer.
struct HoverDetails: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem

    var body: some View {
        let film = item.main
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            if let overview = film.tmdb?.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 11.5))
                    .lineSpacing(1.5)
                    .lineLimit(4)
                    .foregroundStyle(Color.white.opacity(0.88))
            }
            if let ends = Format.endsLine(film, runtime: item.runtime, quality: false) {
                Text(ends)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if item.isOnline {
                    Button {
                        model.play(film)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(Capsule().fill(Color.white))
                            .foregroundStyle(Color.black)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if model.offersTrailer(for: film) {
                    Button {
                        model.showTrailer(for: film)
                    } label: {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 32, height: 28)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                            .foregroundStyle(Color.white)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(model.trailerLabel(for: film))
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(LinearGradient(stops: [.init(color: .black.opacity(0.15), location: 0), .init(color: .black.opacity(0.6), location: 0.45),
                                           .init(color: .black.opacity(0.92), location: 1)],
                                   startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - List

/// The library as a list: everything about each film side by side, sorted by the column you
/// click (title, year, length or rating). Columns that don't fit a narrow window step aside.
struct FilmList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    let items: [LibraryItem]
    @Binding var sort: LibrarySort
    /// False where the order is fixed (Not on Backup).
    let sortable: Bool
    @State private var width: CGFloat = 1100

    private var wide: Bool { width >= 1080 }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isSnapshot {
                VStack(spacing: 0) { rows }
            } else {
                LazyVStack(spacing: 0) { rows }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var rows: some View {
        ForEach(items) { item in
            NavigationLink(value: FilmRoute(id: item.main.id)) {
                FilmListRow(item: item, wide: wide)
            }
            .buttonStyle(.plain)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            column("Film", sortsBy: .title).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 58)
            column("Year", sortsBy: .year).frame(width: FilmListRow.year, alignment: .leading)
            column("Length", sortsBy: .runtime).frame(width: FilmListRow.length, alignment: .leading)
            if wide { column("Genre · Mood", sortsBy: nil).frame(width: FilmListRow.genre, alignment: .leading) }
            column("Ratings", sortsBy: .rating).frame(width: FilmListRow.ratings, alignment: .leading)
            if wide { column("Shot on", sortsBy: nil).frame(width: FilmListRow.shot, alignment: .leading) }
            column("File", sortsBy: nil).frame(width: FilmListRow.file, alignment: .leading)
            column("", sortsBy: nil).frame(width: FilmListRow.status, alignment: .leading)
        }
        .padding(.trailing, 14)
        .frame(height: 34)
        .background(Color.white.opacity(0.03))
    }

    @ViewBuilder
    private func column(_ title: String, sortsBy order: LibrarySort?) -> some View {
        let label = HStack(spacing: 4) {
            Text(title.uppercased())
            if let order, sort == order {
                Image(systemName: order == .title || order == .runtime ? "chevron.up" : "chevron.down").font(.system(size: 7, weight: .bold))
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(order != nil && sort == order ? Theme.brand : Color.secondary)
        if let order, sortable {
            Button { sort = order } label: { label.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help("Sort by \(title.lowercased())")
        } else {
            label
        }
    }
}

/// One film in the list.
struct FilmListRow: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem
    let wide: Bool
    @State private var hovering = false

    static let year: CGFloat = 58
    static let length: CGFloat = 70
    static let genre: CGFloat = 170
    static let ratings: CGFloat = 160
    static let shot: CGFloat = 170
    static let file: CGFloat = 76
    static let status: CGFloat = 92

    var body: some View {
        let film = item.main
        let record = model.record(forKey: item.id)
        HStack(spacing: 0) {
            Poster(path: film.tmdb?.posterPath, title: film.displayTitle, cornerRadius: 4)
                .frame(width: 30)
                .padding(.leading, 14)
                .padding(.trailing, 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(film.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(film.tmdb?.directors.prefix(2).joined(separator: ", ") ?? (item.isOnline ? "" : "Drive not connected"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(film.displayYear.map(String.init) ?? "").frame(width: Self.year, alignment: .leading)
            Text(item.runtime.map(Format.runtime) ?? "").frame(width: Self.length, alignment: .leading)
            if wide {
                Text(([item.shortGenre] + item.moods.prefix(1).map { Optional($0.title) }).compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.genre, alignment: .leading)
            }
            RatingsLine(film: film, size: 11.5).frame(width: Self.ratings, alignment: .leading)
            if wide {
                Text(item.shotOn.isEmpty ? "" : ShotOn.allCases.filter { item.shotOn.contains($0) }.map(\.title).joined(separator: " · "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.shot, alignment: .leading)
            }
            Group {
                if let tag = Format.posterTag(film) { QualityTag(text: tag) } else { Text("") }
            }
            .frame(width: Self.file, alignment: .leading)
            status(record).frame(width: Self.status, alignment: .leading)
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .padding(.trailing, 14)
        .frame(height: 60)
        .background(hovering ? Color.white.opacity(0.045) : Color.clear)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Play") { model.play(film) }.disabled(!item.isOnline)
            Button(model.isTonight(item.id) ? "Remove from Tonight" : "Add to Tonight") { model.toggleTonight(item.id) }
            Button(record.watched ? "Mark as Unwatched" : "Mark as Watched") { model.toggle(\.watched, for: film) }
        }
    }

    @ViewBuilder
    private func status(_ record: PersonalRecord) -> some View {
        if model.isTonight(item.id) {
            Label("Tonight", systemImage: "moon.fill").foregroundStyle(Theme.brand)
        } else if model.arrivals[item.id] != nil && !record.watched {
            Text("New").foregroundStyle(Theme.brand)
        } else if record.watched {
            Label(record.rating.map { "\($0)★" } ?? "Watched", systemImage: "checkmark").foregroundStyle(.secondary)
        } else if record.watchlist {
            Label("Watchlist", systemImage: "bookmark.fill").foregroundStyle(.secondary)
        } else {
            Text("")
        }
    }
}
#endif
