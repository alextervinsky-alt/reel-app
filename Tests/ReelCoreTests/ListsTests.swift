import XCTest
@testable import ReelCore

final class ListsTests: XCTestCase {
    // MARK: IMDb files

    func testIMDbLinesAreReadFromGzip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reel-imdb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let ratings = """
        tconst\taverageRating\tnumVotes
        tt0137523\t8.8\t2400000
        tt0133093\t8.7\t2100000
        tt9999999\t9.5\t40
        tt0000001\t5.7\t2100
        """
        let basics = """
        tconst\ttitleType\tprimaryTitle\toriginalTitle\tisAdult\tstartYear\tendYear\truntimeMinutes\tgenres
        tt0000001\tshort\tCarmencita\tCarmencita\t0\t1894\t\\N\t1\tDocumentary,Short
        tt0133093\tmovie\tThe Matrix\tThe Matrix\t0\t1999\t\\N\t136\tAction,Sci-Fi
        tt0137523\tmovie\tFight Club\tFight Club\t0\t1999\t\\N\t139\tDrama
        tt9999999\tmovie\tObscure\tObscure\t0\t1999\t\\N\t90\tDrama
        """
        let ratingsFile = try gzip(ratings, named: "ratings", in: dir)
        let basicsFile = try gzip(basics, named: "basics", in: dir)

