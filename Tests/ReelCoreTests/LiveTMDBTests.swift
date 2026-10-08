import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ReelCore

/// Talks to the real TMDB. Runs only when TMDB_TOKEN is set (in CI it comes from the repo secret).
final class LiveTMDBTests: XCTestCase {
    func testSampleFilmsMatchAutomatically() async throws {
        guard let token = ProcessInfo.processInfo.environment["TMDB_TOKEN"], !token.isEmpty else {
            throw XCTSkip("TMDB_TOKEN not set")
        }
        let client = TMDBClient(token: token)
        let matcher = FilmMatcher(database: client)

        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/reel-files-sample.txt")
        let text = try String(contentsOf: url, encoding: .utf8)

        for line in text.split(separator: "\n") {
            guard let space = line.firstIndex(of: " ") else { continue }
            let parsed = FilenameParser.parse(String(line[line.index(after: space)...]))
            let result = try await matcher.match(title: parsed.title, year: parsed.year)
            let best = try XCTUnwrap(result.best, parsed.title)
            print("::notice::\(parsed.title) (\(parsed.year ?? 0)) → TMDB \(best.movie.id) \(best.movie.title) (\(best.movie.year ?? 0)), score \(String(format: "%.2f", best.score)), \(result.confidence.rawValue)")
            XCTAssertEqual(result.confidence, .auto, parsed.title)
            XCTAssertEqual(best.movie.year, parsed.year, parsed.title)
        }

        let full = try await client.movieDetails(id: 335984)
        let details = full.trimmed()
        XCTAssertEqual(details.title, "Blade Runner 2049")
        XCTAssertNotNil(details.runtime)
        XCTAssertFalse(details.genreNames.isEmpty)
        XCTAssertFalse(details.cinematographers.isEmpty)
        XCTAssertFalse(details.stillPaths.isEmpty)
        XCTAssertFalse(details.keywordNames.isEmpty)
        let reviews = (full.reviews?.results ?? []).map { ReviewText(text: $0.content, rating: $0.authorDetails?.rating) }
        let reception = ReceptionAnalyzer.summarize(reviews, sentiment: { _ in 0 })
        let moods = MoodClassifier.moods(genres: details.genreNames, keywords: details.keywordNames, runtime: details.runtime)
        print("::notice::Details OK: \(details.title), \(details.runtime ?? 0) min, DP: \(details.cinematographers.joined(separator: ", ")), stills: \(details.stillPaths.count), logo: \(details.logoPath != nil ? "yes" : "no"), collection: \(details.collection?.name ?? "none"), reviews: \(reviews.count), moods: \(moods.map { $0.title }.joined(separator: ", "))")
        XCTAssertNotNil(reception)
    }

    func testPersonAndFunFacts() async throws {
        guard let token = ProcessInfo.processInfo.environment["TMDB_TOKEN"], !token.isEmpty else {
            throw XCTSkip("TMDB_TOKEN not set")
        }
        let person = try await TMDBClient(token: token).person(id: 151)
        let films = Filmography.build(person)
        XCTAssertTrue(films.contains { $0.id == 335984 })
        print("::notice::Person OK: \(person.name), \(films.count) films, departments: \(Filmography.departments(in: films).joined(separator: ", "))")

        let findings = try await WikipediaClient().findings(imdbID: "tt1856101", title: "Blade Runner 2049", year: 2017)
        let facts = findings.funFacts
        XCTAssertEqual(facts.articleTitle, "Blade Runner 2049")
        XCTAssertFalse(facts.facts.isEmpty)
        let quick = try XCTUnwrap(facts.quick)
        print("::notice::Fun facts OK: \(facts.facts.count) facts; highlight: \(facts.highlight?.prefix(100) ?? "-")")
        print("::notice::Quick facts: based on \(quick.basedOn), filmed in \(quick.filmedIn), set in \(quick.setIn), awards \(quick.awardsWon) won / \(quick.nominations) nominated, notable \(quick.notableAwards.prefix(2)), follows \(quick.follows ?? "-")")
        print("::notice::Critics: consensus \(facts.consensus?.prefix(80) ?? "-"), CinemaScore \(facts.cinemaScore ?? "-"), \(findings.criticSentences.count) critic sentences")
        XCTAssertFalse(findings.criticSentences.isEmpty)
    }

    func testExploreLists() async throws {
        guard let token = ProcessInfo.processInfo.environment["TMDB_TOKEN"], !token.isEmpty else {
            throw XCTSkip("TMDB_TOKEN not set")
        }
        let client = TMDBClient(token: token)
        var counts: [String] = []
        for list in [DiscoverList.inCinemas, .trending, .newAtHome, .bestOf(year: 1999), .mood(.feelGood), .mood(.epic)] {
            let r = list.request()
            let films = try await client.movies(r.path, r.query, pages: r.pages)
            XCTAssertFalse(films.isEmpty, list.title)
            counts.append("\(list.title) \(films.count)")
        }
        print("::notice::Explore: \(counts.joined(separator: ", "))")
        let recs = try await client.movies("/movie/335984/recommendations")
        let similar = try await client.movies("/movie/335984/similar")
        let ranked = SimilarFilms.rank(recommendations: recs, similar: similar, genres: ["Science Fiction", "Drama"], excluding: 335984)
        XCTAssertFalse(ranked.isEmpty)
        print("::notice::More like Blade Runner 2049: \(ranked.prefix(4).map { "\($0.movie.title) \($0.match)%" }.joined(separator: ", "))")
    }

