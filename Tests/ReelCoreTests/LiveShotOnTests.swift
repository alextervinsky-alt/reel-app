import XCTest
@testable import ReelCore

/// Live, run with the TMDB check (not offline): Shot on for well-known films whose answers are on
/// record, read from the real sources the way the app reads them. A tag a film shouldn't have is
/// reported with its sentence; a tag it should have and lacks is reported too. It never fails a
/// build (the sites change and refuse): the reports are what's checked.
final class LiveShotOnTests: XCTestCase {
    private struct Known {
        let title: String
        let year: Int
        /// Tags it must have, and tags it must not.
        let has: Set<ShotOn>
        let hasNot: Set<ShotOn>
    }

    private let films: [Known] = [
        Known(title: "Oppenheimer", year: 2023, has: [.film, .imax], hasNot: [.digital, .anamorphic]),
        Known(title: "Interstellar", year: 2014, has: [.film, .imax, .anamorphic], hasNot: [.digital]),
        Known(title: "The Prestige", year: 2006, has: [.film], hasNot: [.digital, .imax]),
        Known(title: "The Dark Knight", year: 2008, has: [.film, .imax], hasNot: [.digital]),
        Known(title: "Inception", year: 2010, has: [.film, .anamorphic], hasNot: []),
        Known(title: "The Matrix", year: 1999, has: [.film], hasNot: [.digital, .anamorphic]),
        Known(title: "No Country for Old Men", year: 2007, has: [.film], hasNot: [.digital]),
        Known(title: "La La Land", year: 2016, has: [.film, .anamorphic], hasNot: [.digital]),
        Known(title: "The Lighthouse", year: 2019, has: [.film, .blackAndWhite], hasNot: [.digital]),
        Known(title: "Lawrence of Arabia", year: 1962, has: [.film], hasNot: [.digital]),
        Known(title: "Jaws", year: 1975, has: [.film], hasNot: [.digital]),
        Known(title: "Saltburn", year: 2023, has: [.film], hasNot: [.digital, .anamorphic]),
        Known(title: "Roma", year: 2018, has: [.digital, .blackAndWhite], hasNot: [.film]),
        Known(title: "Ex Machina", year: 2015, has: [.digital], hasNot: [.film]),
        Known(title: "Blade Runner 2049", year: 2017, has: [.digital], hasNot: [.film]),
        Known(title: "Arrival", year: 2016, has: [.digital], hasNot: [.film]),
        Known(title: "Dune", year: 2021, has: [.digital, .imax], hasNot: [.film]),
        Known(title: "Mad Max: Fury Road", year: 2015, has: [.digital], hasNot: [.film]),
        Known(title: "Prisoners", year: 2013, has: [.digital], hasNot: [.film]),
        Known(title: "Sicario", year: 2015, has: [.digital], hasNot: [.film]),
        Known(title: "Skyfall", year: 2012, has: [.digital], hasNot: [.film]),
        Known(title: "1917", year: 2019, has: [.digital], hasNot: [.film]),
        Known(title: "Joker", year: 2019, has: [.digital], hasNot: [.film]),
        Known(title: "The Revenant", year: 2015, has: [.digital], hasNot: [.film]),
        Known(title: "The Substance", year: 2024, has: [.digital], hasNot: [.film]),
        Known(title: "Parasite", year: 2019, has: [.digital], hasNot: [.film]),
    ]

    func testShotOnForFilmsOnRecord() async throws {
        guard let token = ProcessInfo.processInfo.environment["TMDB_TOKEN"], !token.isEmpty else {
            throw XCTSkip("TMDB_TOKEN not set")
        }
        let client = TMDBClient(token: token)
        var read = 0, expected = 0
        var lines: [String] = [], wrong: [String] = [], missing: [String] = []
        for known in films {
            guard let id = try? await client.searchMovies(query: known.title, year: known.year).first?.id,
                  let details = try? await client.movieDetails(id: id) else {
                print("Shot on: \(known.title): not found on TMDB")
                continue
            }
            let facts = try? await WikipediaClient().findings(imdbID: details.imdbID, title: details.title, year: details.year).funFacts
            var others: [String] = []
            if let collection = details.collection, let set = try? await client.collection(id: collection.id) {
                others = set.parts.filter { $0.id != details.id }.map(\.title)
            }
            guard let craft = await CraftReader.read(details, articleTitle: facts?.articleTitle, colour: facts?.quick?.colour,
                                                     otherTitles: others) else {
                print("Shot on: \(known.title): nothing could be reached")
                continue
            }
            read += 1
            expected += known.has.count + known.hasNot.count
            let tags = craft.shotOn.map { craft.label(for: $0) }.joined(separator: ", ")
            lines.append("\(known.title): \(tags.isEmpty ? "nothing" : tags) (\(craft.sources) texts)")
            for tag in ShotOn.allCases where craft.shotOn.contains(tag) && known.hasNot.contains(tag) {
                wrong.append("\(known.title) \(tag.title)")
                let why = craft.evidence(for: tag).map { "\($0.source): \($0.text.prefix(220))" } ?? ""
                print("::warning::Shot on wrong: \(known.title) is not \(tag.title): \(why)")
            }
            for tag in ShotOn.allCases where known.has.contains(tag) && !craft.shotOn.contains(tag) {
                missing.append("\(known.title) \(tag.title)")
            }
        }
        // One line each (a step shows ten notices at most).
        print("::notice::Shot on read: " + lines.joined(separator: " · "))
        print("::notice::Shot on check: \(wrong.count) wrong, \(missing.count) missing, of \(expected) known tags across \(read) of \(films.count) films read. Wrong: \(wrong.joined(separator: ", ")). Missing: \(missing.joined(separator: ", "))")
        try XCTSkipIf(read == 0, "no film could be read: the sources may be refusing for now")
    }
}
