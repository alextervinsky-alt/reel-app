import XCTest
@testable import ReelCore

/// Live, run with the TMDB check (not offline): how many well-known films the magazines' searches
/// find an interview for. It reports, and never fails a build.
final class LiveCraftSourcesTests: XCTestCase {
    func testMagazinesFindInterviews() async throws {
        let films = ["Sicario", "Dune", "Oppenheimer", "1917", "La La Land", "The Lighthouse", "Roma", "Parasite",
                     "Nomadland", "The Revenant", "Ex Machina", "Drive My Car", "Joker", "Arrival", "Blade Runner 2049"]
        let client = CameraSourcesClient()
        var found = 0
        let unanswered = UnansweredSites()
        for title in films {
            async let asc = client.ascArticles(filmTitle: title, noting: unanswered)
            async let british = client.britishCinematographer(filmTitle: title, noting: unanswered)
            let hits = await asc + british
            if !hits.isEmpty { found += 1 }
            print("Craft sources: \(title): \(hits.map { $0.site + ": " + ($0.title ?? "") })")
        }
        let quiet = await unanswered.all()
        print("Craft sources: \(found) of \(films.count) films have an interview found" + (quiet.isEmpty ? "" : " (didn't answer or asked to wait: \(quiet.joined(separator: ", ")))"))
        // Nothing at all within seconds is a site refusing for a while (or the network), not proof
        // the search changed: reported (the notice says "0 of 15"), not a failed build.
        try XCTSkipIf(found == 0, "no interview found for any film: the sites may be refusing for now, or their search changed")
    }
}
