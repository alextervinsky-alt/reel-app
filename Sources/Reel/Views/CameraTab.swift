#if os(macOS)
import SwiftUI
import ReelCore

// MARK: - Camera

/// How the film was shot, for the cinematographer in you: who shot it, the cameras, lenses,
/// lights, film stock and format (from its Wikipedia article and Wikidata), then the approach in
/// the article's own words — what the cinematographer said and chose, the lighting, the camera
/// language — the camera, lighting and colour crew, and where to read interviews and the full
/// technical specifications. What gives the story away stays out until the film is watched.
struct CameraTab: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    /// The article read once for what it's made from (not on each redraw).
    @State private var read = ReadSpecs()

    var body: some View {
        let id = film.tmdb?.id ?? 0
        let article = model.articles[id]
        let crew = CameraCrew.groups(film.tmdb)
        let specs = read.specs(article: article, hiding: model.hidesSpoilers(for: film),
                               cinematographers: crew.first { $0.isLead }?.names ?? [])
        let bold = specs.specs.filter { !$0.isFixedName }.map(\.name)
        let quick = film.funFacts?.quick
        let formats = specs.names(.format) + Self.wikidataFormats(quick, besides: specs.names(.format))

        VStack(alignment: .leading, spacing: 34) {
            if let lead = crew.first, lead.isLead { shotBy(lead) }
            VStack(alignment: .leading, spacing: 14) {
                Theme.sectionTitle("Shot On")
                if specs.isEmpty && formats.isEmpty {
                    nothingFound(article: article, id: id)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                        tile("Cameras", icon: "video", names: specs.names(.camera))
                        tile("Lenses", icon: "camera.aperture", names: specs.names(.lens))
                        tile("Lighting", icon: "lightbulb", names: specs.names(.light))
                        tile("Film and Format", icon: "film", names: formats)
                    }
                }
            }
            passage("The Cinematographer's Approach", note: "What they said and chose, as the article tells it.",
                    sentences: specs.approach, bold: bold, quoted: true)
            passage("Lighting", note: nil, sentences: specs.lighting, bold: bold)
            passage("Camera Language", note: nil, sentences: specs.cameraLanguage, bold: bold)
            passage(specs.approach.isEmpty && specs.lighting.isEmpty && specs.cameraLanguage.isEmpty ? "In the Article" : "More in the Article",
                    note: nil, sentences: specs.sentences, bold: bold)
            let others = crew.filter { !$0.isLead }
            if !others.isEmpty { crewGrid(others) }
            links(article: article)
        }
        .frame(maxWidth: 820, alignment: .leading)
        // The facts first (they say which article it is), then the article: shared with Behind the Film.
        .task(id: id) {
            await model.loadFunFacts(for: film)
            await model.loadArticle(for: film)
        }
    }

    // MARK: Parts

    private func shotBy(_ lead: CameraCrew.Group) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cinematography", systemImage: "camera")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.brand)
            Text(lead.names.joined(separator: " and "))
                .font(.system(size: 26, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(lead.names.count == 1 ? "Director of photography" : "Directors of photography")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Theme.brand.opacity(0.18), Theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    @ViewBuilder
    private func tile(_ title: String, icon: String, names: [String]) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(title.uppercased(), systemImage: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(names, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 15, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
        }
    }

    @ViewBuilder
    private func nothingFound(article: FilmArticle?, id: Int) -> some View {
        Group {
            if article == nil, model.articlesLoading.contains(id) || model.funFactsLoading.contains(id) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Reading how the film was shot…").foregroundStyle(.secondary)
                }
            } else if article == nil, film.funFacts == nil {
                Text("This needs an internet connection the first time.").foregroundStyle(.secondary)
            } else {
                Text(article == nil
                     ? "Wikipedia has no article about this film yet. IMDb's technical specifications, below, usually list the cameras and lenses."
                     : "Its Wikipedia article doesn't name the gear. IMDb's technical specifications, below, usually do.")
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 13.5))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
    }

    /// Sentences from the article under a heading, the gear in bold; the cinematographer's own
    /// words with a bar beside them. Nothing when there are none.
    @ViewBuilder
    private func passage(_ title: String, note: String?, sentences: [String], bold: [String], quoted: Bool = false) -> some View {
        if !sentences.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Theme.sectionTitle(title)
                    if let note { Text(note).font(.system(size: 13)).foregroundStyle(.secondary) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sentences.enumerated()), id: \.offset) { index, sentence in
                        if index > 0 { Divider().overlay(Theme.hairline) }
                        HStack(alignment: .top, spacing: 14) {
                            if quoted {
                                Capsule().fill(Theme.brand.opacity(0.7)).frame(width: 3)
                            }
                            Text(Self.emphasised(sentence, names: bold))
                                .font(.system(size: quoted ? 15 : 14))
                                .lineSpacing(3)
                                .foregroundStyle(quoted ? Color.white.opacity(0.9) : Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 18)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
            }
        }
    }

    private func crewGrid(_ groups: [CameraCrew.Group]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Theme.sectionTitle("Camera, Lighting and Colour")
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

    private func links(article: FilmArticle?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Interviews and Specifications").font(.system(size: 15, weight: .semibold))
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
                Text("From Wikipedia and Wikidata (CC BY-SA) and TMDB.")
                if let url = article?.url { Link("Open the full article", destination: url) }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: Helpers

    /// Wikidata's aspect ratio and colour, when the article doesn't already say them (the
    /// article's ratio wins: two different ones would only confuse).
    static func wikidataFormats(_ quick: QuickFacts?, besides found: [String]) -> [String] {
        let known = Set(found.map { $0.lowercased() })
        let articleHasRatio = found.contains { $0.contains(":1") }
        let ratios = articleHasRatio ? [] : quick?.aspectRatios ?? []
        let colour = (quick?.colour ?? []).compactMap { label -> String? in
            switch label.lowercased() {
            case "color", "colour": "Colour"
            case "black-and-white", "black and white": known.contains("black and white") ? nil : "Black and white"
            default: nil
            }
        }
        return ratios + colour
    }

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

/// The article's specs, read again only when the article or what may be shown changes.
@MainActor
private final class ReadSpecs {
    private var stamp = ""
    private var specs = TechSpecs.read([])

    func specs(article: FilmArticle?, hiding: Bool, cinematographers: [String]) -> TechSpecs {
        guard let article else { return TechSpecs.read([]) }
        let now = "\(article.title)|\(article.before.count)|\(article.after.count)|\(hiding)|\(cinematographers)"
        if now != stamp {
            stamp = now
            let sections = article.before + (hiding ? [] : article.after)
            specs = TechSpecs.read(sections: sections, cinematographers: cinematographers)
        }
        return specs
    }
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
