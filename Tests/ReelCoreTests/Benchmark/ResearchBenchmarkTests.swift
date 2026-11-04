import XCTest
@testable import ReelCore

/// The research benchmark (1.10.8): every synthetic film of a corpus through the production engine
/// (`ResearchEngine.run` with an in-memory transport, `CraftReader.reading`, `TechSpecs.read`),
/// measured against the corpus's labels. Printed as "BENCH|" lines (CI shows them) and asserted where
/// the brief requires zero: cross-film contamination, untraceable findings, budgets, duplicate or
/// repeated searches, dishonest coverage. The baseline is the same pages read the 1.10.7 way: every
/// page whose text names the film read whole, with no page context and no claim anchoring.
final class ResearchBenchmarkTests: XCTestCase {
    /// The corpus as a provider and a web: what's searched and asked for is recorded.
    final class Transport: ResearchTransport, @unchecked Sendable {
        let corpus: BenchCorpus
        private let lock = NSLock()
        private(set) var searched: [(provider: String, query: String)] = []
        private(set) var fetched: [String] = []
        init(_ corpus: BenchCorpus) { self.corpus = corpus }

        func researchSearch(_ provider: ResearchProvider, query: String, noting: UnansweredSites) async
            -> (hits: [(title: String, url: String)], failure: String?) {
            lock.lock(); searched.append((provider.name, query)); lock.unlock()
            guard let answer = corpus.search(provider.name, query) else { return ([], nil) }
            return (answer.hits, answer.failure)
        }

        func researchPage(_ url: URL, site: String, title: String?, noting: UnansweredSites) async
            -> (source: CameraReading.Source?, failure: SourceFailure?) {
            lock.lock(); fetched.append(url.absoluteString); lock.unlock()
            guard let page = corpus.pages[url.absoluteString] else { return (nil, .gone("not found over HTTPS (404)")) }
            if let failure = page.failure { return (nil, failure) }
            return (CameraReading.Source(title: page.title, site: page.site, url: url, paragraphs: page.paragraphs), nil)
        }
    }

    struct Metrics: CustomStringConvertible {
        var films = 0, accepted = 0, contaminated = 0, unattributed = 0, untraceable = 0
        var expectedGear = 0, foundGear = 0
        var searches = 0, maxSearches = 0, researchPages = 0, maxResearchPages = 0, maxRead = 0, budgetViolations = 0
        var duplicateSearches = 0, duplicateReads = 0, dishonest = 0, vfxMisplanned = 0, repeatedQuiet = 0
        var pagesFetched = 0, pagesRead = 0, pagesPassed = 0, pagesUseful = 0
        var states: [String: Int] = [:]
        var examples: [String] = []

