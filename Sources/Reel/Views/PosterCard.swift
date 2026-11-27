#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

// MARK: - Banner

/// Large backdrop banner for one film, like the top of the Apple TV app.
struct FeaturedBanner: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem
    let open: () -> Void
    let showTrailer: () -> Void
    static let height: CGFloat = 440

    var body: some View {
        let film = item.main
        VStack(alignment: .leading, spacing: 12) {
            TitleArt(film: film, maxWidth: 400, maxHeight: 110, fontSize: 40)
            HStack(spacing: 16) {
                Text(Format.metaLine(film))
                    .foregroundStyle(Theme.secondaryText)
                RatingStrip(film: film)
            }
            .font(.system(size: 13))
            // The whole synopsis: what the film is about, to decide from here.
            if let overview = film.tmdb?.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 600, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button(action: open) {
                    Label("Details", systemImage: "info.circle")
                }
                .buttonStyle(PrimaryCapsuleStyle())
                if model.offersTrailer(for: film) {
                    Button {
                        showTrailer()
                    } label: {
                        Label(model.trailerLabel(for: film), systemImage: "play.rectangle")
                    }
                    .buttonStyle(SecondaryCapsuleStyle())
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.top, 76)
        .padding(.bottom, 28)
        // At least the usual height; a long synopsis makes the banner taller instead of being cut.
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .bottomLeading)
        // Anywhere on the picture opens the film (the buttons do their own thing).
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .background {
            Color.black
                .overlay { FocusedBackdrop(path: film.tmdb?.backdropPath) }
                .clipped()
                .overlay {
                    LinearGradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0)], startPoint: .leading, endPoint: .center)
                }
                .overlay {
                    // Darker along the top, so the label there reads on any picture.
                    LinearGradient(stops: [.init(color: Color.black.opacity(0.5), location: 0), .init(color: .clear, location: 0.3),
                                           .init(color: .clear, location: 0.5), .init(color: Theme.background, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .overlay(alignment: .topLeading) {
            Label("From Your Library", systemImage: "film.stack")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
                .padding(.leading, 32)
                .padding(.top, 24)
        }
        .clipped()
    }
}

// MARK: - Poster card

/// Loads the posters of the next rows while the grid scrolls, so they're in memory before they
/// come into view (instead of keeping the whole library in memory, which doesn't fit). Only asks
/// again once the scroll has moved past most of what it read last time.
@MainActor
final class PosterReadAhead {
    private var warmed: Range<Int> = 0..<0
    private var listID: [String] = []

    func warm(at index: Int, in list: [LibraryItem]) {
        // A different list (another shelf, sort or search) starts over.
        let id = [list.first?.id ?? "", list.last?.id ?? "", String(list.count)]
        if id != listID {
            listID = id
            warmed = 0..<0
        }
        // Ask again only when fewer than ~5 rows are ready ahead (or the scroll went back up).
        let needAhead = index + 30 > warmed.upperBound && warmed.upperBound < list.count
        let needBehind = index - 6 < warmed.lowerBound && warmed.lowerBound > 0
        guard warmed.isEmpty || needAhead || needBehind else { return }
        let range = max(0, index - 12)..<min(list.count, index + 48)
        let wanted = list[range].compactMap { item in
            item.main.tmdb?.posterPath.map { (path: $0, monochrome: false) }
        }
        warmed = range
        ImageStore.shared.warm(wanted, .poster)
    }
}

/// A line that replaces the caption under a poster.
struct CardNote: Equatable {
    let text: String
    let symbol: String?
    let tint: Color?
}

/// Under the pointer: IMDb, Rotten Tomatoes and Metacritic (all three, smaller or on two rows
/// when a small poster can't fit them on one) and when it would end (with subtitles). Only built
/// while the pointer is on it.
struct PosterHoverRatings: View {
    let film: FilmEntry
    let runtime: Int?

    var body: some View {
        let ends = Format.endsLine(film, runtime: runtime, quality: false)
        let hasRatings = PosterRatings.has(film)
        if hasRatings || ends != nil {
            VStack(alignment: .leading, spacing: 7) {
                if hasRatings {
                    PosterRatings(film: film, spacing: 7, keepsAll: true)
                        .environment(\.ratingScale, 0.85)
                }
                if let ends {
                    Text(ends)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 34)
            .padding(.bottom, 10)
            .background(
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
            )
        }
    }
}

/// The scores of a film outside the library over the bottom of its poster, under the pointer
/// (1.11.4): Wikidata's and IMDb's, as soon as the card appeared (see `ScoreBook`); TMDB's vote
/// until they're in.
struct DiscoverHoverRatings: View {
    @Environment(AppModel.self) private var model
    let id: Int
    let tmdbVote: Double?

    var body: some View {
        PosterRatings(ratings: model.scores.ratings[id], tmdbVote: tmdbVote, spacing: 7, keepsAll: true)
            .environment(\.ratingScale, 0.85)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 34)
            .padding(.bottom, 10)
            .background(LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.88)], startPoint: .top, endPoint: .bottom))
    }
}

/// A card outside the library grid tracks the pointer and has a menu of its own.
private struct OwnPointer<Menu: View>: ViewModifier {
    let on: Bool
    @Binding var hovering: Bool
    let item: LibraryItem
    let scroll: ScrollState
    @ViewBuilder let menu: () -> Menu