        let films = try IMDbDataset.build(ratingsFile: ratingsFile, basicsFile: basicsFile)
        XCTAssertEqual(films.map { $0.title }, ["The Matrix", "Fight Club"], "shorts and films with few votes are left out")
        XCTAssertEqual(films.first?.id, "tt0133093")
        XCTAssertEqual(films.first?.votes, 2_100_000)
    }

    private func gzip(_ text: String, named name: String, in dir: URL) throws -> URL {
        let plain = dir.appendingPathComponent(name + ".tsv")
        try Data((text + "\n").utf8).write(to: plain)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-f", plain.path]
        try process.run()
        process.waitUntilExit()
        return dir.appendingPathComponent(name + ".tsv.gz")
    }

    func testTopOfYearWeighsVotes() {
        var films = (0..<400).map { IMDbFilm(id: "tt\($0)", title: "Film \($0)", year: 1999, rating: 6.5, votes: 30_000 + $0) }
        films.append(IMDbFilm(id: "tt-loved", title: "Loved by millions", year: 1999, rating: 8.8, votes: 2_000_000))
        films.append(IMDbFilm(id: "tt-niche", title: "Loved by few", year: 1999, rating: 9.4, votes: 1_200))
        films.append(IMDbFilm(id: "tt-other", title: "Other year", year: 2000, rating: 9.9, votes: 900_000))

        let top = IMDbDataset.top(films, year: 1999, count: 10)
        XCTAssertEqual(top.first?.title, "Loved by millions")
        XCTAssertFalse(top.contains { $0.title == "Loved by few" }, "too few votes for its year")
        XCTAssertFalse(top.contains { $0.year != 1999 })
        XCTAssertEqual(IMDbDataset.topAllTime(films, count: 1).first?.title, "Other year")
        XCTAssertEqual(ListFilm(films[400]).note, "8.8 · 2.0M votes")
    }

    // MARK: Wikidata

    func testAwardRowsBecomeOneFilmEach() {
        let rows: [[String: String]] = [
            ["film": "http://www.wikidata.org/entity/Q1", "filmLabel": "Parasite", "imdb": "tt6751668",
             "tmdb": "496243", "released": "2019-05-21T00:00:00Z", "date": "2019-01-01T00:00:00Z"],
            ["film": "http://www.wikidata.org/entity/Q1", "filmLabel": "Parasite", "imdb": "tt6751668",
             "released": "2019-05-30T00:00:00Z"],
            ["film": "http://www.wikidata.org/entity/Q2", "filmLabel": "Pulp Fiction", "imdb": "tt0110912",
             "released": "1994-05-21T00:00:00Z", "date": "1994-01-01T00:00:00Z"],
            ["film": "http://www.wikidata.org/entity/Q3", "filmLabel": "Q3", "imdb": "tt0000003"],
            ["film": "http://www.wikidata.org/entity/Q4", "filmLabel": "A Director", "imdb": "nm0000001"],
        ]
        let films = WikidataLists.films(from: rows, list: .palmeDOr)
        XCTAssertEqual(films.map { $0.title }, ["Parasite", "Pulp Fiction"])
        XCTAssertEqual(films.first?.tmdbID, 496243)
        XCTAssertEqual(films.first?.note, "Won 2019")

        let criterion = WikidataLists.films(from: [
            ["film": "http://www.wikidata.org/entity/Q5", "filmLabel": "Seven Samurai", "imdb": "tt0047478", "number": "2"],
            ["film": "http://www.wikidata.org/entity/Q6", "filmLabel": "Grand Illusion", "imdb": "tt0028950", "number": "1"],
        ], list: .criterion)
        XCTAssertEqual(criterion.map { $0.note }, ["Spine #1", "Spine #2"])
        XCTAssertTrue(AwardList.palmeDOr.query.contains("\"Palme d'Or\"@en"))
    }

    func testNomineesAndPeopleAwards() {
        let rows: [[String: String]] = [
            // Best Director: the award is on the person, the film is "for work".
            ["film": "http://www.wikidata.org/entity/Q10", "filmLabel": "Oppenheimer", "imdb": "tt15398776",
             "personLabel": "Christopher Nolan", "date": "2024-03-10T00:00:00Z", "won": "1"],
            ["film": "http://www.wikidata.org/entity/Q10", "filmLabel": "Oppenheimer", "imdb": "tt15398776",
             "personLabel": "Christopher Nolan", "date": "2024-03-10T00:00:00Z", "won": "0"],
            ["film": "http://www.wikidata.org/entity/Q11", "filmLabel": "Anatomy of a Fall", "imdb": "tt17009710",
             "personLabel": "Justine Triet", "date": "2024-03-10T00:00:00Z", "won": "0"],
            ["film": "http://www.wikidata.org/entity/Q12", "filmLabel": "Poor Things", "imdb": "tt14230458",
             "date": "2023-01-01T00:00:00Z", "won": "0"],
        ]
        let films = WikidataLists.films(from: rows, list: .oscarDirector)
        XCTAssertEqual(films.map { $0.title }, ["Oppenheimer", "Anatomy of a Fall", "Poor Things"])
        XCTAssertEqual(films.map { $0.won }, [true, false, false])
        XCTAssertEqual(films.first?.note, "Won 2024 · Christopher Nolan")
        XCTAssertEqual(films[1].note, "Nominated 2024 · Justine Triet")
        XCTAssertEqual(films.first?.rank, "2024")
        XCTAssertTrue(AwardList.oscarDirector.query.contains("pq:P1686"))

        let poll = SightAndSound.films
        XCTAssertEqual(poll.count, 100)
        XCTAssertEqual(poll.first?.rank, "1")
        XCTAssertEqual(Set(poll.map { $0.id }).count, 100, "every film has its own key")
    }

    // MARK: Sets

    func testPersonSetKeepsReleasedFeatureFilms() throws {
        let json = """
        {"id": 137427, "name": "Denis Villeneuve", "profile_path": "/v.jpg", "movie_credits": {"cast": [], "crew": [
          {"id": 335984, "title": "Blade Runner 2049", "release_date": "2017-10-04", "job": "Director", "vote_count": 14000},
          {"id": 335984, "title": "Blade Runner 2049", "release_date": "2017-10-04", "job": "Director", "vote_count": 14000},
          {"id": 27205, "title": "Incendies", "release_date": "2010-09-17", "job": "Director", "vote_count": 2500},
          {"id": 1, "title": "Next Floor", "release_date": "2008-05-01", "job": "Director", "vote_count": 12},
          {"id": 2, "title": "Rendezvous with Rama", "release_date": "2030-01-01", "job": "Director", "vote_count": 0},
          {"id": 3, "title": "Some Film", "release_date": "2005-01-01", "job": "Producer", "vote_count": 900},
          {"id": 4, "title": "Owned Rarity", "release_date": "1998-01-01", "job": "Director", "vote_count": 3}
        ]}}
        """
        let person = try JSONDecoder().decode(TMDBPerson.self, from: Data(json.utf8))
        let set = FilmSets.person(person, kind: .director, now: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(set.films(owned: [4]).map { $0.title }, ["Owned Rarity", "Incendies", "Blade Runner 2049"])
        XCTAssertEqual(set.films(owned: []).map { $0.title }, ["Incendies", "Blade Runner 2049"])
        XCTAssertEqual(set.id, "director:137427")

        let collection = TMDBCollection(id: 422837, name: "Blade Runner Collection", parts: [
            TMDBMovieSummary(id: 335984, title: "Blade Runner 2049", releaseDate: "2017-10-04"),
            TMDBMovieSummary(id: 78, title: "Blade Runner", releaseDate: "1982-06-25"),
            TMDBMovieSummary(id: 9, title: "Blade Runner 2099", releaseDate: ""),
        ])
        XCTAssertEqual(FilmSets.collection(collection).films.map { $0.title }, ["Blade Runner", "Blade Runner 2049"])
    }

    func testSetCandidatesComeFromOwnedFilms() {
        let villeneuve = TMDBCrewMember(id: 137427, name: "Denis Villeneuve", job: "Director")
        let deakins = TMDBCrewMember(id: 151, name: "Roger Deakins", job: "Director of Photography")
        let fraser = TMDBCrewMember(id: 2, name: "Greig Fraser", job: "Director of Photography")
        let bladeRunner = TMDBCollectionRef(id: 422837, name: "Blade Runner Collection")
        let owned: [(collection: TMDBCollectionRef?, crew: [TMDBCrewMember])] = [
            (bladeRunner, [villeneuve, deakins]),
            (nil, [villeneuve, deakins]),
            (nil, [villeneuve, villeneuve, fraser]),
        ]
        let found = FilmSets.candidates(owned)
        XCTAssertEqual(found.map { "\($0.kind.rawValue) \($0.name) \($0.owned)" },
                       ["director Denis Villeneuve 3", "cinematographer Roger Deakins 2", "franchise Blade Runner Collection 1"])
    }

    func testTheSameFilmAcrossListsCountsOnce() {
        let palme = [
            ListFilm(imdbID: "tt6751668", tmdbID: 496243, title: "Parasite", year: 2019, note: "Won 2019", won: true),
            ListFilm(imdbID: "tt0000001", tmdbID: 1, title: "Nominee", year: 2019, note: "Nominated 2019", won: false),
        ]
        let top250 = [ListFilm(imdbID: "tt6751668", tmdbID: nil, title: "Parasite", year: 2019, note: "8.5")]
        // Title and year only (Sight and Sound), resolved to the same TMDB id.
        let poll = [ListFilm(imdbID: nil, tmdbID: nil, title: "Parasite", year: 2019, note: nil),
                    ListFilm(imdbID: nil, tmdbID: nil, title: "Jeanne Dielman", year: 1975, note: nil)]
        let picks = ListConsensus.gather([(.award(.palmeDOr), palme), (.imdbAllTime, top250), (.sightAndSound, poll)],
                                         tmdbIDOf: { $0.title == "Jeanne Dielman" ? 44012 : nil })
        XCTAssertEqual(picks.map(\.film.title), ["Parasite", "Jeanne Dielman"], "nominees don't count; one film each")
        XCTAssertEqual(picks.first?.lists, [.sightAndSound, .award(.palmeDOr), .imdbAllTime])
        XCTAssertEqual(picks.first?.tmdbID, 496243)
        XCTAssertEqual(picks.first?.weight ?? 0, 3.9, accuracy: 0.001)
        XCTAssertEqual(picks.last?.tmdbID, 44012)
        XCTAssertEqual(ListConsensus.summary(picks[0].lists), "Sight & Sound · Palme d'Or · +1")
    }
}
