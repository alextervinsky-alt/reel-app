#if os(macOS)
import SwiftUI
import ReelCore

/// Which rows tonight's columns show: a row none of the films has anything for is left out,
/// a row only some have stays (empty where a film has nothing), so the columns stay level.
struct TonightSlots: Equatable {
    var people = false
    var why = false
    var premise = false
    var moods = false
    var sofa = false
    var lists = false

    @MainActor
    init(_ items: [LibraryItem], model: AppModel) {
        for item in items {
            let film = item.main
            people = people || !TonightCompareColumn.people(film).isEmpty
            why = why || model.pickReason(forKey: item.id) != nil
            premise = premise || !(film.tmdb?.overview ?? "").isEmpty
            moods = moods || !item.moods.isEmpty
            sofa = sofa || Format.sofaLine(film) != nil
            lists = lists || !model.badges(for: film).isEmpty
        }
    }

    /// How wide each column can be: wider when there are only a few, so nothing is cut short.
    static func width(for count: Int, in available: CGFloat, large: Bool) -> CGFloat {
        let (narrowest, widest, gap): (CGFloat, CGFloat, CGFloat) = large ? (420, 560, 24) : (300, 400, 16)
        guard count > 0, available > 0 else { return narrowest }
        let share = (available - gap * CGFloat(count - 1)) / CGFloat(count)
        return min(widest, max(narrowest, share.rounded(.down)))
    }
}