    func body(content: Content) -> some View {
        if on {
            content
                .scrollAwareHover($hovering) { [scroll, item] inside in
                    // The poster under the pointer, for Space.
                    if inside { scroll.pointed = item } else if scroll.pointed?.id == item.id { scroll.pointed = nil }
                }
                .contextMenu { menu() }
        } else {
            content
        }
    }
}

struct PosterCard: View, Equatable {
    @Environment(AppModel.self) private var model
    @Environment(ScrollState.self) private var scroll
    /// In the library grid: its one pointer tracker lifts the card (see `GridPointer`).
    @Environment(\.gridPointer) private var grid
    let item: LibraryItem
    var note: CardNote? = nil
    /// Arrived in the last two weeks and not watched: a NEW tag on the poster.
    var isNew = false
    /// Opens "This Is an Extra Of…" (the grid shows the sheet); not offered when nil.
    var regroup: (() -> Void)? = nil
    /// Opens Quick Look; not offered when nil.
    var preview: (() -> Void)? = nil
    @State private var hovering = false

    /// This film's notes only: a change to another film never redraws this card.
    private var record: PersonalRecord { model.record(forKey: item.id) }
    /// Lifted under the pointer, never while scrolling. The shadow is only drawn when lifted.
    private var lifted: Bool { grid.map { $0.box(item.id).lifted } ?? hovering }

    /// Cards only redraw when what they show changes (their own state still updates them).
    nonisolated static func == (lhs: PosterCard, rhs: PosterCard) -> Bool {
        lhs.item.id == rhs.item.id && lhs.item.stamp == rhs.item.stamp && lhs.note == rhs.note && lhs.isNew == rhs.isNew
    }

    var body: some View {
        card
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 9) {
            poster
                .background {
                    if lifted {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black)
                            .shadow(color: Color.black.opacity(0.6), radius: 18, y: 12)
                    }
                }
                .scaleEffect(lifted ? 1.04 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: lifted)

            // Title; year, length and director (the ratings show under the pointer).
            VStack(alignment: .leading, spacing: 3) {
                Text(item.main.displayTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                caption
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .modifier(OwnPointer(on: grid == nil, hovering: $hovering, item: item, scroll: scroll) { menu })
    }

    /// Built from this card's own data only (its film and its notes), so it costs nothing extra
    /// while scrolling and redraws with the card.
    @ViewBuilder
    private var menu: some View {
        let film = item.main
        Button("Play") { model.play(film) }
            .disabled(!item.isOnline)
        Button(record.watched ? "Mark as Unwatched" : "Mark as Watched") {
            model.toggle(\.watched, for: film)
        }
        // Built from the card's own data: no library-wide work while cards are drawn.
        Menu("Play With") {
            ForEach(PlayerChoice.installed) { player in
                Button(player.title) { model.play(film, with: player) }
            }
        }
        .disabled(!item.isOnline)
        Button(model.isTonight(item.id) ? "Remove from Tonight" : "Add to Tonight") { model.toggleTonight(item.id) }
        Button("Show in Finder") { model.showInFinder(film) }
            .disabled(!item.isOnline)
        if let preview {
            Button("Quick Look", action: preview)
        }
        Divider()
        if let regroup {
            Button("This Is an Extra Of…", action: regroup)
        }
        if model.isRegrouped(film.relativePath) {
            Button("Undo Regrouping") { model.resetGrouping(film.relativePath) }
        }
    }

    /// In colour whether or not its drive is connected (the line under it says when it isn't),
    /// with NEW while it's new; the file's quality is left for the film's page.
    private var poster: some View {
        Poster(path: item.main.tmdb?.posterPath, title: item.main.displayTitle, cornerRadius: 12)
            .overlay(alignment: .bottom) {
                // Rounded at the bottom like the poster; only this card, only while lifted (the
                // poster itself comes framed, so the card isn't clipped while scrolling, 1.11).
                if lifted {
                    PosterHoverRatings(film: item.main, runtime: item.runtime)
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous))
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                // Under the pointer: add to (or take off) tonight's shortlist in one click.
                if lifted {
                    TonightButton(key: item.id, size: 30).padding(7).transition(.opacity)
                } else {
                    marks
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isNew && !lifted {
                    Text("NEW")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.brand))
                        .padding(9)
                }
            }
    }

    /// "2017 · 2h 44m · Denis Villeneuve": what the film is, at a glance.
    @ViewBuilder
    private var caption: some View {
        if let note {
            HStack(spacing: 4) {
                if let symbol = note.symbol { Image(systemName: symbol).font(.system(size: 9.5)) }
                Text(note.text)
            }
            .foregroundStyle(note.tint ?? Color.secondary)
        } else if item.main.matchState.needsCheck {
            Text("Check match").foregroundStyle(Color.orange)
        } else {
            let director = item.main.tmdb?.directors.first
            let line = [Format.glanceLine(year: item.main.displayYear, runtime: item.runtime), director]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            Text(item.isOnline ? line : (line.isEmpty ? "Drive not connected" : line + " · Offline"))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var marks: some View {
        let tonight = model.isTonight(item.id)
        if record.favorite || record.watched || record.watchlist || tonight {
            HStack(spacing: 5) {
                if tonight { Image(systemName: "moon.fill") }
                if record.watchlist && !record.watched { Image(systemName: "bookmark.fill") }
                if record.favorite { Image(systemName: "heart.fill").foregroundStyle(Color.pink) }
                if record.watched { Image(systemName: "checkmark") }
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .padding(8)
        }
    }
}
#endif
