#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

struct OverviewTab: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    let onPreview: (PreviewFilm) -> Void
    /// The story and the fact sheet side by side (the usual window) or stacked (a narrow one).
    @State private var sideBySide = true

    var body: some View {
        let details = film.tmdb
        let collection = model.collectionItems(for: film)
        let related = model.relatedFilms(to: film, excluding: Set(collection.map { $0.id }), limit: 10)
        let people = related.people
        let similar = related.similar
        let moods = model.itemMoods(forKey: film.personalKey)

        VStack(alignment: .leading, spacing: 36) {
            // Side by side when there's room, from the width (laid out once, not tried twice).
            Group {
                if sideBySide {
                    HStack(alignment: .top, spacing: 48) {
                        story(details, moods: moods).frame(width: 540, alignment: .leading)
                        FilmFactSheet(film: film).frame(width: 340, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        story(details, moods: moods)
                        FilmFactSheet(film: film).frame(maxWidth: 560, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: Bool.self) { $0.size.width >= 540 + 48 + 340 } action: { sideBySide = $0 }
            // What people say, right under the story (1.11.4, Alex: Reviews and Overview are one tab).
            if details != nil {
                VStack(alignment: .leading, spacing: 14) {
                    Theme.sectionTitle("Reviews")
                    ReceptionTab(film: film)
                }
            }
            if let details, !details.topCast.isEmpty { cast(details) }
            if let pair = model.pairing(for: film) {
                PairItWith(film: film, partner: pair.item, reason: pair.reason)
            }
            if !people.isEmpty {
                PosterRow(title: "From the Same People", items: people.map { $0.item }, captions: related.captions)
            }
            if let series = details?.collection {
                let route = FranchiseRoute(id: series.id, name: series.name)
                if collection.isEmpty {
                    NavigationLink(value: route) {
                        Label("Part of the \(series.name). See which films you have.", systemImage: "square.stack")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.brand)
                    }
                    .buttonStyle(.plain)
                } else {
                    PosterRow(title: "More in \(series.name)", items: collection, seeAll: route)
                }
            }
            if !similar.isEmpty {
                // The row shows the closest ten; See All lists every close match.
                PosterRow(title: "More Like This in Your Library", items: similar,
                          seeSimilar: similar.count >= 10 ? SimilarRoute(filmID: film.id) : nil)
            }
            if let id = details?.id, let recommended = model.similar[id], !recommended.isEmpty {
                SimilarRow(films: recommended, onPreview: onPreview)
            }
            NotesEditor(film: film)
        }
        .task(id: details?.id) { await model.loadSimilar(for: film) }
    }

    @ViewBuilder
    private func story(_ details: TMDBMovieDetails?, moods: [Mood]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let tagline = details?.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            if let overview = details?.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !moods.isEmpty {
                HStack(spacing: 8) {
                    ForEach(moods) { Chip(text: $0.title, symbol: $0.symbol) }
                }
                .padding(.top, 4)
            }
        }
    }

    private func cast(_ details: TMDBMovieDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Theme.sectionTitle("Cast")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(Array(details.topCast.enumerated()), id: \.offset) { _, person in
                        if let id = person.id {
                            NavigationLink(value: PersonRoute(id: id, name: person.name)) {
                                castCard(person)
                            }
                            .buttonStyle(.plain)
                            .help("See all films with \(person.name)")
                        } else {
                            castCard(person)
                        }
                    }
                }
                .hoverRegion()
            }
            .tracksScrolling()
        }
    }

    private func castCard(_ person: TMDBCastMember) -> some View {
        VStack(spacing: 7) {
            Color(white: 0.14)
                .frame(width: 76, height: 76)
                .overlay {
                    CachedImage(path: person.profilePath, kind: .profile) {
                        Image(systemName: "person.fill").font(.title2).foregroundStyle(.tertiary)
                    }
                }
                .clipShape(Circle())
            Text(person.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text(person.character ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 96)
        .contentShape(Rectangle())
    }
}

/// Everything about the film in one place: who made it, how it was shot, the file, where your
/// copies are, and your own notes on it.
struct FilmFactSheet: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry

    var body: some View {
        let d = film.tmdb
        let copies = model.copies(of: film)
        let record = model.record(for: film)
        VStack(alignment: .leading, spacing: 0) {
            people("Director", d?.people(forJobs: ["Director"]) ?? [])
            people("Writers", Array((d?.people(forJobs: TMDBMovieDetails.writerJobs) ?? []).prefix(3)))
            people("Camera", d?.people(forJobs: ["Director of Photography"]) ?? [])
            people("Music", Array((d?.people(forJobs: TMDBMovieDetails.composerJobs) ?? []).prefix(2)))
            people("Editor", Array((d?.people(forJobs: ["Editor"]) ?? []).prefix(2)))
            people("Design", Array((d?.people(forJobs: ["Production Design"]) ?? []).prefix(2)))
            if let ratio = film.funFacts?.quick?.aspectRatios?.first { row("Aspect ratio", Text(ratio)) }
            if let language = FilmLanguage.code(d?.originalLanguage) { row("Language", Text(FilmLanguage.name(language))) }
            if let file = fileLine(copies) { row("File", Text(file)) }
            if let subtitles = subtitlesLine { row("Subtitles", Text(subtitles)) }
            row("Copies", Text(copiesLine(copies)))
            row("You", Text(youLine(record)), last: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private func people(_ label: String, _ crew: [TMDBCrewMember]) -> some View {
        if !crew.isEmpty {
            row(label, VStack(alignment: .leading, spacing: 3) {
                ForEach(crew, id: \.name) { person in PersonLink(name: person.name, id: person.id) }
            })
        }
    }

    private func row(_ label: String, _ value: some View, last: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
                .frame(width: 74, alignment: .leading)
            value
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
        }
    }

    /// "4K · Dolby Vision + HDR10 · 58 GB · MKV": the picture's format as Reel reads it (see
    /// `FilePicture`), or the name's own words.
    private func fileLine(_ copies: [FilmEntry]) -> String? {
        guard let copy = copies.first else { return nil }
        var parts: [String] = []
        if let resolution = copy.parsed.resolution { parts.append(resolution == "2160p" ? "4K" : resolution) }
        let picture = model.picture(of: copy)
        // The name's own HDR words only while it's HDR (you may have set a misnamed file to SDR).
        if picture.isHDR, !picture.isGuess, let format = picture.format?.rawValue ?? copy.parsed.hdr { parts.append(format) }
        parts += copy.parsed.editions
        if copy.size > 0 { parts.append(Format.bytes(copy.size)) }
        let ext = (copy.fileName as NSString).pathExtension.uppercased()
        if !ext.isEmpty { parts.append(ext) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Estonian and English"
    private var subtitlesLine: String? {
        let subtitles = film.subtitleLanguages
        if !subtitles.isEmpty { return ListFormatter.localizedString(byJoining: subtitles) }
        return film.hasSubtitles ? "Yes" : nil
    }

    /// "filmikogu · Backup complete"
    private func copiesLine(_ copies: [FilmEntry]) -> String {
        let main = copies.filter { !(model.drive($0.driveID)?.isBackup ?? false) }.compactMap { model.drive($0.driveID)?.name }
        var parts = Array(Set(main)).sorted()
        if model.drives.contains(where: { $0.isBackup }) {
            let onBackup = copies.contains { model.drive($0.driveID)?.isBackup ?? false }
            if !onBackup {
                parts.append("not on Backup")
            } else if case .incomplete = model.backupGaps[film.personalKey] {
                parts.append("Backup copy incomplete")
            } else {
                parts.append("on Backup")
            }
        }
        return parts.isEmpty ? "No copy found" : parts.joined(separator: " · ")
    }

    /// "Watched · 4★", "On your watchlist", "Unwatched"
    private func youLine(_ record: PersonalRecord) -> String {
        var parts: [String] = [record.watched ? "Watched" : "Unwatched"]
        if let stars = record.rating { parts.append(String(repeating: "★", count: min(max(stars, 1), 5))) }
        if record.watchlist && !record.watched { parts.append("on your watchlist") }
        if record.favorite { parts.append("a favourite") }
        if model.isTonight(film.personalKey) { parts.append("on Tonight") }
        return parts.joined(separator: " · ")
    }
}

/// "Pair it with": one film from your library for a double feature with this one, and why.
struct PairItWith: View {
    let film: FilmEntry
    let partner: LibraryItem
    let reason: String
    @State private var hovering = false

    var body: some View {
        NavigationLink(value: FilmRoute(id: partner.main.id)) {
            HStack(spacing: 0) {
                FocusedBackdrop(path: partner.main.tmdb?.backdropPath)
                    .frame(width: 300, height: 150)
                    .clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text("PAIR IT WITH")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.brand)
                    Text(partner.main.displayTitle)
                        .font(.system(size: 19, weight: .bold))
                        .lineLimit(1)
                    Text(reason)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(2)
                    if let together = together {
                        Text(together)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 22)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 20)
            }
            .frame(maxWidth: 820, alignment: .leading)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(hovering ? Theme.brand.opacity(0.5) : Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scrollAwareHover($hovering)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("A double feature from your library")
    }

    /// "A double feature of 4 h 12 min"
    private var together: String? {
        guard let a = film.tmdb?.runtime, let b = partner.runtime, a > 0, b > 0 else { return nil }
        return "A double feature of " + Format.runtime(a + b)
    }
}

/// A name that opens the person's page (underlined on hover).
struct PersonLink: View {
    let name: String
    let id: Int?
    @State private var hovering = false

    var body: some View {
        if let id {
            NavigationLink(value: PersonRoute(id: id, name: name)) {
                Text(name)
                    .font(.system(size: 13.5))
                    .underline(hovering, color: Theme.brand)
                    .foregroundStyle(hovering ? Theme.brand : Color.primary)
            }
            .buttonStyle(.plain)
            .scrollAwareHover($hovering)
            .help("See all films by \(name)")
        } else {
            Text(name).font(.system(size: 13.5))
        }
    }
}

struct NotesEditor: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry

    var body: some View {
        let record = model.record(for: film)
        VStack(alignment: .leading, spacing: 10) {
            Theme.sectionTitle("Your Notes")
            TextEditor(text: Binding(
                get: { model.record(for: film).note },
                set: { model.setNote($0, for: film) }
            ))
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 70, maxHeight: 180)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
            .overlay(alignment: .topLeading) {
                if record.note.isEmpty {
                    Text("Thoughts, who recommended it, who to watch it with…")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            if let watchedOn = record.watchedOn, record.watched {
                Text(record.viewings.count > 1
                     ? "Watched \(record.viewings.count) times, last on \(watchedOn.formatted(date: .long, time: .omitted))"
                     : "Watched \(watchedOn.formatted(date: .long, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }
}
#endif
