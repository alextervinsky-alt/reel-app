import XCTest
@testable import ReelCore

/// Live, run with the TMDB check (not offline): how many well-known films the magazines' searches
/// find an interview for. It reports; it fails only when nothing at all is found (the sites, or
/// the way Reel asks them, changed).
final class LiveCraftSourcesTests: XCTestCase {
    func testMagazinesFindInterviews() async throws {
        let films = ["Sicario", "Dune", "Oppenheimer", "1917", "La La Land", "The Lighthouse", "Roma", "Parasite",
                     "Nomadland", "The Revenant", "Ex Machina", "Drive My Car", "Joker", "Arrival", "Blade Runner 2049"]
        let client = CameraSourcesClient()
        var found = 0
        for title in films {
            async let asc = client.ascArticles(filmTitle: title)
            async let british = client.britishCinematographer(filmTitle: title)
            let hits = await asc + british
            if !hits.isEmpty { found += 1 }
            print("Craft sources: \(title): \(hits.map { $0.site + ": " + ($0.title ?? "") })")
        }
        print("Craft sources: \(found) of \(films.count) films have an interview found")
        XCTAssertGreaterThan(found, 0, "no interview found for any film: the magazines' search changed")
    }
}
