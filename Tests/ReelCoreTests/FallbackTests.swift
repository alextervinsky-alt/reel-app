import XCTest
@testable import ReelCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// American Cinematographer's search for "F1" as the 1.10.1 audit recorded it (titles and
/// addresses, in the site's order): three lens-news results kept, then two addresses of the
/// magazine's F1 article over the limit. The pages' text is made up for these tests.
enum FallbackFixtures {
    typealias F = DiscoveryFixtures

    enum Answer {
        case lens, about, thin
        case status(Int)
        case fail(Int)
    }

    static let lensNews: [(title: String, url: String)] = [
        ("Viltrox Unveils AF 35mm F1.2 Lab N FE", "https://theasc.com/article/viltrox-unveils-nbsp-af-35mm-f1-2-lab-n-fe/"),
        ("Viltrox Releases AF 16mm F1.8 L", "https://theasc.com/article/viltrox-releases-af-16mm-f1-8-l/"),
        ("Viltrox Unveils AF 35mm F1.2 Lab Z Prime", "https://theasc.com/article/viltrox-unveils-af-35mm-f1-2-lab-z-prime/"),
    ]
    static let fastTrack = (title: "On the Fast Track for F1: The Movie", url: "https://theasc.com/article/on-the-fast-track-for-f1-the-movie/")
    static let fastTrack2 = (title: "On the Fast Trackfor F1: The Movie", url: "https://theasc.com/article/f1-the-movie-cinematography/")

    static func route(_ url: String, _ answer: Answer) {
        let host = URL(string: url)!.host!
        let path = URL(string: url)!.path
        switch answer {
        case .lens: StandInSite.route(host, path, body: F.page("Lens news", NamePriorityFixtures.standIn("Lens news")))
        case .about: StandInSite.route(host, path, body: F.page("F1", NamePriorityFixtures.standIn("Claudio Miranda ASC ACC on F1")))
        case .thin: StandInSite.route(host, path, body: F.page("F1", ["Claudio Miranda ASC ACC on F1, in one made-up paragraph standing in for a short page."]))
        case .status(let code): StandInSite.route(host, path, status: code, body: "<p>Not here</p>")
        case .fail(let code): StandInSite.routeFail(host, path, code: code)
        }
    }

    /// The search, its kept results answering `picks`, and its spare results answering `spare`.
    static let storyPages = ["https://www.kodak.com/en/motion/blog-post/f1/", "https://www.kodak.com/en/motion/page/f1/",
                             "https://nofilmschool.com/f1-cinematography"]

    static func f1(picks: [Answer] = [.lens, .lens, .lens], titles: [String]? = nil, spare: [Answer] = [.about, .about],
                   stories: Answer = .status(404)) {
        StandInSite.reset()
        f1Search(picks: picks, titles: titles, spare: spare, stories: stories)
    }

    /// `f1` without starting again (routes added before it come first).
    static func f1Search(picks: [Answer] = [.lens, .lens, .lens], titles: [String]? = nil, spare: [Answer] = [.about, .about],
                         stories: Answer = .status(404)) {
        let kept = lensNews.enumerated().map { index, hit in (title: titles?[index] ?? hit.title, url: hit.url) }
        let further = Array([fastTrack, fastTrack2].prefix(spare.count))
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: F.ascHits((kept + further).map { ($0.title, $0.url, "article") }))
        for (hit, answer) in zip(kept, picks) { route(hit.url, answer) }
        for (hit, answer) in zip(further, spare) { route(hit.url, answer) }
        StandInSite.route("britishcinematographer.co.uk", "wp-json/wp/v2/posts", body: "[]")
        StandInSite.route("en.wikipedia.org", "prop=extracts", body: F.missingArticle)
        for url in storyPages { route(url, stories) }
    }
}

/// Reel 1.10.2: when every result American Cinematographer's search kept turns out to be another
/// film's, the next result naming the film is asked for: one page, from the same answer.
final class FallbackTests: XCTestCase {
    override func tearDown() {
        StandInSite.reset()
        super.tearDown()
    }

