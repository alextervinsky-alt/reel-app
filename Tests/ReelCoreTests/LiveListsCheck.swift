import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ReelCore

/// The 1.11 lists read live (spec §8.3): the new Wikidata award lists as the app reads them, and
/// whether TMDB finds every film of the two bundled polls by title and year, as the app does. Runs
/// only when REEL_LISTS_CHECK is set; CI's lists-check job does that.
final class LiveListsCheck: XCTestCase {
    func testTheNewListsLive() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["REEL_LISTS_CHECK"] != nil, let token = env["TMDB_TOKEN"], !token.isEmpty else {
            throw XCTSkip("REEL_LISTS_CHECK and TMDB_TOKEN not set")
        }
        let new: [AwardList] = [.oscarDocumentary, .veniceGrandJury, .berlinGrandJury, .baftaCinematography, .europeanCinematography]
        for award in new {
            let films = (try? await WikidataLists().films(award)) ?? []
            let winners = films.filter(\.isWinner)
            let years = Set(winners.compactMap { $0.rank.flatMap(Int.init) })
            let ids = winners.filter { $0.tmdbID != nil }.count
            print("LISTS| \(award.title): \(winners.count) winners (\(ids) with a TMDB id), \(films.count - winners.count) nominees, "
                  + "winners in \(years.count) years \(years.min() ?? 0)–\(years.max() ?? 0); newest: \(winners.first?.note ?? "-")")
            XCTAssertGreaterThan(winners.count, 20, award.title)
        }
        let client = TMDBClient(token: token)
        for (name, films) in [("Directors' poll", DirectorsPoll.films), ("AFI", AFIList.films)] {
            var missing: [String] = []
            for film in films {
                let results = (try? await client.searchMovies(query: film.title, year: nil)) ?? []
                let best = FilmMatcher.rank(results, title: film.title, year: film.year).best
                if best == nil || best!.score < 0.6 { missing.append("\(film.title) (\(film.year ?? 0))") }
            }
            print("LISTS| \(name): \(films.count - missing.count) of \(films.count) found on TMDB; missing: \(missing.joined(separator: "; "))")
        }
    }
}
