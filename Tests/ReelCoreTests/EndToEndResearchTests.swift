import XCTest
@testable import ReelCore

/// 1.10.9, end to end with controlled source responses: search → candidate → fetch → identity →
/// extraction → context → claim interpretation → evidence → reconciliation → persistence → log, for
/// one film and for a synthetic library of 150 films (270 copies) processed autonomously, saved to
/// disk and reopened midway.
final class EndToEndResearchTests: XCTestCase {
    /// The corpus as a web, with pages that fail on purpose.
    final class Web: ResearchTransport, @unchecked Sendable {
        let corpus: BenchCorpus
        let down: Set<String>
        private let lock = NSLock()
        private var _searched = 0, _fetched: [String] = []
        init(_ corpus: BenchCorpus, down: Set<String> = []) { self.corpus = corpus; self.down = down }
        var searched: Int { lock.lock(); defer { lock.unlock() }; return _searched }
        var fetched: [String] { lock.lock(); defer { lock.unlock() }; return _fetched }

        func researchSearch(_ provider: ResearchProvider, query: String, noting: UnansweredSites) async -> (hits: [(title: String, url: String)], failure: String?) {
            lock.lock(); _searched += 1; lock.unlock()
            guard let answer = corpus.search(provider.name, query) else { return ([], nil) }
            return (answer.hits, answer.failure)
        }

        func researchPage(_ url: URL, site: String, title: String?, noting: UnansweredSites) async -> (source: CameraReading.Source?, failure: SourceFailure?) {
            lock.lock(); _fetched.append(url.absoluteString); lock.unlock()
            if down.contains(url.absoluteString) {
                await noting.add(site)
                return (nil, .unanswered("timed out"))
            }
            guard let page = corpus.pages[url.absoluteString] else { return (nil, .gone("not found over HTTPS (404)")) }
            if let failure = page.failure { return (nil, failure) }
            return (CameraReading.Source(title: page.title, site: page.site, url: url, paragraphs: page.paragraphs), nil)
        }
    }

    /// One film read through the production path, reconciled with what was stored, merged and logged.
    static func read(_ film: BenchFilm, corpus: BenchCorpus, web: Web, stored: CraftIndex?, now: Date) async -> (CraftIndex, String) {
        let details = ResearchBenchmarkTests.details(film), article = ResearchBenchmarkTests.article(film)
        let people = details.cinematographers + details.directors
        let first = film.firstPass.compactMap { url -> CameraReading.Source? in
            guard let page = corpus.pages[url], page.failure == nil, !web.down.contains(url), let address = URL(string: url) else { return nil }
            return CameraSources.judged(CameraReading.Source(title: page.title, site: page.site, url: address, paragraphs: page.paragraphs),
                                        filmTitle: film.title, otherTitles: [], people: people, year: film.year)
        }
        let downSites = film.firstPass.filter(web.down.contains).compactMap { corpus.pages[$0]?.site }
        let base = CameraReading(sources: first, more: [], cinematographer: nil, unanswered: Array(Set(downSites)).sorted())
        let crew = CraftReader.crew(of: details, article: article, reading: base)
        let researched = await ResearchEngine.run(base, article: article, filmTitle: film.title, cinematographers: details.cinematographers,
                                                  directors: details.directors, year: film.year, otherTitles: [], crew: crew,
                                                  previous: stored, transport: web, now: now)
        let reading = CraftReader.reading(of: details, articleTitle: film.title, article: article, reading: researched, colour: nil,
                                          previous: stored, now: now)
        let merged = CraftIndex.merging(old: stored, new: reading.index, now: now)
        return (merged.index, reading.log + CraftLog.stored(merged))
    }

    // MARK: One film

    func testOneFilmThroughEveryOutcome() async throws {
        let corpus = DevelopmentCorpus.corpus()
        let film = try XCTUnwrap(corpus.films.first { !$0.firstPass.isEmpty })
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        // Read once: every source answers.
        let web = Web(corpus)
        let (first, log) = await Self.read(film, corpus: corpus, web: web, stored: nil, now: t0)
        XCTAssertFalse(first.claimsKnown.isEmpty)
        XCTAssertTrue(first.claimsKnown.allSatisfy { $0.status == .confirmed })
        XCTAssertTrue(log.contains("STORED IN REEL"))
        XCTAssertEqual(web.fetched.count, Set(web.fetched).count, "no page asked for twice")
        XCTAssertLessThanOrEqual(web.searched, ResearchPlan.maxQueries)
        // Read again with its first page down (a timeout): what that page gave is carried, not lost.
        let down = Set(film.firstPass.prefix(1))
        let (second, secondLog) = await Self.read(film, corpus: corpus, web: Web(corpus, down: down), stored: first, now: t0.addingTimeInterval(86_400))
        let site = corpus.pages[film.firstPass[0]]?.site ?? ""
        for claim in first.claimsKnown where claim.site == site {
            let now = second.claimsKnown.first { $0.name == claim.name && $0.source == claim.source }
            XCTAssertNotNil(now, "\(claim.name) from \(site) kept")
            XCTAssertTrue(now?.supports ?? false, "\(claim.name): \(String(describing: now?.status))")
        }
        XCTAssertNotNil(second.retryAt, "tried again later")
        XCTAssertTrue(secondLog.contains("carried") || second.claimsKnown.contains { $0.status == .carried } || first.claimsKnown.allSatisfy { $0.site != site })
        // Retry after the failure, with the page back: confirmed again, nothing carried.
        let (third, _) = await Self.read(film, corpus: corpus, web: Web(corpus), stored: second, now: t0.addingTimeInterval(8 * 86_400))
        XCTAssertFalse(third.claimsKnown.contains { $0.status == .carried })
        XCTAssertEqual(Set(third.shotOn), Set(first.shotOn), "the same tags as the first full reading")
    }

