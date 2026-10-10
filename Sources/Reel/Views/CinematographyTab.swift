#if os(macOS)
import SwiftUI
import ReelCore

// MARK: - Cinematography

/// How the film was shot, curated like a good cinematography piece: who shot it and how they
/// came to, frames, the look in brief and its specification sheet, then What to Look For (the five
/// most telling notes: the visual idea, their own words, what it drew on, a scene, a challenge,
/// the frame, the light, the colour) with the rest by topic a click away. Every note opens to the
/// paragraph it comes from and what the gear it names is; every value on the specification sheet
/// opens to what it is and what it does to the picture (`CraftGlossary`). Then their other films
/// in the library, the crew and the interviews to read in full. From the film's Wikipedia article, the interviews and
/// craft articles it cites, American Cinematographer, the cinematographer's own article and
/// Wikidata's awards (see `CameraReading`, `TechSpecs`). What gives the story away stays out until
/// the film is watched.
struct CinematographyTab: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    let openStill: ([String], Int) -> Void
    /// Everything read once for what it's made from (not on each redraw).
    @State private var read = ReadSpecs()
    /// Everything else read, opened.
    @State private var showAll = false
    /// The notes opened to read more.
    @State private var opened: Set<String> = []

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
            let notes = read.notes
            if !notes.top.isEmpty { whatToLookFor(notes.top, bold: bold) }
            if !notes.rest.isEmpty { moreNotes(notes.rest, total: notes.restCount, bold: bold) }
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
                            SpecValue(value: value)
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

    /// The five most telling notes, numbered; each opens to the paragraph it's from and what
    /// the gear and techniques it names are.
    private func whatToLookFor(_ top: [CraftNotes.Item], bold: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Theme.sectionTitle("What to Look For")
                Text("The choices that shape how it looks, the most telling first. Open one to read more.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Theme.hairline) }
                    NoteRow(number: index + 1, topic: item.topic.title, note: item.note, names: bold,
                            quoted: item.topic == .words, open: opened.contains(item.id)) { toggle(item.id) }
                }
            }
            .padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
        }
    }

    /// The rest of what was read, by topic, closed until asked for; each note opens the same way.
    private func moreNotes(_ groups: [(topic: CraftNotes.Topic, notes: [TechSpecs.Note])], total: Int, bold: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showAll.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(showAll ? "Less on How It Was Shot" : "More on How It Was Shot")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(total)").font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(showAll ? 180 : 0))
                }
                .foregroundStyle(Color.white.opacity(0.9))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showAll {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups, id: \.topic) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.topic.title.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(.tertiary)
                                .padding(.bottom, 4)
                            ForEach(group.notes) { note in
                                NoteRow(number: nil, topic: nil, note: note, names: bold, quoted: group.topic == .words,
                                        open: opened.contains(note.id)) { toggle(note.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            if opened.contains(id) { opened.remove(id) } else { opened.insert(id) }
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
            // Whole words: "Red" (the cameras) not in "inspired".
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#
            var start = sentence.startIndex
            while let found = sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive], range: start..<sentence.endIndex) {
                if let range = Range(found, in: text) { text[range].inlinePresentationIntent = .stronglyEmphasized }
                start = found.upperBound
            }
        }
        return text
    }
}