    func testOMDbRatings() async throws {
        guard let key = ProcessInfo.processInfo.environment["OMDB_KEY"], !key.isEmpty else {
            throw XCTSkip("OMDB_KEY not set")
        }
        let ratings = try await OMDbClient(key: key).ratings(imdbID: "tt1856101")
        let r = try XCTUnwrap(ratings)
        XCTAssertNotNil(r.imdb)
        print("::notice::OMDb OK: IMDb \(r.imdb ?? 0), RT \(r.rottenTomatoes ?? 0)%, Metacritic \(r.metacritic ?? 0), \(r.rated ?? "-")")
    }

    func testAwardLists() async throws {
        guard let token = ProcessInfo.processInfo.environment["TMDB_TOKEN"], !token.isEmpty else {
            throw XCTSkip("TMDB_TOKEN not set")
        }
        var empty: [String] = []
        var summary: [String] = []
        for list in AwardList.allCases {
            let films = (try? await WikidataLists().films(list)) ?? []
            if films.isEmpty { empty.append(list.title) }
            let winners = films.filter { $0.isWinner }
            summary.append("\(list.title) \(winners.count)+\(films.count - winners.count) (\(winners.first?.note ?? "-"))")
        }
        print("::notice::Award lists: \(summary.joined(separator: "; "))")
        if !empty.isEmpty { print("::warning::Empty lists: \(empty.joined(separator: ", "))") }
        XCTAssertTrue(empty.isEmpty, "Lists with nothing: \(empty)")

        let client = TMDBClient(token: token)
        let found = try await client.find(imdbID: "tt0137523")
        XCTAssertEqual(found?.id, 550)
        let collection = try await client.collection(id: 422837)
        let person = try await client.person(id: 137427)
        let set = FilmSets.person(person, kind: .director)
        let counted = set.films(owned: [])
        print("::notice::Sets: \(collection.name) \(FilmSets.collection(collection).films.map { $0.title }); \(set.name) \(counted.count) films: \(counted.map { $0.title }.joined(separator: ", "))")
    }

    /// Downloads IMDb's free files (about 200 MB) and builds the compact copy, as the app does.
    func testIMDbDataset() async throws {
        guard ProcessInfo.processInfo.environment["TMDB_TOKEN"] != nil else { throw XCTSkip("live tests only") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reel-imdb-live")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ratings = dir.appendingPathComponent("ratings.tsv.gz")
        let basics = dir.appendingPathComponent("basics.tsv.gz")
        let started = Date()
        try await download(IMDbDataset.ratingsURL, to: ratings)
        try await download(IMDbDataset.basicsURL, to: basics)
        let downloaded = Date()
        let films = try IMDbDataset.build(ratingsFile: ratings, basicsFile: basics)
        let built = Date()
        let size = try JSONStore.encode(IMDbRatingsFile(builtAt: built, films: films)).count
        print("::notice::IMDb: \(films.count) films kept, saved copy \(size / 1_000_000) MB; download \(Int(downloaded.timeIntervalSince(started)))s, build \(Int(built.timeIntervalSince(downloaded)))s (debug build)")
        let top1999 = IMDbDataset.top(films, year: 1999, count: 100)
        print("::notice::IMDb Top 100 of 1999 (\(top1999.count)): \(top1999.prefix(8).map { $0.title }.joined(separator: ", "))")
        let top1960 = IMDbDataset.top(films, year: 1960, count: 100)
        let allTime = IMDbDataset.topAllTime(films, count: 250)
        print("::notice::IMDb 1960 (\(top1960.count)): \(top1960.prefix(5).map { $0.title }.joined(separator: ", ")); all time: \(allTime.prefix(6).map { $0.title }.joined(separator: ", "))")
        XCTAssertGreaterThan(films.count, 20_000)
        XCTAssertEqual(top1999.count, 100)
    }

    private func download(_ url: URL, to file: URL) async throws {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: url) { data, _, error in
                if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: error ?? URLError(.badServerResponse)) }
            }.resume()
        }
        try data.write(to: file)
    }

    /// The award lists Reel added most recently come back from Wikidata with their winners.
    func testNewAwardListsLoadFromWikidata() async throws {
        guard let token = ProcessInfo.processInfo.environment["TMDB_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Live tests run in CI only")
        }
        for list in [AwardList.oscarAnimated, .goldenLeopard] {
            let films = try await WikidataLists().films(list)
            let winners = films.filter(\.isWinner)
            print("::notice::\(list.title): \(winners.count) winners, \(films.count) films, e.g. \(winners.prefix(3).map(\.title))")
            XCTAssertGreaterThan(winners.count, 5, list.title)
        }
    }
}
