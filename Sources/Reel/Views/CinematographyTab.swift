#if os(macOS)
import SwiftUI
import ReelCore

// MARK: - Cinematography

/// How the film was shot (1.11, spec §7): who shot it, frames from the film, the facts sheet (each
/// value from a structured source or one plain sentence, with where it's from), the camera,
/// lighting and colour crew, and where to read more. Everything shown is stored with the film:
/// opening the tab fetches nothing but the film's facts and article, as Behind the Film does.
struct CinematographyTab: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    let openStill: ([String], Int) -> Void

    var body: some View {
        let id = film.tmdb?.id ?? 0
        let article = model.articles[id]
        let crew = CameraCrew.groups(film.tmdb)
        let lead = crew.first { $0.isLead }?.names ?? []
        let removed = model.removedFacts[id] ?? []
        let facts = (film.craftFacts?.facts ?? []).filter { !removed.contains($0.row.rawValue) }

        VStack(alignment: .leading, spacing: 34) {
            if !lead.isEmpty {
                shotBy(lead, honours: film.funFacts?.quick?.cinematographyHonours ?? [])
            }
            // The pictures first: what the words below are about. Hidden once checked and none
            // turned out to be frames from the film.
            if !(film.tmdb?.stillPaths.isEmpty ?? true), film.checkedStills.map({ model.visibleStills(film, checked: $0).isEmpty }) != true {
                VStack(alignment: .leading, spacing: 14) {
                    Theme.sectionTitle("Frames from the Film")
                    FilmStills(film: film, open: openStill)
                }
            }
            if !facts.isEmpty { factSheet(facts) }
            let others = model.filmsShot(by: lead, besides: film)
            if !others.isEmpty {
                PosterRow(title: lead.count == 1 ? "Also Shot by \(lead[0])" : "Also Shot by Them", items: others)
            }
            let team = crew.filter { !$0.isLead }
            if !team.isEmpty { crewGrid(team) }
            links(article: article)
        }
        .frame(maxWidth: 820, alignment: .leading)
        .task(id: id) {
            await model.loadFunFacts(for: film)
            await model.loadArticle(for: film)
        }
    }

    // MARK: Parts

    /// Who shot it (their page a click away), and the awards the cinematography won or was up for.
    private func shotBy(_ names: [String], honours: [Honour]) -> some View {
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

    /// The facts sheet: one row per value, with where it's from.
    private func factSheet(_ facts: [CraftFacts.Fact]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Theme.sectionTitle("The Facts")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                    if index > 0 { Divider().overlay(Theme.hairline) }
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text(Self.title(of: fact.row).uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.tertiary)
                            .frame(width: 150, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fact.value + (fact.inPart ? " (in part)" : "")).font(.system(size: 14, weight: .medium))
                            if let sentence = fact.sentence, !model.hidesSpoilers(for: film) || !Spoilers.tellsTheStory(sentence) {
                                Text("“\(sentence)”").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let link = fact.link {
                                TextLink(fact.source, destination: link).font(.system(size: 11.5))
                            } else {
                                Text(fact.source).font(.system(size: 11.5)).foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Not Right") { model.removeFact(fact.row, from: film) }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11.5))
                            .help("Hide this for good (kept in Your Notes)")
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
        }
    }

    static func title(of row: CraftFacts.Row) -> String {
        switch row {
        case .aspectRatio: "Aspect ratio"
        case .colour: "Colour"
        case .format: "Shot on"
        case .camera: "Camera"
        case .lenses: "Lenses"
        case .award: "Awards"
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
        ("Visual Effects", ["Visual Effects Supervisor"]),
    ]

    static func groups(_ details: TMDBMovieDetails?) -> [Group] {
        guard let details else { return [] }
        var listed = Set<String>()
        let groups: [Group] = jobs.compactMap { entry in
            let names = details.people(forJobs: entry.jobs).map(\.name).filter { !listed.contains($0) }
            listed.formUnion(names)
            return names.isEmpty ? nil : Group(title: entry.title, names: Array(names.prefix(4)))
        }
        return groups
    }
}
#endif