/// One note: what it says, and, opened, the paragraph it comes from (the note in white within it)
/// and what the gear and techniques it names are.
private struct NoteRow: View {
    let number: Int?
    let topic: String?
    let note: TechSpecs.Note
    /// The gear found in what was read (in bold).
    let names: [String]
    let quoted: Bool
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        // What it names, each explained once (Cooke S4/i and Cooke Panchro share an explanation).
        var explained = Set<String>()
        let terms = note.names.compactMap { name -> Term? in
            guard let text = CraftGlossary.explain(name), explained.insert(text).inserted else { return nil }
            return Term(name: name, explanation: text)
        }
        let more = note.context != nil || !terms.isEmpty
        VStack(alignment: .leading, spacing: 12) {
            // Only a note with more to read is a button (a disabled one would look dimmed).
            if more {
                Button(action: toggle) { header(more: more) }
                    .buttonStyle(.plain)
                    .help(open ? "Show less" : "Read more")
            } else {
                header(more: more)
            }
            if open, more {
                VStack(alignment: .leading, spacing: 14) {
                    if let context = note.context {
                        Self.inContext(note.text, context)
                            .font(.system(size: 15, design: .serif))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Text("From \(note.source ?? "the film's Wikipedia article")")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(terms) { term in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(term.name).font(.system(size: 12.5, weight: .semibold))
                            Text(term.explanation)
                                .font(.system(size: 13))
                                .lineSpacing(3)
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, number == nil ? 0 : 38)
                .padding(.bottom, 4)
                .transition(.opacity)
            }
        }
        .padding(.vertical, number == nil ? 10 : 16)
    }

    private func header(more: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if let number {
                Text("\(number)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 22, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 7) {
                if let topic {
                    Text(topic.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.brand.opacity(0.85))
                }
                Text(CinematographyTab.emphasised(note.text, names: names))
                    .font(quoted ? .system(size: number == nil ? 15 : 17, design: .serif).italic()
                                 : .system(size: number == nil ? 14.5 : 16, weight: number == nil ? .regular : .medium))
                    .lineSpacing(4)
                    .foregroundStyle(Color.white.opacity(number == nil ? 0.86 : 0.94))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let source = note.source, !source.hasPrefix("Wikipedia") {
                    Text("— " + source).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if more {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(open ? Theme.brand : Color.secondary)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
        }
        .contentShape(Rectangle())
    }

    /// A name the note mentions, and what it is.
    struct Term: Identifiable {
        let name: String
        let explanation: String
        var id: String { name }
    }

    /// The paragraph, quiet, with the note itself in full white.
    static func inContext(_ note: String, _ paragraph: String) -> Text {
        // The note as it stands, or (two sentences read together, spaced differently) from its
        // first sentence to the end of its last.
        let sentences = note.components(separatedBy: ". ")
        let whole = paragraph.range(of: note)
        let from = paragraph.range(of: sentences.first ?? note)
        let to = sentences.last.flatMap { paragraph.range(of: $0) }
        guard let range = whole ?? from.map({ start in start.lowerBound..<max(start.upperBound, to?.upperBound ?? start.upperBound) }) else {
            return Text(paragraph).foregroundStyle(Theme.secondaryText)
        }
        return Text(paragraph[..<range.lowerBound]).foregroundStyle(Theme.secondaryText)
            + Text(paragraph[range]).foregroundStyle(Color.white.opacity(0.95))
            + Text(paragraph[range.upperBound...]).foregroundStyle(Theme.secondaryText)
    }
}

/// A value on the specification sheet: clicked, what it is and what it does to the picture
/// (when Reel knows; see `CraftGlossary`).
private struct SpecValue: View {
    let value: String
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        if let explanation = CraftGlossary.explain(value) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { open.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        name
                        Image(systemName: open ? "info.circle.fill" : "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(open || hovering ? Theme.brand : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help("What is it?")
                if open {
                    Text(explanation)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        } else {
            // Nothing to explain: plain text (a disabled button would look dimmed).
            name.textSelection(.enabled)
        }
    }

    private var name: some View {
        Text(value)
            .font(.system(size: 14.5, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }
}

/// What was read about the shooting, curated: the five most telling notes across the topics
/// (at most two of a topic, each worth reading on its own), then the rest by topic. A note is
/// worth as much as the gear and detail it names, its reason, its source (their own words count
/// most) and how much it surprises (see `FunFactExtractor.score`).
struct CraftNotes {
    enum Topic: Hashable {
        case idea, words, reference, scene, challenge, frame, light, colour, gear

        var title: String {
            switch self {
            case .idea: "The Visual Idea"
            case .words: "In Their Own Words"
            case .reference: "What It Drew On"
            case .scene: "A Scene"
            case .challenge: "A Challenge"
            case .frame: "Frame and Movement"
            case .light: "Light"
            case .colour: "Colour and Texture"
            case .gear: "The Gear"
            }
        }

        /// The kinds of note that say most about why it looks as it does.
        var bonus: Double {
            switch self {
            case .words, .idea, .reference: 2
            case .scene, .challenge: 1.5
            case .frame, .light, .colour: 0.5
            case .gear: 0
            }
        }
    }

    struct Item: Identifiable {
        let topic: Topic
        let note: TechSpecs.Note
        var id: String { note.id }
    }

    let top: [Item]
    let rest: [(topic: Topic, notes: [TechSpecs.Note])]
    var restCount: Int { rest.reduce(0) { $0 + $1.notes.count } }

    init(_ specs: TechSpecs) {
        let all: [(Topic, [TechSpecs.Note])] = [
            (.idea, specs.intent), (.words, specs.approach), (.reference, specs.references), (.scene, specs.scenes),
            (.challenge, specs.challenges), (.frame, specs.cameraLanguage), (.light, specs.lighting),
            (.colour, specs.colour), (.gear, specs.sentences),
        ]
        // Each note's worth worked out once.
        let items: [Item] = all.flatMap { entry in entry.1.map { Item(topic: entry.0, note: $0) } }
        let worths: [(Item, Double)] = items.filter { $0.note.text.count <= 420 }.map { item in
            let worth: Double = Double(item.note.weight) + item.topic.bonus + FunFactExtractor.score(item.note.text)
            return (item, worth)
        }
        let ranked = worths.sorted { $0.1 > $1.1 }
        var top: [Item] = []
        for (item, worth) in ranked where top.count < 5 && worth >= 2 {
            guard top.filter({ $0.topic == item.topic }).count < 2 else { continue }
            top.append(item)
        }
        self.top = top
        let shown = Set(top.map(\.id))
        rest = all.compactMap { topic, notes in
            let left = notes.filter { !shown.contains($0.id) }
            return left.isEmpty ? nil : (topic, left)
        }
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
    /// What's shown of it, curated (read with `specs`).
    private(set) var notes = CraftNotes(TechSpecs.read([]))

    func specs(article: FilmArticle?, reading: CameraReading?, hiding: Bool, cinematographers: [String],
               directors: [String]) -> TechSpecs {
        guard article != nil || reading != nil else {
            // Nothing read yet (another film opened): nothing from the last one shows.
            stamp = ""
            notes = CraftNotes(TechSpecs.read([]))
            return TechSpecs.read([])
        }
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
            notes = CraftNotes(specs)
        }
        return specs
    }

    /// While spoiler-safe: nothing that tells of the story, or of how it ends ("the closing
    /// sequence was lit…"), and no paragraph to read more that does.
    private static func withoutStory(_ read: TechSpecs) -> TechSpecs {
        func safe(_ text: String) -> Bool {
            !Spoilers.mentionsPlot(text) && text.range(of: ending, options: [.regularExpression, .caseInsensitive]) == nil
        }
        func keep(_ notes: [TechSpecs.Note]) -> [TechSpecs.Note] {
            notes.filter { safe($0.text) }.map { note in
                var kept = note
                if let context = kept.context, !safe(context) { kept.context = nil }
                return kept
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