        var description: String {
            "films \(films); accepted claims \(accepted); contaminated \(contaminated); unattributed (about no film) \(unattributed); "
                + "untraceable \(untraceable); gear recall \(foundGear)/\(expectedGear); searches \(searches) (max \(maxSearches)/film); "
                + "research pages fetched \(pagesFetched), read \(pagesRead) (useful \(pagesUseful)), set aside by context \(pagesPassed); "
                + "max research pages/film \(maxResearchPages); max read/film \(maxRead); budget violations \(budgetViolations); "
                + "duplicate searches \(duplicateSearches); duplicate reads \(duplicateReads); dishonest coverage \(dishonest); "
                + "VFX searched without VFX \(vfxMisplanned); quiet searches repeated \(repeatedQuiet); states \(states.sorted { $0.key < $1.key })"
        }
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func details(_ film: BenchFilm) -> TMDBMovieDetails {
        var details = TMDBMovieDetails(id: film.id, title: film.title, releaseDate: "\(film.year)-06-01")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: film.director, job: "Director")]
                                      + film.crew.map { TMDBCrewMember(name: $0.name, job: $0.job) })
        return details
    }

    static func article(_ film: BenchFilm) -> FilmArticle? {
        film.article.isEmpty ? nil : FilmArticle(title: film.title, extract: "== Production ==\n" + film.article.joined(separator: "\n"))
    }

    /// Every film of `corpus` through the engine. `baseline`: the pages read the 1.10.7 way.
    static func measure(_ corpus: BenchCorpus, baseline: Bool = false) async -> Metrics {
        var m = Metrics()
        let claims = corpus.claims
        for film in corpus.films {
            m.films += 1
            let transport = Transport(corpus)
            let details = details(film), article = article(film)
            let people = details.cinematographers + details.directors
            var first = film.firstPass.compactMap { url -> CameraReading.Source? in
                guard let page = corpus.pages[url], page.failure == nil, let address = URL(string: url) else { return nil }
                return CameraReading.Source(title: page.title, site: page.site, url: address, paragraphs: page.paragraphs)
            }
            if !baseline { first = first.map { CameraSources.judged($0, filmTitle: film.title, otherTitles: [], people: people) } }
            let base = CameraReading(sources: first, more: [], cinematographer: nil)
            let crew = CraftReader.crew(of: details, article: article, reading: base)
            var researched = await ResearchEngine.run(base, article: article, filmTitle: film.title, cinematographers: details.cinematographers,
                                                      directors: details.directors, year: film.year, otherTitles: [], crew: crew,
                                                      previous: nil, transport: transport, now: now)
            if baseline {
                // 1.10.7: a fetched page naming the film (anywhere in its text) was read whole.
                var sources = researched.sources.map { source -> CameraReading.Source in var s = source; s.context = nil; return s }
                for url in transport.fetched where !sources.contains(where: { $0.url.absoluteString == url }) && sources.count < CameraSources.readLimit {
                    guard let page = corpus.pages[url], page.failure == nil, page.paragraphs.count >= 3,
                          CameraSources.fold(page.paragraphs.joined(separator: " ")).contains(CameraSources.fold(film.title)) else { continue }
                    sources.append(CameraReading.Source(title: page.title, site: page.site, url: URL(string: url)!, paragraphs: page.paragraphs))
                }
                var replaced = CameraReading(sources: sources, more: [], cinematographer: nil, unanswered: researched.unanswered, skipped: researched.skipped)
                replaced.research = researched.research
                researched = replaced
            }
            let reading = CraftReader.reading(of: details, articleTitle: film.title, article: article, reading: researched, colour: nil, now: now)
            let texts = CraftReader.texts(article: article, reading: researched, hiding: false)
            let specs = TechSpecs.read(texts: texts, cinematographers: details.cinematographers, directors: details.directors,
                                       year: film.year, title: film.title, otherTitles: [], crew: crew)
            // What was accepted: the sheet's gear and every observation.
            let notes = specs.approach + specs.intent + specs.references + specs.scenes + specs.challenges + specs.lighting
                + specs.colour + specs.cameraLanguage + specs.cameraVFX + specs.sentences
            var items: [(text: String, gear: String?)] = specs.specs.map { spec -> (text: String, gear: String?) in (text: spec.evidence, gear: spec.name) }
            items += notes.map { note -> (text: String, gear: String?) in (text: note.text, gear: nil) }
            let readText = texts.flatMap { $0.sections.flatMap(\.paragraphs) }.joined(separator: "\n")
            for item in items {
                m.accepted += 1
                let owners = claims.filter { item.text.contains($0.claim.text) || $0.claim.text.contains(item.text) }.map(\.claim.film)
                if owners.contains(where: { !$0.isEmpty && $0 != film.title }) {
                    m.contaminated += 1
                    if m.examples.count < 6 { m.examples.append("\(film.title) ← “\(item.text.prefix(110))”" + (item.gear.map { " [\($0)]" } ?? "")) }
                } else if item.gear != nil, owners.contains(""), !owners.contains(film.title) {
                    m.unattributed += 1
                    if m.examples.count < 6 { m.examples.append("\(film.title) ← (about no film) “\(item.text.prefix(100))” [\(item.gear!)]") }
                }
                if item.gear != nil, !readText.contains(item.text.prefix(60)) { m.untraceable += 1 }
            }
            // Recall: gear its reachable claims establish for it.
            let reachable = Set(film.firstPass + corpus.searches.filter { s in film.crew.contains { $0.name == s.query } || s.query == film.title }
                .flatMap { $0.hits.map(\.url) })
            let expected = Set(claims.filter { $0.claim.film == film.title && (reachable.contains($0.page) || $0.page == "wikipedia:" + film.title) }
                .flatMap(\.claim.gear))
            m.expectedGear += expected.count
            let names = specs.specs.map { $0.name.lowercased() }
            m.foundGear += expected.filter { gear in names.contains { $0.contains(gear.lowercased()) || gear.lowercased().contains($0) } }.count
            // Budgets and duplication.
            let run = researched.research
            let outcomes = run?.outcomes ?? []
            let made = outcomes.filter { if case .notTried = $0.result { return false } else { return true } }
            m.searches += made.count
            m.maxSearches = max(m.maxSearches, made.count)
            let keys = made.map(\.query.key)
            m.duplicateSearches += keys.count - Set(keys).count
            m.duplicateReads += transport.fetched.count - Set(transport.fetched).count
            let added = researched.sources.count - base.sources.count
            m.researchPages += added
            m.maxResearchPages = max(m.maxResearchPages, transport.fetched.count)
            m.maxRead = max(m.maxRead, researched.sources.count)
            if made.count > ResearchPlan.maxQueries || transport.fetched.count > ResearchPlan.maxPages || researched.sources.count > CameraSources.readLimit
                || base.sources.count + transport.fetched.count > CameraSources.askLimit { m.budgetViolations += 1 }
            m.pagesFetched += transport.fetched.count
            m.pagesRead += max(0, added)
            m.pagesPassed += run?.passed.count ?? 0
            for source in researched.sources.dropFirst(base.sources.count) {
                let owned = claims.filter { $0.page == source.url.absoluteString && $0.claim.film == film.title }
                if !owned.isEmpty { m.pagesUseful += 1 }
            }
            // Coverage honesty: a dimension whose only searches failed isn't "nothing found".
            for entry in reading.index.research ?? [] {
                m.states[entry.state.rawValue, default: 0] += 1
                let mine = outcomes.filter { $0.query.covers(entry.dimension) }
                let failed = !mine.isEmpty && mine.allSatisfy {
                    if case .unavailable = $0.result { return true }
                    if case .pageUnavailable = $0.result { return true }
                    return false
                }
                if failed, [.searchedNoSource, .readNoFindings, .notSearched].contains(entry.state) { m.dishonest += 1 }
            }
            // Planning: no VFX searches for a film without effects.
            let context = ResearchContext(crew: crew, specs: TechSpecs.read(texts: CraftReader.texts(article: article, reading: base, hiding: false),
                                                                            cinematographers: details.cinematographers, directors: details.directors,
                                                                            year: film.year, title: film.title, crew: crew),
                                          texts: CraftReader.texts(article: article, reading: base, hiding: false))
            if !context.vfxRelevant, made.contains(where: { $0.query.covers(.vfx) && $0.query.site == "Cinesite" }) { m.vfxMisplanned += 1 }
            // Read again a day later with what was stored: a search that found nothing isn't repeated.
            if !baseline {
                let stored = CraftIndex.merging(old: nil, new: reading.index, now: now).index
                let again = Transport(corpus)
                _ = await ResearchEngine.run(base, article: article, filmTitle: film.title, cinematographers: details.cinematographers,
                                             directors: details.directors, year: film.year, otherTitles: [], crew: crew,
                                             previous: stored, transport: again, now: now.addingTimeInterval(86_400))
                let quiet = Set(ResearchPlan.quiet(stored.research, discovery: CraftIndex.currentDiscovery, readAt: stored.readAt,
                                                   now: now.addingTimeInterval(86_400)).flatMap(\.queries))
                m.repeatedQuiet += again.searched.filter { quiet.contains($0.provider + "|" + $0.query.lowercased()) }.count
            }
        }
        return m
    }

    func say(_ line: String) { FileHandle.standardOutput.write(Data(("BENCH| " + line + "\n").utf8)) }

    func check(_ m: Metrics, _ name: String) {
        XCTAssertEqual(m.contaminated, 0, "\(name): cross-film contamination: \(m.examples)")
        XCTAssertEqual(m.unattributed, 0, "\(name): gear from statements about no film: \(m.examples)")
        XCTAssertEqual(m.untraceable, 0, "\(name): findings without a read passage")
        XCTAssertEqual(m.budgetViolations, 0, "\(name): budgets")
        XCTAssertEqual(m.duplicateSearches, 0, "\(name): duplicate searches")
        XCTAssertEqual(m.duplicateReads, 0, "\(name): duplicate reads")
        XCTAssertEqual(m.dishonest, 0, "\(name): coverage said nothing found where the search failed")
        XCTAssertEqual(m.vfxMisplanned, 0, "\(name): VFX searched for a film without effects")
        XCTAssertEqual(m.repeatedQuiet, 0, "\(name): a quiet search repeated")
    }

    func testTheDevelopmentCorpus() async {
        let corpus = DevelopmentCorpus.corpus()
        XCTAssertEqual(corpus.films.count, 150)
        let now = await Self.measure(corpus)
        let before = await Self.measure(corpus, baseline: true)
        say("development, 1.10.8: \(now)")
        say("development, 1.10.7 way (baseline): \(before)")
        if !now.examples.isEmpty { say("development examples: \(now.examples.joined(separator: " ¦ "))") }
        if !before.examples.isEmpty { say("baseline examples: \(before.examples.joined(separator: " ¦ "))") }
        check(now, "development")
    }

    func testTheBlindHoldout() async {
        let corpus = HoldoutCorpus.corpus()
        let now = await Self.measure(corpus)
        let before = await Self.measure(corpus, baseline: true)
        say("holdout, 1.10.8: \(now)")
        say("holdout, 1.10.7 way (baseline): \(before)")
        if !now.examples.isEmpty { say("holdout examples: \(now.examples.joined(separator: " ¦ "))") }
        check(now, "holdout")
    }

    /// 150 films, 120 of them on two drives (270 copies): each film due once by the new rules,
    /// whatever its copies, and none read twice in a pass.
    func testTheSyntheticLibraryIsQueuedOncePerFilm() {
        let start = Self.now
        var all: [FilmEntry] = []
        for id in 1...150 {
            for drive in id <= 120 ? ["Main", "Backup"] : ["Main"] {
                var entry = FilmEntry(driveID: drive, relativePath: "Film \(id).mkv", fileName: "Film \(id).mkv", size: Int64(id),
                                      modified: nil, addedAt: start, matchState: .auto)
                entry.tmdb = TMDBMovieDetails(id: id, title: "Film \(id)")
                entry.funFacts = FunFacts(facts: [], articleTitle: "Film \(id)", fetchedAt: start)
                var old = CraftIndex.make(from: TechSpecs.read([]), colour: nil, keywords: [], sources: 1, now: start)
                old.version = 16
                old.discovery = 6
                entry.craft = old
                all.append(entry)
            }
        }
        XCTAssertEqual(all.count, 270)
        let due = CraftQueue.due(all, now: start.addingTimeInterval(60))
        XCTAssertEqual(due.count, 150, "every film once, however many copies")
        var run = CraftRun()
        var seen: [Int] = []
        while true {
            let batch = run.nextBatch(all, now: start.addingTimeInterval(60))
            if batch.isEmpty { break }
            seen += batch.compactMap { $0.tmdb?.id }
        }
        XCTAssertEqual(seen.count, 150)
        XCTAssertEqual(Set(seen).count, 150)
    }
}
