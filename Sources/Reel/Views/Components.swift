#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

enum Theme {
    /// Near-black with a hint of blue, like Apple TV.
    static let background = Color(red: 0.067, green: 0.067, blue: 0.078)
    static let panel = Color.white.opacity(0.055)
    static let hairline = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.62)
    /// Reel's own colour: a warm projector-light orange.
    static let brand = Color(red: 1.0, green: 0.45, blue: 0.28)
    static let brandGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.62, blue: 0.3), Color(red: 0.93, green: 0.25, blue: 0.33)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 17, weight: .semibold))
    }
}

enum Format {
    static func runtime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func endTime(minutes: Int) -> String {
        Date().addingTimeInterval(Double(minutes) * 60).formatted(date: .omitted, time: .shortened)
    }

    static func bytes(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    static func rating(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func votes(_ count: Int) -> String {
        count >= 1_000_000 ? String(format: "%.1fM", Double(count) / 1_000_000)
            : count >= 1_000 ? "\(count / 1_000)K" : "\(count)"
    }

    /// "2017 · R · 2h 44m · Science Fiction, Drama"
    static func metaLine(_ film: FilmEntry) -> String {
        var parts: [String] = []
        if let year = film.displayYear { parts.append(String(year)) }
        if let rated = film.ratings?.rated, rated != "Not Rated", rated != "Unrated" { parts.append(rated) }
        if let minutes = film.tmdb?.runtime, minutes > 0 { parts.append(Format.runtime(minutes)) }
        let genres = film.tmdb?.genreNames ?? []
        if !genres.isEmpty { parts.append(genres.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: "  ·  ")
    }

    /// The line under a poster: "2019 · 2h 13m".
    static func glanceLine(year: Int?, runtime: Int?) -> String {
        [year.map(String.init), runtime.flatMap { $0 > 0 ? Format.runtime($0) : nil }].compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Under a trailer: "2019 · 2h 13m · ends 23:10".
    static func decisionLine(_ film: FilmEntry) -> String {
        let runtime = film.tmdb?.runtime ?? 0
        return [glanceLine(year: film.displayYear, runtime: runtime), runtime > 0 ? "ends \(endTime(minutes: runtime))" : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// What matters on the sofa, in one line: "Ends 23:10 · English subtitles · 4K" (posters
    /// leave the quality out).
    static func endsLine(_ film: FilmEntry, runtime: Int?, quality: Bool = true) -> String? {
        let parts = [runtime.flatMap { $0 > 0 ? "Ends \(endTime(minutes: $0))" : nil }, sofaLine(film, quality: quality)]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Images

/// 2:3 poster with a quiet title card while loading or when TMDB has no poster.
struct Poster: View {
    let path: String?
    let title: String
    var kind: ImageKind = .poster
    var cornerRadius: CGFloat = 10
    /// Grey and dimmed (a film on a drive that isn't connected).
    var monochrome = false

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                CachedImage(path: path, kind: kind, monochrome: monochrome) {
                    ZStack {
                        LinearGradient(colors: [Color(white: 0.17), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                        if !title.isEmpty {
                            Text(title)
                                .font(.system(size: 14, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color.white.opacity(0.6))
                                .padding(12)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
    }
}

/// The film's title logo when TMDB has one, otherwise the title in large type.
struct TitleArt: View {
    let film: FilmEntry
    var maxWidth: CGFloat = 460
    var maxHeight: CGFloat = 130
    var fontSize: CGFloat = 46

    var body: some View {
        if let logo = film.tmdb?.logoPath {
            CachedImage(path: logo, kind: .logo, fit: true) { titleText }
                .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .bottomLeading)
                .shadow(color: Color.black.opacity(0.45), radius: 10)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(film.displayTitle)
            .font(.system(size: fontSize, weight: .bold))
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .shadow(color: Color.black.opacity(0.4), radius: 8)
    }
}

// MARK: - Ratings

/// IMDb · Rotten Tomatoes · Metacritic · TMDB, each with a small coloured tag.
struct RatingStrip: View {
    let ratings: ExternalRatings?
    let tmdbVote: Double?

    init(film: FilmEntry) {
        ratings = film.ratings
        tmdbVote = film.tmdb?.voteAverage
    }

    init(ratings: ExternalRatings?, tmdbVote: Double?) {
        self.ratings = ratings
        self.tmdbVote = tmdbVote
    }

    var body: some View {
        HStack(spacing: 16) {
            if let imdb = ratings?.imdb {
                RatingBadge(tag: "IMDb", value: Format.rating(imdb), background: Self.imdbYellow, foreground: .black)
            }
            if let rt = ratings?.rottenTomatoes {
                RatingBadge(tag: "RT", value: "\(rt)%", background: Self.tomatoColor(rt), foreground: .white)
            }
            if let mc = ratings?.metacritic {
                RatingBadge(tag: "MC", value: "\(mc)", background: Self.metacriticColor(mc), foreground: .white)
            }
            if ratings?.imdb == nil, let vote = tmdbVote, vote > 0 {
                RatingBadge(tag: "TMDB", value: Format.rating(vote), background: Color(red: 0.01, green: 0.71, blue: 0.89), foreground: .black)
            }
        }
    }

    static let imdbYellow = Color(red: 0.96, green: 0.77, blue: 0.09)

    /// Fresh red at 60% and above, rotten green below.
    static func tomatoColor(_ percent: Int) -> Color {
        percent >= 60 ? Color(red: 0.92, green: 0.2, blue: 0.13) : Color(red: 0.4, green: 0.68, blue: 0.2)
    }

    static func metacriticColor(_ score: Int) -> Color {
        score >= 61 ? Color(red: 0.4, green: 0.8, blue: 0.2)
            : score >= 40 ? Color(red: 1.0, green: 0.8, blue: 0.2) : Color(red: 1.0, green: 0.0, blue: 0.0)
    }
}

struct RatingBadge: View {
    @Environment(\.ratingScale) private var scale
    let tag: String
    let value: String
    let background: Color
    let foreground: Color

    var body: some View {
        HStack(spacing: 6 * scale) {
            Text(tag)
                .font(.system(size: 10 * scale, weight: .heavy))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5 * scale)
                .padding(.vertical, 2 * scale)
                .background(RoundedRectangle(cornerRadius: 3 * scale, style: .continuous).fill(background))
                .foregroundStyle(foreground)
            Text(value)
                .font(.system(size: 14 * scale, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .fixedSize()
    }
}

/// IMDb, Rotten Tomatoes and Metacritic on one line over or under a poster (TMDB when there
/// are none of them). When they don't all fit, Metacritic and then Rotten Tomatoes step aside,
/// so the line never breaks in two.
struct PosterRatings: View {
    let film: FilmEntry
    var spacing: CGFloat = 8

    private struct Score: Identifiable {
        let tag: String
        let value: String
        let background: Color
        let foreground: Color
        var id: String { tag }
    }

    /// Whether there's anything to show (otherwise whatever it stands in for stays).
    static func has(_ film: FilmEntry) -> Bool {
        !scores(film).isEmpty
    }

    var body: some View {
        let all = Self.scores(film)
        if !all.isEmpty {
            ViewThatFits(in: .horizontal) {
                line(all)
                if all.count > 2 { line(Array(all.prefix(2))) }
                if all.count > 1 { line(Array(all.prefix(1))) }
            }
        }
    }

    private func line(_ scores: [Score]) -> some View {
        HStack(spacing: spacing) {
            ForEach(scores) { RatingBadge(tag: $0.tag, value: $0.value, background: $0.background, foreground: $0.foreground) }
        }
    }

    private static func scores(_ film: FilmEntry) -> [Score] {
        let r = film.ratings
        var all: [Score] = []
        if let imdb = r?.imdb {
            all.append(Score(tag: "IMDb", value: Format.rating(imdb), background: RatingStrip.imdbYellow, foreground: .black))
        }
        if let rt = r?.rottenTomatoes {
            all.append(Score(tag: "RT", value: "\(rt)%", background: RatingStrip.tomatoColor(rt), foreground: .white))
        }
        if let mc = r?.metacritic {
            all.append(Score(tag: "MC", value: "\(mc)", background: RatingStrip.metacriticColor(mc), foreground: .white))
        }
        if all.isEmpty, let vote = film.tmdb?.voteAverage, vote > 0 {
            all.append(Score(tag: "TMDB", value: Format.rating(vote), background: Color(red: 0.01, green: 0.71, blue: 0.89),
                             foreground: .black))
        }
        return all
    }
}

private struct RatingScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// Rating badges drawn larger (Cinema mode), as type rather than a blurry zoom.
    var ratingScale: CGFloat {
        get { self[RatingScaleKey.self] }
        set { self[RatingScaleKey.self] = newValue }
    }
}

// MARK: - Controls

struct PrimaryCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 20)
            .frame(height: 38)
            .background(Capsule().fill(Color.white))
            .foregroundStyle(Color.black)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

struct SecondaryCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.24 : 0.14)))
            .foregroundStyle(Color.white)
            .contentShape(Capsule())
    }
}

/// Round button for Watched / Favorite / Watchlist. Fills white when on.
struct RoundToggle: View {
    let symbol: String
    var onSymbol: String? = nil
    let isOn: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? (onSymbol ?? symbol) : symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(Circle().fill(isOn ? Color.white : Color.white.opacity(0.14)))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// Adds a film to tonight's shortlist, or takes it off: a moon over a poster. It sits inside the
/// poster's own button, so it takes the click first (the film doesn't open). Reads only this
/// film's place on the list, so other posters don't redraw when it changes.
struct TonightButton: View {
    @Environment(AppModel.self) private var model
    let key: String
    var size: CGFloat = 30

    var body: some View {
        let isOn = model.isTonight(key)
        Image(systemName: isOn ? "moon.fill" : "moon")
            .font(.system(size: size * 0.42, weight: .semibold))
            .frame(width: size, height: size)
            .background(Circle().fill(isOn ? Color.white : Color.black.opacity(0.62)))
            .foregroundStyle(isOn ? Color.black : Color.white)
            .contentShape(Circle())
            .highPriorityGesture(TapGesture().onEnded {
                withAnimation(.easeOut(duration: 0.15)) { model.toggleTonight(key) }
            })
            .help(isOn ? "On tonight's shortlist (click to remove)" : "Add to Tonight")
            .accessibilityElement()
            .accessibilityLabel(isOn ? "Remove from Tonight" : "Add to Tonight")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.toggleTonight(key) }
    }
}

struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(isOn ? Color.white : Color.white.opacity(0.07)))
            .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.85))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

struct StarRating: View {
    let rating: Int?
    let onChange: (Int?) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                let filled = (rating ?? 0) >= i
                Button {
                    onChange(rating == i ? nil : i)
                } label: {
                    Image(systemName: filled ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundStyle(filled ? Color.yellow : Color.white.opacity(0.45))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .help("Your rating. Click the same star again to clear it.")
    }
}

struct Chip: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}

/// Row of posters that open the film, for collections and "More like this".
struct PosterRow: View {
    let title: String
    let items: [LibraryItem]
    /// "See Whole Series" for a franchise.
    var seeAll: FranchiseRoute?
    /// "See All" for More Like This.
    var seeSimilar: SimilarRoute?
    /// A line under a poster in place of the year ("Director · Yorgos Lanthimos").
    var captions: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Theme.sectionTitle(title)
                Spacer()
                if let seeAll {
                    link("See Whole Series", to: seeAll)
                } else if let seeSimilar {
                    link("See All", to: seeSimilar)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink(value: FilmRoute(id: item.main.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Poster(path: item.main.tmdb?.posterPath, title: item.main.displayTitle, cornerRadius: 8)
                                    .frame(width: 112)
                                Text(item.main.displayTitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .frame(width: 112, alignment: .leading)
                                if let caption = captions[item.id] {
                                    Text(caption)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 112, alignment: .leading)
                                } else if let year = item.main.displayYear {
                                    Text(String(year)).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func link(_ title: String, to route: some Hashable) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.brand)
        }
        .buttonStyle(.plain)
    }
}

struct NoticeBar: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(14)
    }
}
/// A link in running text, in Reel's colour. (A plain button: SwiftUI's own `Link` can't be
/// drawn into the CI screens, where it shows as a placeholder.)
struct TextLink: View {
    let title: String
    let url: URL

    init(_ title: String, destination: URL) {
        self.title = title
        url = destination
    }

    var body: some View {
        Button(title) { NSWorkspace.shared.open(url) }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.brand)
            .help(url.absoluteString)
    }
}
#endif