/// One film on tonight's shortlist, as a column of fixed rows, so films side by side compare
/// line by line: picture, title, year and genres, who made it, ratings, verdict, why it's
/// offered, the premise, when it ends, moods, subtitles and quality, the lists it's on, then
/// Play (and the trailer); the × in the picture's corner takes it off the list.
/// The same column in the library (`large == false`) and in Cinema mode.
struct TonightCompareColumn: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem
    let slots: TonightSlots
    let width: CGFloat
    let chosen: Bool
    let dimmed: Bool
    let large: Bool
    let open: () -> Void

    private var textSize: CGFloat { large ? Cinema.body : 12.5 }
    private var line: CGFloat { large ? 30 : 18 }

    var body: some View {
        let film = item.main
        let verdict = ReceptionVerdict.sentence(ratings: film.ratings, tmdbVote: film.tmdb?.voteAverage,
                                                reception: film.reception, cinemaScore: film.funFacts?.cinemaScore)
        VStack(alignment: .leading, spacing: large ? 10 : 7) {
            picture(film)
            // One line (a long title shrinks a little first), so short titles leave no gap.
            Text(film.displayTitle)
                .font(.system(size: large ? 28 : 18, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: large ? 34 : 22, alignment: .leading)
            text(meta(film), lines: 1)
            if slots.people { row("person.2", Self.people(film)) }
            Group {
                if large { CinemaRatings(film: film) } else { RatingStrip(film: film).font(.system(size: 12)) }
            }
            .frame(height: line, alignment: .leading)
            text(verdict, lines: 2, color: Theme.brand, weight: .medium)
            if slots.why { text(model.pickReason(forKey: item.id)?.long, lines: 1) }
            if slots.premise {
                text(film.tmdb?.overview, lines: 3, color: Color.white.opacity(0.82))
            }
            row("clock", item.runtime.map { "\(Format.runtime($0)) · ends \(Format.endTime(minutes: $0))" })
            if slots.moods {
                row("theatermasks", item.moods.isEmpty ? nil : item.moods.prefix(3).map(\.title).joined(separator: ", "))
            }
            if slots.sofa { row("captions.bubble", Format.sofaLine(film)) }
            if slots.lists { row("laurel.leading", lists(film)) }
            buttons(film)
                .padding(.top, 4)
        }
        .padding(large ? 22 : 16)
        .frame(width: width, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: large ? 22 : 18, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: large ? 22 : 18, style: .continuous)
            .strokeBorder(chosen ? Theme.brand : Theme.hairline, lineWidth: chosen ? (large ? 4 : 2) : 1))
        .scaleEffect(chosen ? 1.02 : 1)
        .opacity(dimmed ? 0.4 : 1)
    }

    private func picture(_ film: FilmEntry) -> some View {
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                FocusedBackdrop(path: film.tmdb?.backdropPath)
                    .frame(height: large ? 180 : 150)
                    .clipShape(RoundedRectangle(cornerRadius: large ? 16 : 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the film")
            // Taking it off the list sits apart from Play, in the picture's corner.
            Button {
                withAnimation(.easeOut(duration: 0.2)) { model.toggleTonight(item.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: large ? 17 : 12, weight: .bold))
                    .frame(width: large ? 44 : 28, height: large ? 44 : 28)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .foregroundStyle(Color.white)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(large ? 10 : 8)
            .help("Remove from Tonight")
        }
    }

    /// "2021 · Science Fiction, Adventure"
    private func meta(_ film: FilmEntry) -> String {
        [film.displayYear.map(String.init), (film.tmdb?.genreNames ?? []).prefix(2).joined(separator: ", ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Denis Villeneuve · with Timothée Chalamet, Zendaya"
    static func people(_ film: FilmEntry) -> String {
        let director = film.tmdb?.directors.first
        let leads = (film.tmdb?.topCast ?? []).prefix(2).map(\.name)
        let with = leads.isEmpty ? nil : (director == nil ? "" : "with ") + leads.joined(separator: ", ")
        return [director, with].compactMap { $0 }.joined(separator: " · ")
    }

    /// The two most notable lists, then how many more ("Palme d'Or · 2019 · +2").
    private func lists(_ film: FilmEntry) -> String? {
        let badges = model.badges(for: film)
        guard let first = badges.first else { return nil }
        return badges.count > 1 ? first.text + "  +\(badges.count - 1)" : first.text
    }

    private func text(_ value: String?, lines: Int, color: Color = Theme.secondaryText,
                      weight: Font.Weight = .regular) -> some View {
        Text(value ?? "")
            .font(.system(size: textSize, weight: weight))
            .foregroundStyle(color)
            .lineLimit(lines)
            .frame(height: line * CGFloat(lines), alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A one-line fact with its symbol; empty space when there's nothing to say.
    private func row(_ symbol: String, _ text: String?) -> some View {
        Group {
            if let text, !text.isEmpty {
                Label(text, systemImage: symbol)
                    .font(.system(size: textSize))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            } else {
                Color.clear
            }
        }
        .frame(height: line, alignment: .leading)
    }

    private func buttons(_ film: FilmEntry) -> some View {
        HStack(spacing: large ? 12 : 8) {
            if item.isOnline {
                button("Play", symbol: "play.fill", primary: true) { model.play(film) }
            } else {
                // Says why there's no Play, rather than leaving a gap.
                Label("Connect \(driveName) to play", systemImage: "externaldrive")
                    .font(.system(size: textSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if model.offersTrailer(for: film) {
                button(model.trailerLabel(for: film), symbol: "play.rectangle") {
                    model.showTrailer(for: film, offersFilmPage: true)
                }
            }
        }
        .frame(height: large ? 50 : 30, alignment: .leading)
    }

    private var driveName: String {
        model.drives.first { $0.id == item.main.driveID }?.name ?? "the drive"
    }

    @ViewBuilder
    private func button(_ title: String, symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) { Label(title, systemImage: symbol) }
        if large {
            button.buttonStyle(CinemaButtonStyle(primary: primary, compact: true))
        } else if primary {
            button.buttonStyle(PrimaryCapsuleStyle())
        } else {
            button.buttonStyle(SecondaryCapsuleStyle())
        }
    }
}

/// "Decide for Us": the pick counts only while it's still on the list.
enum TonightPick {
    static func current(_ chosen: String?, in items: [LibraryItem]) -> String? {
        items.contains { $0.id == chosen } ? chosen : nil
    }
}
#endif