    // MARK: A library

    func testASyntheticLibraryIsResearchedAutonomouslyAndSurvivesARelaunch() async throws {
        let corpus = DevelopmentCorpus.corpus()
        XCTAssertEqual(corpus.films.count, 150)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var films: [FilmEntry] = []
        for (index, film) in corpus.films.enumerated() {
            for drive in index < 120 ? ["Main", "Backup"] : ["Main"] {
                var entry = FilmEntry(driveID: drive, relativePath: "Films/\(film.id).mkv", fileName: "\(film.id).mkv", size: Int64(film.id),
                                      modified: nil, addedAt: start, matchState: .auto, tmdb: ResearchBenchmarkTests.details(film))
                entry.funFacts = FunFacts(facts: [], articleTitle: film.title, fetchedAt: start)
                films.append(entry)
            }
        }
        XCTAssertEqual(films.count, 270)
        // One site's pages time out throughout: those films are still read, the rest aren't blocked.
        let downSite = "British Cinematographer"
        let down = Set(corpus.pages.values.filter { $0.site == downSite }.map(\.url))
        let web = Web(corpus, down: down)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("reel-e2e-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Library.json")
        var run = CraftRun()
        var processed: [Int] = []
        var searchesPerFilm: [Int: Int] = [:]
        var batches = 0
        let now = start.addingTimeInterval(60)
        while true {
            let batch = run.nextBatch(films, now: now)
            if batch.isEmpty { break }
            for entry in batch {
                guard let id = entry.tmdb?.id, let film = corpus.films.first(where: { $0.id == id }) else { continue }
                let before = web.searched
                let (index, _) = await Self.read(film, corpus: corpus, web: web, stored: entry.craft, now: now)
                searchesPerFilm[id] = web.searched - before
                for i in films.indices where films[i].tmdb?.id == id { films[i].craft = index }
                processed.append(id)
            }
            batches += 1
            try JSONStore.save(LibraryFile(films: films), to: file)
            // Relaunch midway: the library is read back from disk and a new run starts from it.
            if batches == 30 {
                guard case .loaded(let reopened) = LibraryOpening.open(file) else { return XCTFail("the saved library opens") }
                XCTAssertEqual(reopened.films.count, 270)
                XCTAssertEqual(reopened.version, LibraryFile.currentVersion)
                films = reopened.films
                run = CraftRun()
            }
        }
        XCTAssertEqual(processed.count, 150, "each film once")
        XCTAssertEqual(Set(processed).count, 150, "no duplicate jobs, across the relaunch")
        XCTAssertLessThanOrEqual(searchesPerFilm.values.max() ?? 0, ResearchPlan.maxQueries, "requests stay bounded")
        XCTAssertTrue(films.allSatisfy { $0.craft?.version == CraftIndex.currentVersion && $0.craft?.discovery == CraftIndex.currentDiscovery })
        // A film whose only source was the site that's down is partial, tried again later; the others aren't held up.
        XCTAssertGreaterThan(films.filter { $0.craft?.unanswered.contains(downSite) ?? false }.count, 0)
        XCTAssertGreaterThan(films.filter { $0.craft?.unanswered.isEmpty ?? false }.count, 100)
        // Partial findings leave their questions open.
        for film in films {
            for entry in film.craft?.research ?? [] where entry.state == .partial {
                XCTAssertFalse(entry.open.isEmpty, "\(entry.dimension): a partial finding names what's still open")
            }
        }
        // Read again a day later: nothing is due but the films a site didn't answer for (no needless repeats).
        var again = CraftRun()
        let later = now.addingTimeInterval(86_400)
        let due = Set(again.nextBatch(films, now: later).compactMap { $0.tmdb?.id })
        let waiting = Set(films.filter { $0.craft?.retryAt.map { $0 <= later } ?? false }.compactMap { $0.tmdb?.id })
        XCTAssertTrue(due.isSubset(of: waiting), "only what's planned to be read again")
        // Valid old evidence isn't silently destroyed: with the site back, nothing that site supported is lost.
        let recovered = Web(corpus)
        var lost: [String] = []
        for entry in films where !(entry.craft?.unanswered.isEmpty ?? true) {
            guard let id = entry.tmdb?.id, let film = corpus.films.first(where: { $0.id == id }), let stored = entry.craft else { continue }
            let (index, _) = await Self.read(film, corpus: corpus, web: recovered, stored: stored, now: later.addingTimeInterval(7 * 86_400))
            for claim in stored.claimsKnown where claim.supports {
                let now = index.claimsKnown.first { $0.kind == claim.kind && SourceReconciliation.sameName($0.name, claim.name) }
                if now == nil { lost.append("\(film.title): \(claim.name)") }
            }
        }
        XCTAssertTrue(lost.isEmpty, "\(lost.prefix(10))")
    }
}
