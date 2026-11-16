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

    /// A second 30, not looked at while the rules were set: the held-out check.
    static let heldOut: [(String, Int)] = [
        ("The Master", 2012), ("Phantom Thread", 2017), ("There Will Be Blood", 2007), ("No Country for Old Men", 2007),
        ("Children of Men", 2006), ("Gravity", 2013), ("Birdman", 2014), ("The Tree of Life", 2011), ("Drive", 2011),
        ("Her", 2013), ("Skyfall", 2012), ("Sicario", 2015), ("Prisoners", 2013), ("Gone Girl", 2014),
        ("The Favourite", 2018), ("Portrait of a Lady on Fire", 2019), ("Cold War", 2018), ("Ida", 2013), ("Nebraska", 2013),
        ("Little Women", 2019), ("The Irishman", 2019), ("Once Upon a Time in Hollywood", 2019), ("Uncut Gems", 2019),
        ("The Power of the Dog", 2021), ("Licorice Pizza", 2021), ("Everything Everywhere All at Once", 2022),
        ("The Zone of Interest", 2023), ("Aftersun", 2022), ("The Holdovers", 2023), ("Challengers", 2024),
    ]

    /// A third 30, for checking the rules after the held-out fixes.
    static let third: [(String, Int)] = [
        ("Lost in Translation", 2003), ("The Royal Tenenbaums", 2001), ("Amélie", 2001), ("City of God", 2002),
        ("Pan's Labyrinth", 2006), ("The Assassination of Jesse James by the Coward Robert Ford", 2007), ("Atonement", 2007),
        ("The Dark Knight", 2008), ("Black Swan", 2010), ("True Grit", 2010), ("Melancholia", 2011), ("Hugo", 2011),
        ("Life of Pi", 2012), ("12 Years a Slave", 2013), ("Inside Llewyn Davis", 2013), ("Whiplash", 2014),
        ("Carol", 2015), ("The Witch", 2015), ("Manchester by the Sea", 2016), ("Call Me by Your Name", 2017),
        ("The Shape of Water", 2017), ("If Beale Street Could Talk", 2018), ("The Father", 2020), ("Minari", 2020),
        ("Drive My Car", 2021), ("The Banshees of Inisherin", 2022), ("All Quiet on the Western Front", 2022),
        ("Anatomy of a Fall", 2023), ("Perfect Days", 2023), ("Conclave", 2024),
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
        let set = env["REEL_CRAFT_SET"] == "third" ? Self.third : env["REEL_CRAFT_SET"] == "held-out" ? Self.heldOut : Self.films
        for (title, year) in set {
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
