import XCTest
@testable import ReelCore

/// Reel 1.9.4: the year's most acclaimed films, from critics, audiences, how widely seen and the
/// big prizes, with made-up films.
final class AcclaimTests: XCTestCase {
    private func film(_ id: String, rating: Double, votes: Int, year: Int = 2025) -> IMDbFilm {
        IMDbFilm(id: id, title: "Film \(id)", year: year, rating: rating, votes: votes)
    }

    func testCriticsAudiencesAndPrizesTogetherOutrankOneSitesVoters() {
        let agreed = Acclaim.Candidate(film: film("tt1", rating: 7.9, votes: 300_000), tmdbVote: 7.8, tmdbVotes: 3_000,
                                       metacritic: 92, rottenTomatoes: 95, prize: .topPrize, prizeName: "Palme d'Or")
        // Rated 8.6 on IMDb by many, but much lower on TMDB, and no critics' score.
        let oneSite = Acclaim.Candidate(film: film("tt2", rating: 8.6, votes: 500_000), tmdbVote: 7.0, tmdbVotes: 800)
        let blockbuster = Acclaim.Candidate(film: film("tt3", rating: 7.6, votes: 900_000), tmdbVote: 7.5, tmdbVotes: 9_000,
                                            metacritic: 74, rottenTomatoes: 88)
        let liked = Acclaim.Candidate(film: film("tt4", rating: 6.4, votes: 120_000), tmdbVote: 6.3, tmdbVotes: 2_000,
                                      metacritic: 55, rottenTomatoes: 60)
        let ranked = Acclaim.rank([liked, oneSite, blockbuster, agreed]).map { $0.candidate.film.id }
        XCTAssertEqual(ranked, ["tt1", "tt3", "tt2", "tt4"])
    }

    func testWithoutAnyCriticsAudiencesAndPrizesDecide() {
        let a = Acclaim.Candidate(film: film("tt1", rating: 8.0, votes: 200_000), prize: .nominated, prizeName: "Nominated: Oscar for Best Picture")
        let b = Acclaim.Candidate(film: film("tt2", rating: 8.0, votes: 200_000))
        let c = Acclaim.Candidate(film: film("tt3", rating: 6.0, votes: 900_000))
        XCTAssertEqual(Acclaim.rank([c, b, a]).map { $0.candidate.film.id }, ["tt1", "tt2", "tt3"])
    }

    func testThePoolIsTheBestKnownAndTheAwarded() {
        var films = (0..<200).map { film("tt\($0)", rating: 7, votes: 10_000 + $0) }
        films.append(film("tt-festival", rating: 7.4, votes: 2_500))
        films.append(film("tt-old", rating: 9, votes: 900_000, year: 2024))
        let pool = Acclaim.pool(films, year: 2025, awarded: ["tt-festival"], size: 120)
        XCTAssertEqual(pool.count, 121)
        XCTAssertEqual(pool.first?.id, "tt199", "the most voted first")
        XCTAssertTrue(pool.contains { $0.id == "tt-festival" }, "a prize winner with few votes is in the running")
        XCTAssertFalse(pool.contains { $0.year != 2025 })
    }

    func testTheBestPrizeEachFilmHad() {
        func entry(_ id: String, won: Bool) -> ListFilm {
            ListFilm(imdbID: id, tmdbID: nil, title: id, year: 2025, note: nil, won: won)
        }
        let prizes = Acclaim.prizes([
            (.oscarBestPicture, [entry("tt1", won: false), entry("tt2", won: true)]),
            (.palmeDOr, [entry("tt1", won: true)]),
            (.baftaBestFilm, [entry("tt3", won: true)]),
            (.criterion, [entry("tt4", won: true)]),
        ], year: 2025)
        XCTAssertEqual(prizes["tt1"]?.prize, .topPrize)
        XCTAssertEqual(prizes["tt1"]?.name, "Palme d'Or")
        XCTAssertEqual(prizes["tt2"]?.name, "Oscar for Best Picture")
        XCTAssertEqual(prizes["tt3"]?.prize, .won)
        XCTAssertNil(prizes["tt4"], "a collection isn't a prize")
    }

    func testTheNoteSaysWhatCriticsAndAudiencesSaid() {
        XCTAssertEqual(Acclaim.note(Acclaim.Candidate(film: film("tt1", rating: 7.94, votes: 1), metacritic: 95)), "Metacritic 95 · IMDb 7.9")
        XCTAssertEqual(Acclaim.note(Acclaim.Candidate(film: film("tt1", rating: 7.9, votes: 1), rottenTomatoes: 91)), "RT 91% · IMDb 7.9")
        XCTAssertEqual(Acclaim.note(Acclaim.Candidate(film: film("tt1", rating: 8.4, votes: 1), tmdbVote: 7.1, tmdbVotes: 900)),
                       "IMDb 8.4 · TMDB 7.1")
        XCTAssertEqual(FilmListKind.acclaimed(2025).title, "The Most Acclaimed of 2025")
    }
}
