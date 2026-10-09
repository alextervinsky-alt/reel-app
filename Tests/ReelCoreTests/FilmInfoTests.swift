import XCTest
@testable import ReelCore

final class FilmInfoTests: XCTestCase {
    func testOMDbParsing() {
        let json = """
        {"Title":"Blade Runner 2049","Rated":"R","Awards":"Won 2 Oscars. 101 wins & 352 nominations total",
         "Ratings":[{"Source":"Internet Movie Database","Value":"8.0/10"},{"Source":"Rotten Tomatoes","Value":"88%"},
                    {"Source":"Metacritic","Value":"81/100"}],
         "Metascore":"81","imdbRating":"8.0","imdbVotes":"716,415","imdbID":"tt1856101","Response":"True"}
        """
        let r = OMDbClient.parse(Data(json.utf8))
        XCTAssertEqual(r?.imdb, 8.0)
        XCTAssertEqual(r?.imdbVotes, 716_415)
        XCTAssertEqual(r?.rottenTomatoes, 88)
        XCTAssertEqual(r?.metacritic, 81)
        XCTAssertEqual(r?.rated, "R")
        XCTAssertEqual(r?.awards, "Won 2 Oscars. 101 wins & 352 nominations total")

        let missing = #"{"imdbRating":"N/A","Metascore":"N/A","Ratings":[],"Response":"True"}"#
        XCTAssertEqual(OMDbClient.parse(Data(missing.utf8))?.isEmpty, true)
        XCTAssertNil(OMDbClient.parse(Data(#"{"Response":"False","Error":"Incorrect IMDb ID."}"#.utf8)))
    }

    func testDetailsKeepWhatReelShows() throws {
        let json = """
        {"id": 335984, "title": "Blade Runner 2049", "runtime": 164,
         "belongs_to_collection": {"id": 422837, "name": "Blade Runner Collection", "poster_path": "/p.jpg"},
         "credits": {"cast": [], "crew": [
            {"name": "Denis Villeneuve", "job": "Director"}, {"name": "Roger Deakins", "job": "Director of Photography"},
            {"name": "Joe Walker", "job": "Editor"}, {"name": "Hans Zimmer", "job": "Original Music Composer"},
            {"name": "Dennis Gassner", "job": "Production Design"}, {"name": "Someone", "job": "Grip"}]},
         "keywords": {"keywords": [{"id": 1, "name": "dystopia"}, {"id": 2, "name": "artificial intelligence"}]},
         "videos": {"results": [
            {"key": "c1", "site": "YouTube", "type": "Clip"}, {"key": "c2", "site": "YouTube", "type": "Clip"},
            {"key": "c3", "site": "YouTube", "type": "Featurette"}, {"key": "c4", "site": "YouTube", "type": "Clip"},
            {"key": "c5", "site": "YouTube", "type": "Teaser"}, {"key": "c6", "site": "YouTube", "type": "Clip"},
            {"key": "v1", "site": "Vimeo", "type": "Trailer"}, {"key": "t1", "site": "YouTube", "type": "Trailer", "official": true}]},
         "images": {"backdrops": [{"file_path": "/text.jpg", "iso_639_1": "en", "vote_average": 9},
                                  {"file_path": "/still1.jpg", "iso_639_1": null, "vote_average": 5},
                                  {"file_path": "/still2.jpg", "iso_639_1": null, "vote_average": 7}],
                    "logos": [{"file_path": "/logo-fr.png", "iso_639_1": "fr"}, {"file_path": "/logo.png", "iso_639_1": "en"}]},
         "reviews": {"results": [{"author": "a", "content": "Great.", "author_details": {"rating": 9}}], "total_results": 1}}
        """
        let full = try JSONDecoder().decode(TMDBMovieDetails.self, from: Data(json.utf8))
        XCTAssertEqual(full.reviews?.results.count, 1)
        let d = full.trimmed()
        XCTAssertNil(d.reviews)
        XCTAssertEqual(d.cinematographers, ["Roger Deakins"])
        XCTAssertEqual(d.people(forJobs: ["Editor"]).map { $0.name }, ["Joe Walker"])
        XCTAssertEqual(d.people(forJobs: TMDBMovieDetails.composerJobs).map { $0.name }, ["Hans Zimmer"])
        XCTAssertEqual(d.credits?.crew.count, 5)
        XCTAssertEqual(d.stillPaths, ["/still2.jpg", "/still1.jpg"])
        XCTAssertEqual(d.logoPath, "/logo.png")
        XCTAssertEqual(d.collection?.name, "Blade Runner Collection")
        XCTAssertEqual(d.keywordNames, ["dystopia", "artificial intelligence"])
        XCTAssertEqual(Trailers.candidates(d.videos?.results ?? [], title: d.title, preferTeaser: false,
                                           originalLanguage: d.originalLanguage).map(\.key), ["t1"],
                       "someone else's upload with no name isn't trusted")
        XCTAssertEqual(d.videos?.results.map(\.key), ["c5", "t1"], "only YouTube trailers and teasers are kept")
    }

    func testReceptionFindsLikesAndDislikes() {
        let reviews = [
            ReviewText(text: "The cinematography is stunning and every shot looks like a painting. The story is thin though and a bit predictable.", rating: 7),
            ReviewText(text: "Deakins' cinematography is breathtaking. The score by Zimmer is overwhelming in the best way. It drags in the middle and feels overlong.", rating: 8),
            ReviewText(text: "Gorgeous visuals, great performances from the whole cast. But the pacing is so slow and tedious at times.", rating: 6),
            ReviewText(text: "<em>Boring.</em> The plot is predictable and the runtime is far too long for what it says.", rating: 4),
        ]
        // A crude stand-in for the Mac's sentiment model.
        let sentiment: (String) -> Double = { s in
            let l = s.lowercased()
            var score = 0.0
            for w in ["stunning", "breathtaking", "best", "gorgeous", "great"] where l.contains(w) { score += 0.5 }
            for w in ["thin", "boring", "slow", "tedious", "far too long"] where l.contains(w) { score -= 0.5 }
            return max(-1, min(1, score))
        }
        let summary = try! XCTUnwrap(ReceptionAnalyzer.summarize(reviews, sentiment: sentiment))
        XCTAssertEqual(summary.reviewCount, 4)
        XCTAssertEqual(summary.averageRating, 6.25)
        XCTAssertEqual(summary.liked.first?.aspect, "Visuals")
        XCTAssertTrue(summary.disliked.map { $0.aspect }.contains("Pacing"))
        XCTAssertTrue(summary.disliked.map { $0.aspect }.contains("Story"))
        XCTAssertFalse(summary.liked.map { $0.aspect }.contains("Pacing"))
        XCTAssertNotNil(summary.liked.first?.quote)
        XCTAssertNil(ReceptionAnalyzer.summarize([], sentiment: sentiment))
    }

    func testCleaningAndSentences() {
        XCTAssertEqual(ReceptionAnalyzer.clean("**Wow** <b>this</b> is _great_"), "Wow this is great")
        let parts = ReceptionAnalyzer.sentences(in: "Short. This sentence is long enough to count as a sentence! And so is this one, with Mr. Smith in it?\nA line break also ends a sentence here.")
        XCTAssertEqual(parts.count, 3)
        XCTAssertTrue(ReceptionAnalyzer.shorten(String(repeating: "word ", count: 80)).hasSuffix("…"))
    }

    func testMoods() {
        let bladeRunner = MoodClassifier.moods(
            genres: ["Science Fiction", "Drama"],
            keywords: ["dystopia", "artificial intelligence", "neo-noir", "replicant", "future"],
            runtime: 164)
        XCTAssertEqual(Set(bladeRunner), [.dark, .mindBending, .epic])

        let comedy = MoodClassifier.moods(genres: ["Comedy", "Family"], keywords: ["friendship"], runtime: 95)
        XCTAssertTrue(comedy.contains(.funny))
        XCTAssertTrue(comedy.contains(.feelGood))
        XCTAssertTrue(MoodClassifier.moods(genres: ["Horror"], keywords: ["haunted house"], runtime: 100).contains(.scary))
        XCTAssertFalse(MoodClassifier.moods(genres: ["Horror", "Comedy"], keywords: [], runtime: 90).contains(.feelGood))
        XCTAssertTrue(MoodClassifier.moods(genres: [], keywords: [], runtime: nil).isEmpty)
    }

    func testLengthBands() {
        XCTAssertTrue(LengthBand.short.contains(85))
        XCTAssertTrue(LengthBand.standard.contains(120))
        XCTAssertTrue(LengthBand.long.contains(135))
        XCTAssertTrue(LengthBand.epic.contains(164))
        XCTAssertFalse(LengthBand.short.contains(nil))
        XCTAssertTrue(LengthBand.any.contains(nil))
    }

    func testFailedRatingsAreRetriedSeparately() {
        var entry = FilmEntry(driveID: "D", relativePath: "a.mkv", fileName: "a.mkv", size: 1, modified: nil, addedAt: Date())
        let details = TMDBMovieDetails(id: 1, title: "A")
        entry.apply(details, ratings: nil, ratingsFailed: true, reception: nil)
        XCTAssertEqual(entry.infoVersion, FilmEntry.currentInfoVersion)
        XCTAssertTrue(entry.ratingsDue)
        entry.applyRatings(ExternalRatings(imdb: 7.1), failed: false)
        XCTAssertFalse(entry.ratingsDue)
        entry.apply(details, ratings: nil, ratingsFailed: true, reception: nil)
        XCTAssertEqual(entry.ratings?.imdb, 7.1)
        XCTAssertFalse(entry.ratingsDue)
    }

    func testFilmography() throws {
        let json = """
        {"id": 151, "name": "Roger Deakins", "known_for_department": "Camera",
         "movie_credits": {
           "cast": [{"id": 9, "title": "Making Of", "character": "Himself", "release_date": "2018-01-01"},
                    {"id": 7, "title": "Cameo Film", "character": "Bartender", "release_date": "2001-05-01"}],
           "crew": [{"id": 335984, "title": "Blade Runner 2049", "job": "Director of Photography", "department": "Camera", "release_date": "2017-10-04", "vote_count": 14000},
                    {"id": 335984, "title": "Blade Runner 2049", "job": "Additional Photography", "department": "Camera", "release_date": "2017-10-04"},
                    {"id": 6977, "title": "No Country for Old Men", "job": "Director of Photography", "department": "Camera", "release_date": "2007-11-08"},
                    {"id": 999, "title": "Untitled Project", "job": "Director of Photography", "department": "Camera"}]}}
        """
        let person = try JSONDecoder().decode(TMDBPerson.self, from: Data(json.utf8))
        let films = Filmography.build(person)
        XCTAssertEqual(films.map { $0.id }, [999, 335984, 6977, 7])
        XCTAssertEqual(films[1].roles, ["Director of Photography", "Additional Photography"])
        XCTAssertEqual(films[3].roles, ["as Bartender"])
        XCTAssertEqual(Filmography.departments(in: films), ["Camera", "Acting"])
    }

    func testFunFactsPicksBehindTheScenes() {
        let extract = """
        Blade Runner 2049 is a 2017 American science fiction film.

        == Plot ==
        K, a replicant, was originally built to hunt older models and discovers a secret in 2049 that changes everything.

        == Production ==
        === Development ===
        Ridley Scott originally intended to direct the sequel but stepped back to produce, citing his schedule with another film.
        === Casting ===
        Harrison Ford was confirmed in November 2015, and Ryan Gosling had reportedly turned down other offers to join the cast.
        It was a quiet time for everyone involved with the casting process.
        === Filming ===
        Principal photography took place in Budapest over four months, with large practical sets built at Origo Studios.
        === Visual effects ===
        The film won the Academy Award for Best Visual Effects after effects teams spent months building miniatures for the city.

        == Reception ==
        === Box office ===
        Blade Runner 2049 grossed $92 million in the United States and Canada against a production budget of $150 million.
        === Critical response ===
        Critics praised it as one of the best sequels ever made, with a 88% approval rating on review aggregators.
        The website's critical consensus reads, "Visually stunning and narratively satisfying, Blade Runner 2049 deepens and expands its predecessor's story." Audiences polled by CinemaScore gave the film an average grade of "A−" on an A+ to F scale.
        """
        let picked = FunFactExtractor.facts(fromExtract: extract)
        let facts = picked.facts
        XCTAssertNotNil(picked.highlight)
        XCTAssertEqual(FunFactExtractor.consensus(fromExtract: extract),
                       "Visually stunning and narratively satisfying, Blade Runner 2049 deepens and expands its predecessor's story.")
        XCTAssertEqual(FunFactExtractor.cinemaScore(fromExtract: extract), "A−")
        XCTAssertEqual(FunFactExtractor.criticSentences(fromExtract: extract).first?.hasPrefix("Critics praised"), true)
        let categories = facts.map { $0.category }
        XCTAssertEqual(categories, ["Story & script", "Casting", "On set", "Effects", "Release"])
        XCTAssertFalse(facts.contains { $0.text.contains("replicant") }, "no plot")
        XCTAssertFalse(facts.contains { $0.text.contains("Critics praised") })
        XCTAssertFalse(facts.contains { $0.text.hasPrefix("It was") })

        let stored = FunFacts(facts: facts, articleTitle: "Blade Runner 2049", fetchedAt: Date())
        XCTAssertEqual(stored.articleURL?.absoluteString, "https://en.wikipedia.org/wiki/Blade_Runner_2049")
    }

    func testAlwaysTwoLikesAndTwoDislikesWhenPossible() {
        let reviews = [
            ReviewText(text: "A gorgeous film with stunning visuals and a beautiful score throughout the whole thing.", rating: 9),
            ReviewText(text: "The acting is brilliant and the cinematography is breathtaking in every single frame.", rating: 9),
            ReviewText(text: "Honestly the pacing is so slow and boring that I nearly fell asleep halfway.", rating: 5, isCritic: true),
            ReviewText(text: "The ending felt weak and disappointing after such a long build-up of tension.", rating: nil, isCritic: true),
        ]
        let sentiment: (String) -> Double = { s in
            let l = s.lowercased()
            if ["gorgeous", "brilliant", "breathtaking"].contains(where: { l.contains($0) }) { return 0.8 }
            if ["boring", "weak", "slow"].contains(where: { l.contains($0) }) { return -0.7 }
            return 0
        }
        let summary = try! XCTUnwrap(ReceptionAnalyzer.summarize(reviews, sentiment: sentiment))
        XCTAssertGreaterThanOrEqual(summary.liked.count, 2)
        XCTAssertGreaterThanOrEqual(summary.disliked.count, 2)
        XCTAssertEqual(summary.reviewCount, 2)
        XCTAssertEqual(summary.criticCount, 2)
        XCTAssertEqual(summary.averageRating, 9)
    }

    func testVerdictSentences() {
        let reception = ReceptionSummary(
            liked: [ReceptionPoint(aspect: "Visuals", mentions: 5, quote: nil), ReceptionPoint(aspect: "Direction", mentions: 3, quote: nil)],
            disliked: [ReceptionPoint(aspect: "Pacing", mentions: 4, quote: nil), ReceptionPoint(aspect: "Story", mentions: 2, quote: nil)],
            reviewCount: 10, averageRating: 7)

        let criticsDarling = ReceptionVerdict.sentence(
            ratings: ExternalRatings(imdb: 6.6, rottenTomatoes: 92, metacritic: 86), tmdbVote: nil, reception: reception, cinemaScore: nil)
        XCTAssertEqual(criticsDarling, "A critics' favourite for its visuals and its direction, but casual audiences were cooler on it, mostly because of its slow pacing and its story.")

        let loved = ReceptionVerdict.sentence(
            ratings: ExternalRatings(imdb: 8.0, rottenTomatoes: 88, metacritic: 81), tmdbVote: nil, reception: reception, cinemaScore: "A−")
        XCTAssertEqual(loved, "Loved by critics and audiences alike, especially for its visuals and its direction. A few found its slow pacing a weak spot. Opening-night audiences gave it an A− CinemaScore.")

        let crowd = ReceptionVerdict.sentence(
            ratings: ExternalRatings(imdb: 7.6, rottenTomatoes: 45, metacritic: 50), tmdbVote: nil, reception: reception, cinemaScore: "B+")
        XCTAssertTrue(crowd?.hasPrefix("A crowd-pleaser: audiences enjoyed its visuals") == true)
        XCTAssertTrue(crowd?.hasSuffix("gave it a B+ CinemaScore.") == true)

        XCTAssertNil(ReceptionVerdict.sentence(ratings: nil, tmdbVote: nil, reception: nil, cinemaScore: nil))
    }

    func testSimilarFilmsRanking() {
        func movie(_ id: Int, _ genres: [Int], votes: Int = 500) -> TMDBMovieSummary {
            TMDBMovieSummary(id: id, title: "M\(id)", voteCount: votes, genreIDs: genres)
        }
        let ranked = SimilarFilms.rank(
            recommendations: [movie(1, [878, 18]), movie(2, [35]), movie(99, [878])],
            similar: [movie(1, [878, 18]), movie(3, [878, 18]), movie(4, [878], votes: 10)],
            genres: ["Science Fiction", "Drama"], excluding: 99)
        XCTAssertEqual(ranked.first?.id, 1)
        XCTAssertFalse(ranked.contains { $0.id == 99 })
        XCTAssertFalse(ranked.contains { $0.id == 4 }, "too few votes")
        XCTAssertTrue(ranked.allSatisfy { (55...98).contains($0.match) })
        XCTAssertGreaterThan(ranked.first { $0.id == 3 }!.match, ranked.first { $0.id == 2 }!.match)
    }

    func testDiscoverRequests() {
        let today = ISO8601DateFormatter().date(from: "2026-10-06T08:00:00Z")!
        let home = DiscoverList.newAtHome.request(today: today)
        XCTAssertEqual(home.path, "/discover/movie")
        XCTAssertTrue(home.query.contains(URLQueryItem(name: "primary_release_date.gte", value: "2026-05-09")))
        XCTAssertTrue(home.query.contains(URLQueryItem(name: "primary_release_date.lte", value: "2026-07-08")))
        let best = DiscoverList.bestOf(year: 1994).request(today: today)
        XCTAssertEqual(best.pages, 5)
        XCTAssertTrue(best.query.contains(URLQueryItem(name: "primary_release_year", value: "1994")))
        let gems = DiscoverList.bestOf(year: 2019, source: .gems).request(today: today)
        XCTAssertTrue(gems.query.contains(URLQueryItem(name: "vote_count.lte", value: "1000")))
        XCTAssertEqual(DiscoverList.bestOf(year: 2019, source: .popular).request(today: today).query.first { $0.name == "sort_by" }?.value,
                       "popularity.desc")
        XCTAssertEqual(DiscoverList.because(id: 496243, title: "Parasite").request(today: today).path, "/movie/496243/recommendations")
        XCTAssertTrue(DiscoverList.decade(1970).request(today: today).query.contains(URLQueryItem(name: "primary_release_date.lte", value: "1979-12-31")))
        XCTAssertEqual(DiscoverList.country(code: "JP").title, "Cinema from Japan")
    }

    func testThreeShelvesEachLaunch() {
        var generator = SystemRandomNumberGenerator()
        let shelves = DiscoverList.shelves(loved: [(496243, "Parasite")], using: &generator)
        XCTAssertEqual(shelves.count, 3)
        XCTAssertEqual(shelves.first, .because(id: 496243, title: "Parasite"))
        XCTAssertEqual(DiscoverList.shelves(loved: [], using: &generator).count, 2, "no loved films: no Because You Loved")
    }

    func testWikipediaFallbackOnlyAcceptsExactTitles() {
        let accepted = WikipediaClient.acceptedTitles(title: "Home", year: 2009)
        XCTAssertTrue(accepted.contains(TitleSimilarity.normalize("Home (2009 film)")))
        XCTAssertTrue(accepted.contains(TitleSimilarity.normalize("Home (film)")))
        XCTAssertFalse(accepted.contains(TitleSimilarity.normalize("Home Alone")))
        XCTAssertFalse(accepted.contains(TitleSimilarity.normalize("Home")), "bare titles need a separate check")
        XCTAssertFalse(accepted.contains(TitleSimilarity.normalize("Dune (novel)")))
    }

    func testRatingsStaleness() {
        var entry = FilmEntry(driveID: "D", relativePath: "a.mkv", fileName: "a.mkv", size: 1, modified: nil, addedAt: Date())
        XCTAssertTrue(entry.ratingsStale())
        entry.ratings = ExternalRatings(imdb: 7)
        XCTAssertFalse(entry.ratingsStale(), "saved by an older version without a date")
        entry.ratingsTriedAt = Date().addingTimeInterval(-40 * 86_400)
        XCTAssertTrue(entry.ratingsStale())
    }

    func testOlderEntriesAreMarkedForRefresh() throws {
        let json = """
        {"driveID": "D", "relativePath": "a.mkv", "fileName": "a.mkv", "size": 1, "addedAt": "2026-10-05T10:00:00Z",
         "matchState": "auto", "candidates": []}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(FilmEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.infoVersion, 1)
        XCTAssertLessThan(entry.infoVersion, FilmEntry.currentInfoVersion)
        XCTAssertNil(entry.ratings)
        XCTAssertNil(entry.checkedStills)

        let oldNotes = #"{"version": 2, "records": {}, "corrections": {"a.mkv": 1}}"#
        let notes = try JSONDecoder().decode(PersonalFile.self, from: Data(oldNotes.utf8))
        XCTAssertEqual(notes.wishlist, [])
        XCTAssertEqual(notes.corrections["a.mkv"], 1)
    }
}
