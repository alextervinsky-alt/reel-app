#if os(macOS)
import SwiftUI
import ReelCore

// MARK: - Cinematography

/// How the film was shot, told the way a cinematography piece tells it (American Cinematographer's
/// order): who shot it and how they came to, the look in brief and its specification sheet, the
/// visual idea, the filmmakers' own words, what it drew on, the frame, the light and the colour,
/// particular scenes, what was hard or new, then the gear, their other films in the library, the
/// crew and the interviews to read in full. From the film's Wikipedia article, the interviews and
/// craft articles it cites, American Cinematographer, the cinematographer's own article and
/// Wikidata's awards (see `CameraReading`, `TechSpecs`). What gives the story away stays out until
/// the film is watched.
struct CinematographyTab: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    let openStill: ([String], Int) -> Void
    /// Everything read once for what it's made from (not on each redraw).
    @State private var read = ReadSpecs()
    /// Sections opened past their first three.
    @State private var expanded: Set<String> = []

    var body: some View {
        let id = film.tmdb?.id ?? 0
        let article = model.articles[id]
        let reading = model.cameraReadings[id]
        let crew = CameraCrew.groups(film.tmdb)
        let lead = crew.first { $0.isLead }?.names ?? []
        let hiding = model.hidesSpoilers(for: film)
        let specs = read.specs(article: article, reading: reading, hiding: hiding, cinematographers: lead,
                               directors: film.tmdb?.directors ?? [])
        let bold = specs.specs.filter { !$0.isFixedName }.map(\.name)
        let sheet = SpecSheet(specs: specs, quick: film.funFacts?.quick)
        let loading = model.cameraReadingsLoading.contains(id) || model.articlesLoading.contains(id)

        VStack(alignment: .leading, spacing: 34) {
            if !lead.isEmpty {
                shotBy(lead, about: reading?.cinematographer, with: specs.collaboration,
                       honours: film.funFacts?.quick?.cinematographyHonours ?? [])
            }
            // The pictures first: what the words below are about. Hidden once checked and none
            // turned out to be frames from the film.
            if !(film.tmdb?.stillPaths.isEmpty ?? true), film.checkedStills?.isEmpty != true {
                VStack(alignment: .leading, spacing: 14) {
                    Theme.sectionTitle("Frames from the Film")
                    FilmStills(film: film, open: openStill)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Theme.sectionTitle("The Look")
                    if let brief = specs.brief(by: lead, ratio: sheet.wikidataRatio, blackAndWhite: sheet.blackAndWhite) {
                        Text(brief)
                            .font(.system(size: 18, weight: .medium))
                            .lineSpacing(5)
                            .foregroundStyle(Color.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                if loading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Reading interviews and articles about how it was shot…").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13))
                }
                if sheet.rows.isEmpty {
                    if !loading { nothingFound(article: article, id: id) }
                } else {
                    specTable(sheet.rows)
                }
            }
            passage("The Visual Idea", note: "What the images were meant to do, and the choices made for it.",
                    notes: specs.intent, bold: bold)
            passage("In Their Own Words", note: "The filmmakers on how they shot it.",
                    notes: specs.approach, bold: bold, quoted: true)
            passage("References and Influences", note: "What the look drew on.", notes: specs.references, bold: bold)
            passage("Frame and Movement", note: "Composition, lenses and how the camera moves.",
                    notes: specs.cameraLanguage, bold: bold)
            passage("Light", note: "Sources, shadows and contrast.", notes: specs.lighting, bold: bold)
            passage("Colour and Texture", note: "Palette, grade, stock and grain.", notes: specs.colour, bold: bold)
            passage("Scene by Scene", note: "How particular scenes and shots were done.", notes: specs.scenes, bold: bold)
            passage("Challenges and Innovations", note: "What was hard, tested, built or done for the first time.",
                    notes: specs.challenges, bold: bold)
            passage(specs.saysNothing ? "In the Article" : "More on the Gear", note: nil, notes: specs.sentences, bold: bold)
            let others = model.filmsShot(by: lead, besides: film)
            if !others.isEmpty {
                PosterRow(title: lead.count == 1 ? "Also Shot by \(lead[0])" : "Also Shot by Them", items: others)
            }
            let team = crew.filter { !$0.isLead }
            if !team.isEmpty { crewGrid(team) }
            reads(reading)
            links(article: article)
        }
        .frame(maxWidth: 820, alignment: .leading)
        // The facts first (they say which article it is), then the article: shared with Behind
        // the Film. The interviews and the cinematographer's article alongside.
        .task(id: id) {
            await model.loadFunFacts(for: film)
            async let article: Void = model.loadArticle(for: film)
            async let more: Void = model.loadCameraReading(for: film)
            _ = await (article, more)
        }
    }

    // MARK: Parts

    /// Who shot it (their page a click away), who they are, how they came to work with the
    /// director, and the awards the cinematography won or was up for.
    private func shotBy(_ names: [String], about: CameraReading.Cinematographer?, with director: [TechSpecs.Note],
                        honours: [Honour]) -> some View {
        let person = film.tmdb?.people(forJobs: ["Director of Photography"]).first
        return VStack(alignment: .leading, spacing: 8) {
            Label("Cinematography", systemImage: "camera")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.brand)
            if names.count == 1, let person, let personID = person.id {
                NavigationLink(value: PersonRoute(id: personID, name: person.name)) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(person.name).font(.system(size: 26, weight: .bold))
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help("All films shot by \(person.name)")
            } else {
                Text(names.joined(separator: " and "))
                    .font(.system(size: 26, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(names.count == 1 ? "Director of photography" : "Directors of photography")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if let about {
                Text(about.lead)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                TextLink("More about \(about.name) on Wikipedia", destination: about.url)
                    .font(.system(size: 12.5, weight: .medium))
            }
            if !director.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WITH THE DIRECTOR")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                    ForEach(director.prefix(2)) { note in
                        Text(note.text)
                            .font(.system(size: 13.5))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 10)
            }
            if !honours.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(honours.prefix(8)) { honour in
                        Label(honour.name, systemImage: honour.won ? "trophy.fill" : "rosette")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .foregroundStyle(honour.won ? Theme.brand : Theme.secondaryText)
                            .background(Capsule().fill(honour.won ? Theme.brand.opacity(0.14) : Color.white.opacity(0.07)))
                            .help(honour.won ? "Won" : "Nominated")
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Theme.brand.opacity(0.18), Theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    /// The specification sheet: one row per kind, its names stacked.
    private func specTable(_ rows: [SpecSheet.Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.title) { index, row in
                if index > 0 { Divider().overlay(Theme.hairline) }
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Label(row.title.uppercased(), systemImage: row.icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                        .frame(width: 190, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(row.values, id: \.self) { value in
                            Text(value)
                                .font(.system(size: 14.5, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
    }

    @ViewBuilder
    private func nothingFound(article: FilmArticle?, id: Int) -> some View {
        Group {
            if article == nil, film.funFacts == nil {
                Text("This needs an internet connection the first time.").foregroundStyle(.secondary)
            } else {
                Text("Nothing read about this film names its cameras or lenses. IMDb's technical specifications, below, usually list them.")
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 13.5))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
    }

    /// Notes under a heading, the gear in bold, each with where it was read; the filmmakers' own
    /// words with a bar beside them. Nothing when there are none.
    @ViewBuilder
    private func passage(_ title: String, note: String?, notes: [TechSpecs.Note], bold: [String], quoted: Bool = false) -> some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Theme.sectionTitle(title)
                    if let note { Text(note).font(.system(size: 13)).foregroundStyle(.secondary) }
                }
                let open = expanded.contains(title)
                let shown = open ? notes : Array(notes.prefix(3))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider().overlay(Theme.hairline) }
                        HStack(alignment: .top, spacing: 12) {
                            if quoted {
                                Image(systemName: "quote.opening")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.brand)
                                    .padding(.top, 3)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                // Their own words read as quotes (as in Behind the Film).
                                Text(Self.emphasised(item.text, names: bold))
                                    .font(quoted ? .system(size: 16, design: .serif).italic() : .system(size: 14))
                                    .lineSpacing(quoted ? 5 : 3)
                                    .foregroundStyle(quoted ? Color.white.opacity(0.92) : Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                Text((item.source ?? "Wikipedia").uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 14)
                    }
                    if notes.count > 3 {
                        Divider().overlay(Theme.hairline)
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if open { expanded.remove(title) } else { expanded.insert(title) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(open ? "Show Less" : "Show All \(notes.count)")
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                                    .rotationEffect(.degrees(open ? 180 : 0))
                            }
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.brand)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
            }
        }
    }

    private func crewGrid(_ groups: [CameraCrew.Group]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Theme.sectionTitle("Camera, Lighting and Colour Crew")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.tertiary)
                        Text(group.names.joined(separator: ", "))
                            .font(.system(size: 13.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
                }
            }
        }
    }

    /// The interviews and articles found, to read in full.
    @ViewBuilder
    private func reads(_ reading: CameraReading?) -> some View {
        let all = (reading?.sources ?? []) + (reading?.more ?? [])
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Theme.sectionTitle("Read the Interviews")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(all.prefix(8).enumerated()), id: \.element.id) { index, source in
                        if index > 0 { Divider().overlay(Theme.hairline) }
                        Link(destination: source.url) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.92))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(source.site)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 10)
                                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }
        }
    }

    private func links(article: FilmArticle?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find More").font(.system(size: 15, weight: .semibold))
            FlowLayout(spacing: 8) {
                ForEach(model.cameraLinks(for: film), id: \.title) { link in
                    Link(destination: link.url) {
                        HStack(spacing: 5) {
                            Text(link.title).lineLimit(1)
                            Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(Color.white.opacity(0.88))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                Text("From Wikipedia and Wikidata (CC BY-SA), TMDB and the articles named, quoted briefly.")
                if let url = article?.url { TextLink("Open the full article", destination: url) }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: Helpers

    /// The sentence with every name of gear found in it in bold.
    static func emphasised(_ sentence: String, names: [String]) -> AttributedString {
        var text = AttributedString(sentence)
        for name in names {
            var start = text.startIndex
            while let range = text[start...].range(of: name, options: .caseInsensitive) {
                text[range].inlinePresentationIntent = .stronglyEmphasized
                start = range.upperBound
            }
        }
        return text
    }
}

/// The technical specifications as rows, in the order a camera report lists them; Wikidata's
/// aspect ratio and colour when the texts don't say them (the texts' ratio wins: two different
/// ones would only confuse).
struct SpecSheet {
    struct Row {
        let title: String
        let icon: String
        let values: [String]
    }

    let rows: [Row]
    /// Wikidata's ratio, used only when nothing read gives one.
    let wikidataRatio: String?
    let blackAndWhite: Bool

    init(specs: TechSpecs, quick: QuickFacts?) {
        let formats = specs.names(.format)
        let ratios = formats.filter { $0.contains(":1") }
        let speeds = formats.filter { $0.contains("fps") || $0.contains("frames") }
        let media = formats.filter { !ratios.contains($0) && !speeds.contains($0) && $0 != "Black and white" }
        let colourLabels = (quick?.colour ?? []).map { $0.lowercased() }
        blackAndWhite = formats.contains("Black and white") || colourLabels.contains { $0.contains("black") }
        wikidataRatio = ratios.isEmpty ? quick?.aspectRatios?.first : nil
        var colour: [String] = []
        if blackAndWhite { colour.append("Black and white") }
        if colourLabels.contains(where: { $0 == "color" || $0 == "colour" }) { colour.append("Colour") }
        rows = [
            Row(title: "Camera", icon: "video", values: specs.names(.camera)),
            Row(title: "Lenses", icon: "camera.aperture", values: specs.names(.lens)),
            Row(title: "Film and Format", icon: "film", values: media),
            Row(title: "Aspect Ratio", icon: "rectangle.ratio.16.to.9", values: ratios.isEmpty ? (quick?.aspectRatios ?? []) : ratios),
            Row(title: "Frame Rate", icon: "speedometer", values: speeds),
            Row(title: "Colour", icon: "paintpalette", values: colour),
            Row(title: "Lighting", icon: "lightbulb", values: specs.names(.light)),
            Row(title: "Grip and Movement", icon: "move.3d", values: specs.names(.support)),
            Row(title: "Filters", icon: "camera.filters", values: specs.names(.filter)),
            Row(title: "Lab and Finish", icon: "slider.horizontal.3", values: specs.names(.finish)),
        ].filter { !$0.values.isEmpty }
    }
}

/// What was read, read again only when the article, the interviews or what may be shown changes.
@MainActor
private final class ReadSpecs {
    private var stamp = ""
    private var specs = TechSpecs.read([])

    func specs(article: FilmArticle?, reading: CameraReading?, hiding: Bool, cinematographers: [String],
               directors: [String]) -> TechSpecs {
        guard article != nil || reading != nil else { return TechSpecs.read([]) }
        let now = "\(article?.title ?? "")|\(article?.before.count ?? 0)|\(article?.after.count ?? 0)|"
            + "\(reading?.sources.count ?? -1)|\(hiding)|\(cinematographers)|\(directors)"
        if now != stamp {
            stamp = now
            var texts = reading?.texts(hiding: hiding) ?? []
            if let article {
                // The interviews first: the filmmakers' own words lead.
                let sections = article.before + (hiding ? [] : article.after)
                texts.insert(TechSpecs.Text(source: nil, sections: sections, isInterview: false), at: min(texts.count, reading?.sources.count ?? 0))
            }
            specs = TechSpecs.read(texts: texts, cinematographers: cinematographers, directors: directors)
            if hiding { specs = Self.withoutStory(specs) }
        }
        return specs
    }

    /// While spoiler-safe: nothing that tells of the story, or of how it ends ("the closing
    /// sequence was lit…").
    private static func withoutStory(_ read: TechSpecs) -> TechSpecs {
        func keep(_ notes: [TechSpecs.Note]) -> [TechSpecs.Note] {
            notes.filter { note in
                !Spoilers.mentionsPlot(note.text) && note.text.range(of: ending, options: [.regularExpression, .caseInsensitive]) == nil
            }
        }
        var specs = read
        specs.sentences = keep(specs.sentences)
        specs.approach = keep(specs.approach)
        specs.intent = keep(specs.intent)
        specs.references = keep(specs.references)
        specs.lighting = keep(specs.lighting)
        specs.cameraLanguage = keep(specs.cameraLanguage)
        specs.colour = keep(specs.colour)
        specs.scenes = keep(specs.scenes)
        specs.challenges = keep(specs.challenges)
        specs.collaboration = keep(specs.collaboration)
        return specs
    }

    private static let ending = #"\b(?:final|closing|last|ending)\s+(?:\w+\s+)?(?:scenes?|shots?|sequences?|images?|moments?|frames?)\b"#
}

/// The film's camera, lighting and colour people from TMDB, grouped by what they did.
enum CameraCrew {
    struct Group: Identifiable {
        let title: String
        let names: [String]
        /// The director(s) of photography.
        var isLead: Bool { title == "Cinematography" }
        var id: String { title }
    }

    /// In order: Cinematography first, then the rest of the camera team, lighting and colour.
    static let jobs: [(title: String, jobs: Set<String>)] = [
        ("Cinematography", ["Director of Photography"]),
        ("Additional Photography", ["Additional Director of Photography", "Second Unit Director of Photography",
                                    "Aerial Director of Photography", "Underwater Director of Photography",
                                    "Additional Photography"]),
        ("Camera Operators", ["Camera Operator", "\"A\" Camera Operator", "\"B\" Camera Operator", "Additional Camera Operator"]),
        ("Steadicam", ["Steadicam Operator"]),
        ("Focus Pullers", ["First Assistant Camera", "\"A\" First Assistant Camera", "First Assistant \"A\" Camera",
                           "\"B\" First Assistant Camera", "First Assistant \"B\" Camera"]),
        ("Digital Imaging", ["Digital Imaging Technician"]),
        ("Gaffer", ["Gaffer", "Chief Lighting Technician"]),
        ("Key Grip", ["Key Grip"]),
        ("Colourist", ["Colorist", "Digital Intermediate Colorist", "Supervising Colorist", "Senior Colorist"]),
    ]

    static func groups(_ details: TMDBMovieDetails?) -> [Group] {
        guard let details else { return [] }
        var listed = Set<String>()
        return jobs.compactMap { entry in
            let names = details.people(forJobs: entry.jobs).map(\.name).filter { !listed.contains($0) }
            listed.formUnion(names)
            return names.isEmpty ? nil : Group(title: entry.title, names: Array(names.prefix(4)))
        }
    }
}
#endif