    private func client() -> CameraSourcesClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StandInSite.self]
        return CameraSourcesClient(session: URLSession(configuration: config))
    }

    private func asked(_ host: String) -> [String] { StandInSite.asked(of: host).map(\.absoluteString) }

    private func readF1(articleTitle: String? = nil) async -> CameraReading {
        await client().read(articleTitle: articleTitle, filmTitle: "F1", cinematographers: ["Claudio Miranda"],
                            directors: ["Joseph Kosinski"], year: 2025)
    }

    private func pagesAsked() -> [String] { asked("theasc.com").filter { !$0.contains("wp-json") } }

    // MARK: A. F1

    func testF1AsksForTheArticleAfterTheLensNews() async {
        FallbackFixtures.f1()
        let reading = await readF1()
        guard let fallback = reading.discovery?.fallback else { return XCTFail("no trace") }
        // The three kept, each another film's: then the first further result, once.
        XCTAssertEqual(fallback.picks, [.anotherFilm, .anotherFilm, .anotherFilm])
        XCTAssertEqual(fallback.url, FallbackFixtures.fastTrack.url)
        XCTAssertEqual(fallback.result, .read)
        XCTAssertEqual(asked("theasc.com").filter { $0.contains("wp-json") }.count, 1, "no new search")
        XCTAssertEqual(pagesAsked().count, 4, "the three kept and one more")
        XCTAssertFalse(pagesAsked().contains(FallbackFixtures.fastTrack2.url), "one further result, no more")
        // Read like any page: it names Miranda.
        XCTAssertEqual(reading.sources.map(\.url.absoluteString), [FallbackFixtures.fastTrack.url])
        XCTAssertEqual(reading.skipped.filter { $0.reason.hasPrefix("another film of that title") }.count, 3)
        // The search's own decisions are as before; the pages asked for by the usual limit too.
        XCTAssertEqual(reading.discovery?.searches[0].hits.map(\.rejected), [nil, nil, nil, .overLimit, .overLimit])
        XCTAssertEqual(reading.discovery?.assembly.asked.count, 3)
        // The log says why and what became of it.
        let lines = reading.discovery?.lines() ?? []
        XCTAssertTrue(lines.contains("  left out (over the limit): On the Fast Track for F1: The Movie — https://theasc.com/article/on-the-fast-track-for-f1-the-movie/ (then asked for as the one further result: see below)"), "\(lines)")
        XCTAssertTrue(lines.contains("• American Cinematographer, one more result (only when every result kept was another film's; kept: 3 another film's): On the Fast Track for F1: The Movie — https://theasc.com/article/on-the-fast-track-for-f1-the-movie/: read (see READ)"), "\(lines)")
        // Nothing made up for it: the stand-in page says nothing of how F1 was shot.
        var details = TMDBMovieDetails(id: 42, title: "F1", releaseDate: "2025-06-27")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Claudio Miranda", job: "Director of Photography")])
        XCTAssertEqual(CraftReader.reading(of: details, articleTitle: nil, article: nil, reading: reading, colour: nil).index.shotOn, [])
    }

    // MARK: B. A page read: no further result

    func testNoFurtherResultWhenAKeptPageWasRead() async {
        FallbackFixtures.f1(picks: [.lens, .about, .lens])
        let reading = await readF1()
        XCTAssertEqual(reading.discovery?.fallback?.picks, [.anotherFilm, .read, .anotherFilm])
        XCTAssertEqual(reading.discovery?.fallback?.result, .notTried("not every result kept was another film's"))
        XCTAssertEqual(pagesAsked().count, 3)
    }

    // MARK: C. Other failures: no further result

    func testNoFurtherResultForAnyOtherOutcome() async {
        let cases: [(FallbackFixtures.Answer, DiscoveryTrace.Fallback.Pick)] = [
            (.status(404), .notLoaded), (.fail(-1001), .notLoaded), (.status(403), .notLoaded), (.status(500), .notLoaded), (.thin, .thin),
        ]
        for (answer, pick) in cases {
            FallbackFixtures.f1(picks: [.lens, .lens, answer])
            let reading = await readF1()
            XCTAssertEqual(reading.discovery?.fallback?.picks.last, pick, "\(answer)")
            XCTAssertEqual(reading.discovery?.fallback?.result, .notTried("not every result kept was another film's"), "\(answer)")
            XCTAssertFalse(pagesAsked().contains(FallbackFixtures.fastTrack.url), "\(answer)")
        }
        // An interview about another craft.
        FallbackFixtures.f1(picks: [.lens, .lens, .about],
                            titles: [FallbackFixtures.lensNews[0].title, FallbackFixtures.lensNews[1].title, "F1: Editing the Race with its editor"])
        let craft = await readF1()
        XCTAssertEqual(craft.discovery?.fallback?.picks.last, .otherCraft)
        XCTAssertFalse(pagesAsked().contains(FallbackFixtures.fastTrack.url))
        // No result beyond the limit.
        FallbackFixtures.f1(spare: [])
        let none = await readF1()
        XCTAssertEqual(none.discovery?.fallback?.result, .notTried("no other result naming the film beyond the limit"))
        XCTAssertEqual(pagesAsked().count, 3)
    }

    /// Pages with too little text to tell whose they are don't show the search chose wrong; and
    /// with nothing to know the film's page by, no further result could be shown to be its.
    func testNoFurtherResultWithoutGroundsForIt() async {
        FallbackFixtures.f1(picks: [.lens, .lens, .status(200)])  // a page with no text to read
        let empty = await readF1()
        XCTAssertEqual(empty.discovery?.fallback?.picks.last, .thin)
        XCTAssertFalse(pagesAsked().contains(FallbackFixtures.fastTrack.url))
        FallbackFixtures.f1()
        let unknown = await client().read(articleTitle: nil, filmTitle: "F1", cinematographers: [], directors: [], year: 2025)
        XCTAssertEqual(unknown.discovery?.fallback?.result, .notTried("no cinematographer, or director and year, to know the film's page by"))
        XCTAssertFalse(pagesAsked().contains(FallbackFixtures.fastTrack.url))
    }

    /// Of the further results, one naming the cinematographer before the site's order.
    func testTheFurtherResultNamingTheCinematographerComesFirst() async {
        // The last place already went to a result naming him (1.10.1), whose page turned out to be
        // lens news; of the two left, the one naming him is asked for, not the site's next.
        let hits = FallbackFixtures.lensNews.prefix(2).map { ($0.title, $0.url, "article") } + [
            ("Claudio Miranda picks his F1.2 primes", "https://theasc.com/article/miranda-picks-f1-2-primes/", "article"),
            ("F1.4 primes compared", "https://theasc.com/article/f1-4-primes-compared/", "article"),
            ("Claudio Miranda, ASC, ACC on F1", "https://theasc.com/article/claudio-miranda-f1/", "article"),
        ]
        StandInSite.reset()
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: DiscoveryFixtures.ascHits(hits))
        for hit in FallbackFixtures.lensNews.prefix(2) { FallbackFixtures.route(hit.url, .lens) }
        FallbackFixtures.route("https://theasc.com/article/miranda-picks-f1-2-primes/", .lens)
        FallbackFixtures.route("https://theasc.com/article/claudio-miranda-f1/", .about)
        StandInSite.route("britishcinematographer.co.uk", "wp-json/wp/v2/posts", body: "[]")
        StandInSite.route("en.wikipedia.org", "prop=extracts", body: DiscoveryFixtures.missingArticle)
        for url in FallbackFixtures.storyPages { FallbackFixtures.route(url, .status(404)) }
        let reading = await readF1()
        XCTAssertEqual(reading.discovery?.fallback?.url, "https://theasc.com/article/claudio-miranda-f1/")
        XCTAssertEqual(reading.discovery?.fallback?.result, .read)
        XCTAssertFalse(pagesAsked().contains("https://theasc.com/article/f1-4-primes-compared/"))
    }

    /// Other sources read don't stop it: the search's choice was still wrong (F1: British
    /// Cinematographer's interview read, American Cinematographer's lens news not).
    func testOtherSourcesReadDontStopIt() async {
        StandInSite.reset()
        StandInSite.route("britishcinematographer.co.uk", "wp-json/wp/v2/posts", body: DiscoveryFixtures.bcHits([
            ("Claudio Miranda ASC ACC / F1: The Movie", "https://britishcinematographer.co.uk/claudio-miranda-asc-acc-f1-the-movie/")]))
        FallbackFixtures.route("https://britishcinematographer.co.uk/claudio-miranda-asc-acc-f1-the-movie/", .about)
        FallbackFixtures.f1Search()
        let reading = await readF1()
        XCTAssertEqual(reading.sources.first?.site, "British Cinematographer")
        XCTAssertEqual(reading.discovery?.fallback?.result, .read)
        XCTAssertEqual(reading.sources.count, 2)
    }

    // MARK: D. The further result fails too

    func testAFurtherResultThatFailsIsTheLast() async {
        // Another film's too: no second one.
        FallbackFixtures.f1(spare: [.lens, .about])
        let other = await readF1()
        XCTAssertEqual(other.discovery?.fallback?.result, .anotherFilm)
        XCTAssertEqual(pagesAsked().count, 4)
        XCTAssertFalse(pagesAsked().contains(FallbackFixtures.fastTrack2.url))
        XCTAssertTrue(other.sources.isEmpty)
        // Gone: kept as a limit, like any page found; no retry.
        FallbackFixtures.f1(spare: [.status(404), .about])
        let gone = await readF1()
        XCTAssertEqual(gone.discovery?.fallback?.result, .unavailable("gone: not found over HTTPS (404)"))
        XCTAssertEqual(gone.skipped.last?.limit, .gone)
        XCTAssertFalse(pagesAsked().contains(FallbackFixtures.fastTrack2.url))
        // Not answering: like any page asked for, the site is noted and the film read again later
        // (never "Complete"), on the usual schedule; and still no second further result.
        FallbackFixtures.f1(spare: [.fail(-1001), .about])
        let quiet = await readF1()
        XCTAssertEqual(quiet.discovery?.fallback?.result, .unavailable("didn't answer: timed out (read again later)"))
        XCTAssertEqual(quiet.unanswered, ["American Cinematographer"])
        XCTAssertEqual(quiet.skipped.last?.limit, .unanswered)
        XCTAssertFalse(pagesAsked().contains(FallbackFixtures.fastTrack2.url))
        var details = TMDBMovieDetails(id: 42, title: "F1", releaseDate: "2025-06-27")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Claudio Miranda", job: "Director of Photography")])
        let index = CraftReader.reading(of: details, articleTitle: nil, article: nil, reading: quiet, colour: nil).index
        XCTAssertEqual(index.coverage, .partial)
        let stored = CraftIndex.merging(old: CraftIndex(shotOn: [], names: [], sources: 1, discovery: 4), new: index).index
        XCTAssertNotNil(stored.retryAt, "read again later, on the usual schedule")
        XCTAssertEqual(CraftQueue.state(craft: stored, attempt: nil, hasFacts: true, inCollection: true, now: Date()), .partial)
        XCTAssertFalse(CraftQueue.isDue(craft: stored, attempt: nil, hasFacts: true, inCollection: true, now: Date()), "not every launch")
        // Refused: kept as a limit, no retry.
        FallbackFixtures.f1(spare: [.status(403), .about])
        let refused = await readF1()
        XCTAssertEqual(refused.skipped.last?.limit, .restricted)
        XCTAssertEqual(refused.unanswered, [])
        // Too thin: not read, and said so.
        FallbackFixtures.f1(spare: [.thin, .about])
        let thin = await readF1()
        XCTAssertEqual(thin.discovery?.fallback?.result, .notRead("too little text to read"))
        XCTAssertTrue(thin.sources.isEmpty)
    }

    // MARK: E. An article already found

    func testAnArticleAlreadyFoundIsPassedOver() async {
        FallbackFixtures.f1()
        // Wikipedia cites the F1 article at its old ascmag.com address: the same article.
        StandInSite.route("en.wikipedia.org", "prop=extlinks", body: DiscoveryFixtures.extlinks(["https://ascmag.com/articles/on-the-fast-track-for-f1-the-movie"]))
        StandInSite.route("ascmag.com", "on-the-fast-track", body: DiscoveryFixtures.page("F1", NamePriorityFixtures.standIn("Claudio Miranda ASC ACC on F1")))
        let reading = await readF1(articleTitle: "F1 (film)")
        guard let fallback = reading.discovery?.fallback else { return XCTFail("no trace") }
        XCTAssertEqual(fallback.alreadyFound, [FallbackFixtures.fastTrack.url])
        // The next one is a different article (another address, not an alias of it): asked for.
        XCTAssertEqual(fallback.url, FallbackFixtures.fastTrack2.url)
        XCTAssertFalse(pagesAsked().contains(FallbackFixtures.fastTrack.url), "not asked for again under its other address")
        XCTAssertTrue(pagesAsked().contains(FallbackFixtures.fastTrack2.url))
        XCTAssertEqual(asked("ascmag.com").count, 1)
        XCTAssertNotEqual(CameraSources.identity(URL(string: FallbackFixtures.fastTrack.url)!),
                          CameraSources.identity(URL(string: FallbackFixtures.fastTrack2.url)!), "the same title isn't the same article")
        XCTAssertEqual(CameraSources.identity(URL(string: FallbackFixtures.fastTrack.url)!),
                       CameraSources.identity(URL(string: "https://ascmag.com/articles/on-the-fast-track-for-f1-the-movie")!))
    }

    // MARK: F. The limits on pages asked for and read

    func testNoFurtherResultOnceEightPagesWereAskedFor() async {
        FallbackFixtures.f1()
        let cited = (1...5).map { "https://www.ymcinema.com/2025/f1-claudio-miranda-\($0)/" }
        StandInSite.route("en.wikipedia.org", "prop=extlinks", body: DiscoveryFixtures.extlinks(cited))
        for url in cited { FallbackFixtures.route(url, .about) }
        let reading = await readF1(articleTitle: "F1 (film)")
        XCTAssertEqual(reading.discovery?.assembly.asked.count, 8)
        XCTAssertEqual(reading.discovery?.fallback?.result, .notTried("the 8 pages to ask for were all asked for"))
        XCTAssertEqual(reading.discovery?.fallback?.url, FallbackFixtures.fastTrack.url)
        XCTAssertFalse(pagesAsked().contains(FallbackFixtures.fastTrack.url))
    }

    func testNoFurtherResultOnceSixPagesWereRead() async {
        // The three guessed story pages found and naming Miranda, and three cited pages.
        FallbackFixtures.f1(stories: .about)
        let cited = (1...3).map { "https://www.ymcinema.com/2025/f1-claudio-miranda-\($0)/" }
        StandInSite.route("en.wikipedia.org", "prop=extlinks", body: DiscoveryFixtures.extlinks(cited))
        for url in cited { FallbackFixtures.route(url, .about) }
        let reading = await readF1(articleTitle: "F1 (film)")
        XCTAssertEqual(reading.sources.count, 6)
        XCTAssertLessThan(reading.discovery?.assembly.asked.count ?? 9, 8)
        XCTAssertEqual(reading.discovery?.fallback?.result, .notTried("6 pages were already read"))
        XCTAssertFalse(pagesAsked().contains(FallbackFixtures.fastTrack.url))
    }

    // MARK: G. What it finds is stored like anything else

    func testWhatTheFurtherResultSaysIsStoredAndMerged() async {
        // A made-up film: the further result says how it was shot.
        StandInSite.reset()
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: DiscoveryFixtures.ascHits([
            ("Ferry Lights at the Harbour Festival", "https://theasc.com/news/ferry-lights-harbour-festival/", "news"),
            ("Ferry Lights: a new lamp for night exteriors", "https://theasc.com/article/ferry-lights-lamp/", "article"),
            ("Ferry Lights restored", "https://theasc.com/article/ferry-lights-restored/", "article"),
            ("Shooting Ferry Lights", "https://theasc.com/article/shooting-ferry-lights/", "article"),
        ]))
        for slug in ["ferry-lights-harbour-festival", "ferry-lights-lamp", "ferry-lights-restored"] {
            StandInSite.route("theasc.com", slug, body: DiscoveryFixtures.page("Other", NamePriorityFixtures.standIn("Another subject")))
        }
        StandInSite.route("theasc.com", "shooting-ferry-lights", body: DiscoveryFixtures.page("Shooting Ferry Lights", [
            "Jane Doe shot Ferry Lights on Kodak 35mm film, every scene of it, on two Panaflex cameras.",
            "Doe says the harbour at night needed the film's latitude more than any digital camera could give.",
            "The made-up interview goes on about the lamps on the quay, long enough to be read as prose.",
        ]))
        StandInSite.route("britishcinematographer.co.uk", "wp-json/wp/v2/posts", body: "[]")
        StandInSite.route("en.wikipedia.org", "prop=extracts", body: DiscoveryFixtures.missingArticle)
        StandInSite.route("www.kodak.com", "ferry-lights", status: 404, body: "<p>Not here</p>")
        StandInSite.route("nofilmschool.com", "ferry-lights", status: 404, body: "<p>Not here</p>")
        let reading = await client().read(articleTitle: nil, filmTitle: "Ferry Lights", cinematographers: ["Jane Doe"], directors: [], year: 2019)
        XCTAssertEqual(reading.discovery?.fallback?.result, .read)
        var details = TMDBMovieDetails(id: 51, title: "Ferry Lights", releaseDate: "2019-01-01")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Jane Doe", job: "Director of Photography")])
        let new = CraftReader.reading(of: details, articleTitle: nil, article: nil, reading: reading, colour: nil).index
        XCTAssertTrue(new.shotOn.contains(.film))
        XCTAssertEqual(new.evidence(for: .film)?.source, "American Cinematographer")
        XCTAssertEqual(new.discovery, 5)
        // Merged with an older reading that had nothing: the new tag is stored.
        let old = CraftIndex(shotOn: [], names: [], sources: 1, read: ["Wikipedia"], discovery: 4)
        XCTAssertTrue(CraftIndex.merging(old: old, new: new).index.shotOn.contains(.film))
        // And a tag from a site that didn't answer this time is kept.
        let digital = CraftIndex.Evidence(shotOn: .anamorphic, text: "Doe used anamorphic lenses.", source: "British Cinematographer")
        let earlier = CraftIndex(shotOn: [.anamorphic], names: [], evidence: [digital], sources: 2, discovery: 4)
        var down = new
        down.unanswered = ["British Cinematographer"]
        XCTAssertTrue(CraftIndex.merging(old: earlier, new: down).index.shotOn.contains(.anamorphic))
    }
}
