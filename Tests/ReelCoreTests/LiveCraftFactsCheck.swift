import XCTest
@testable import ReelCore

/// The facts sheet read live for 30 well-known films (public titles, not anyone's library), for
/// the hand check before Cinematography ships (spec §7.8). Runs only when REEL_CRAFT_CHECK names
/// a file to write; CI's craft-check job does that.
final class LiveCraftFactsCheck: XCTestCase {
    static let films: [(String, Int)] = [
        ("Oppenheimer", 2023), ("Dunkirk", 2017), ("Parasite", 2019), ("Roma", 2018), ("The Lighthouse", 2019),
        ("Mank", 2020), ("Belfast", 2021), ("Joker", 2019), ("1917", 2019), ("Blade Runner 2049", 2017),
        ("Dune", 2021), ("Mad Max: Fury Road", 2015), ("The Revenant", 2015), ("La La Land", 2016), ("Moonlight", 2016),
        ("Arrival", 2016), ("The Social Network", 2010), ("Zodiac", 2007), ("Collateral", 2004), ("Inception", 2010),
        ("Interstellar", 2014), ("The Grand Budapest Hotel", 2014), ("Lady Bird", 2017), ("Anora", 2024), ("The Brutalist", 2024),
        ("Past Lives", 2023), ("Poor Things", 2023), ("Killers of the Flower Moon", 2023), ("Nomadland", 2020), ("Tár", 2022),
    ]

    struct Row: Encodable {
        let row: String
        let value: String
        let inPart: Bool
        let source: String
        let sentence: String?
    }

    struct Film: Encodable {
        let title: String
        let year: Int
        let article: String?
        let shotOn: [String]
        let inPart: [String]
        let rows: [Row]
    }

    func testReadTheFactsSheetLive() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let output = env["REEL_CRAFT_CHECK"], !output.isEmpty, let token = env["TMDB_TOKEN"], !token.isEmpty else {
            throw XCTSkip("REEL_CRAFT_CHECK and TMDB_TOKEN not set")
        }
        let tmdb = TMDBClient(token: token)
        var films: [Film] = []
        for (title, year) in Self.films {
            guard let hit = try await tmdb.searchMovies(query: title, year: year).first else { continue }
            let details = try await tmdb.movieDetails(id: hit.id)
            guard let findings = try? await WikipediaClient().findings(imdbID: details.imdbID, title: details.title, year: details.year),
                  let craft = findings.craft else { continue }
            films.append(Film(title: details.title, year: year, article: findings.funFacts.articleTitle,
                              shotOn: craft.shotOn.map(\.rawValue), inPart: craft.inPart.map(\.rawValue).sorted(),
                              rows: craft.facts.map { Row(row: $0.row.rawValue, value: $0.value, inPart: $0.inPart, source: $0.source, sentence: $0.sentence) }))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(films).write(to: URL(fileURLWithPath: output))
        let withFormat = films.filter { !$0.shotOn.isEmpty }.count
        print("CRAFT| \(films.count) films read; film or digital or other format for \(withFormat); "
              + "\(films.map { $0.rows.count }.reduce(0, +)) values in all")
        XCTAssertGreaterThan(films.count, 25)
    }
}
