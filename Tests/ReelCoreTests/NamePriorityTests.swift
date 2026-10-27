import XCTest
@testable import ReelCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Search results as the 1.10.0 audit recorded them for Barbie and F1 (their titles and addresses,
/// in the order the sites gave them). The pages' text is made up for these tests: it stands in for
/// the real pages and says nothing about how either film was shot.
enum NamePriorityFixtures {
    typealias F = DiscoveryFixtures

    static func standIn(_ who: String) -> [String] {
        ["\(who), in a paragraph made up for this test, standing in for the real page's opening.",
         "A second made-up paragraph, long enough for Reel to read, standing in for the interview itself.",
         "A third made-up paragraph, so the page has enough text to read, and no word on how it was shot."]
    }

    static func barbie() {
        StandInSite.reset()
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: F.ascHits([
            ("Barbie: “What Was I Made For?” Re-Imagines A Classic", "https://theasc.com/article/barbie-what-was-i-made-for/", "article"),
        ]))
        StandInSite.route("theasc.com", "barbie-what-was-i-made-for", body: F.page("What Was I Made For?", standIn("A music video, not the film")))
        StandInSite.route("britishcinematographer.co.uk", "wp-json/wp/v2/posts", body: F.bcHits([
            ("Sara Garth / Black Barbie", "https://britishcinematographer.co.uk/sara-garth-black-barbie/"),
            ("Barbie and Ahsoka take home top honours at ICG Publicists Awards",
             "https://britishcinematographer.co.uk/barbie-and-ahsoka-take-home-top-honours-at-icg-publicists-awards/"),
            ("Lighting the night", "https://britishcinematographer.co.uk/lighting-the-night/"),
            ("Rodrigo Prieto ASC AMC / Barbie", "https://britishcinematographer.co.uk/rodrigo-prieto-asc-amc-barbie/"),
        ]))
        // Another film's page, with a camera sentence of its own: never this film's.
        StandInSite.route("britishcinematographer.co.uk", "sara-garth-black-barbie", body: F.page("Sara Garth / Black Barbie", [
            "Sara Garth, in a made-up paragraph for this test, says the documentary was shot on 16mm film throughout.",
            "A second made-up paragraph about that documentary, long enough for Reel to read it as prose.",
            "A third made-up paragraph about that documentary, so the page has enough text to be read.",
        ]))
        StandInSite.route("britishcinematographer.co.uk", "barbie-and-ahsoka", body: F.page("Awards", standIn("An awards item")))
        StandInSite.route("britishcinematographer.co.uk", "rodrigo-prieto-asc-amc-barbie",
                          body: F.page("Rodrigo Prieto ASC AMC / Barbie", standIn("Rodrigo Prieto ASC AMC on Barbie")))
        StandInSite.route("en.wikipedia.org", "prop=extracts", body: F.missingArticle)
        StandInSite.route("www.kodak.com", "/barbie/", status: 404, body: "<p>Not here</p>")
        StandInSite.route("nofilmschool.com", "barbie-cinematography", status: 404, body: "<p>Not here</p>")
    }

    static func f1(promotedPage: [String]? = nil) {
        StandInSite.reset()
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: F.ascHits([
            ("Viltrox Unveils AF 35mm F1.2 Lab N FE", "https://theasc.com/article/viltrox-unveils-nbsp-af-35mm-f1-2-lab-n-fe/", "article"),
            ("Viltrox Releases AF 16mm F1.8 L", "https://theasc.com/article/viltrox-releases-af-16mm-f1-8-l/", "article"),
            ("Viltrox Unveils AF 35mm F1.2 Lab Z Prime", "https://theasc.com/article/viltrox-unveils-af-35mm-f1-2-lab-z-prime/", "article"),
            ("On the Fast Track for F1: The Movie", "https://theasc.com/article/on-the-fast-track-for-f1-the-movie/", "article"),
        ]))
        StandInSite.route("theasc.com", "viltrox", body: F.page("Viltrox", standIn("Lens news")))
        StandInSite.route("britishcinematographer.co.uk", "wp-json/wp/v2/posts", body: F.bcHits([
            ("LK Samyang expands Prima Series with new AF 35mm F1.8 P FE lens",
             "https://britishcinematographer.co.uk/lk-samyang-expands-prima-series-with-new-af-35mm-f1-8-p-fe-lens/"),
            ("F1 and Simon Hayes honoured at AMPS Awards", "https://britishcinematographer.co.uk/f1-and-simon-hayes-honoured-at-amps-awards/"),
            ("Claudio Miranda ASC ACC / F1: The Movie", "https://britishcinematographer.co.uk/claudio-miranda-asc-acc-f1-the-movie/"),
        ]))
        StandInSite.route("britishcinematographer.co.uk", "lk-samyang", body: F.page("LK Samyang", standIn("Lens news")))
        StandInSite.route("britishcinematographer.co.uk", "amps-awards", body: F.page("AMPS", standIn("An awards item")))
        StandInSite.route("britishcinematographer.co.uk", "claudio-miranda-asc-acc-f1-the-movie",
                          body: F.page("Claudio Miranda ASC ACC / F1: The Movie", promotedPage ?? standIn("Claudio Miranda ASC ACC on F1")))
        StandInSite.route("en.wikipedia.org", "prop=extracts", body: F.missingArticle)
        StandInSite.route("www.kodak.com", "/f1/", status: 404, body: "<p>Not here</p>")
        StandInSite.route("nofilmschool.com", "f1-cinematography", status: 404, body: "<p>Not here</p>")
    }
}

/// Reel 1.10.1: of the magazines' search results that name the film, the last place goes to one
/// that names the film's cinematographer, through the same selection the app uses.
final class NamePriorityTests: XCTestCase {
    override func tearDown() {
        StandInSite.reset()
        super.tearDown()
    }

    private func client() -> CameraSourcesClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StandInSite.self]
        return CameraSourcesClient(session: URLSession(configuration: config))
    }

    private func asked(_ host: String) -> [String] { StandInSite.asked(of: host).map(\.absoluteString).sorted() }
    private func reasons(_ hits: [DiscoveryTrace.Hit]) -> [DiscoveryTrace.Rejection?] { hits.map(\.rejected) }

    // MARK: A. Barbie

    func testBarbieTheCinematographersInterviewTakesTheLastPlace() async {
        NamePriorityFixtures.barbie()
        let reading = await client().read(articleTitle: nil, filmTitle: "Barbie", cinematographers: ["Rodrigo Prieto"],
                                          directors: ["Greta Gerwig"], year: 2023)
        guard let british = reading.discovery?.searches.first(where: { $0.site == "British Cinematographer" }) else { return XCTFail("no trace") }
        XCTAssertEqual(british.outcome, .answered(4))
        // The site's first kept as before; the interview for the last place, the awards item over the limit.
        XCTAssertEqual(reasons(british.hits), [nil, .overLimit, .notAboutFilm, nil])
        XCTAssertEqual(british.hits.map(\.promotedForName), [false, false, false, true])
        XCTAssertEqual(british.hits.filter { $0.rejected == nil }.count, 2, "still at most two")
        // The same number of requests as before: one search, two pages.
        XCTAssertEqual(asked("britishcinematographer.co.uk").count, 3)
        XCTAssertTrue(asked("britishcinematographer.co.uk").contains("https://britishcinematographer.co.uk/rodrigo-prieto-asc-amc-barbie/"))
        XCTAssertFalse(asked("britishcinematographer.co.uk").contains { $0.contains("barbie-and-ahsoka") }, "over the limit: not asked for")
        // Read like any page; the other film's page still left out after it's fetched.
        XCTAssertTrue(reading.sources.map(\.url.absoluteString).contains("https://britishcinematographer.co.uk/rodrigo-prieto-asc-amc-barbie/"))
        XCTAssertTrue(reading.skipped.contains {
            $0.source.url.absoluteString == "https://britishcinematographer.co.uk/sara-garth-black-barbie/" && $0.reason.hasPrefix("another film of that title")
        })
        // The log says what was chosen and why.
        let lines = reading.discovery?.lines() ?? []
        XCTAssertTrue(lines.contains("  kept, ahead of the site's order for naming the cinematographer: Rodrigo Prieto ASC AMC / Barbie — https://britishcinematographer.co.uk/rodrigo-prieto-asc-amc-barbie/"), "\(lines)")
        XCTAssertTrue(lines.contains("  left out (over the limit): Barbie and Ahsoka take home top honours at ICG Publicists Awards — https://britishcinematographer.co.uk/barbie-and-ahsoka-take-home-top-honours-at-icg-publicists-awards/ (its place went to a result naming the cinematographer)"), "\(lines)")
        XCTAssertEqual(british.hits.map(\.displacedForName), [false, true, false, false])
        // Nothing from the other film's page.
        var details = TMDBMovieDetails(id: 41, title: "Barbie", releaseDate: "2023-07-21")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Rodrigo Prieto", job: "Director of Photography")])
        let index = CraftReader.reading(of: details, articleTitle: nil, article: nil, reading: reading, colour: nil).index
        XCTAssertFalse(index.shotOn.contains(.film), "the documentary's 16mm isn't Barbie's")
    }

    // MARK: B and C. F1

    func testF1TheBritishInterviewIsAskedForTheAmericanArticleIsStillBeyondTheLimit() async {
        NamePriorityFixtures.f1()
        let reading = await client().read(articleTitle: nil, filmTitle: "F1", cinematographers: ["Claudio Miranda"],
                                          directors: ["Joseph Kosinski"], year: 2025)
        guard let trace = reading.discovery else { return XCTFail("no trace") }
        // British Cinematographer: the interview in place of the awards item.
        XCTAssertEqual(reasons(trace.searches[1].hits), [nil, .overLimit, nil])
        XCTAssertEqual(trace.searches[1].hits.map(\.promotedForName), [false, false, true])
        // American Cinematographer: no result names Miranda, so the order is the site's, as before.
        // "On the Fast Track for F1: The Movie" names the film but not him: still over the limit
        // (reading it would take another request, not this change).
        XCTAssertEqual(reasons(trace.searches[0].hits), [nil, nil, nil, .overLimit])
        XCTAssertEqual(trace.searches[0].hits.map(\.promotedForName), [false, false, false, false])
        XCTAssertFalse(asked("theasc.com").contains { $0.contains("on-the-fast-track") })
        // Requests: one search and three pages there, one search and two pages here, as before.
        XCTAssertEqual(asked("theasc.com").count, 4)
        XCTAssertEqual(asked("britishcinematographer.co.uk").count, 3)
        XCTAssertEqual(trace.assembly.asked.count, 5)
        XCTAssertEqual(reading.sources.map(\.url.absoluteString), ["https://britishcinematographer.co.uk/claudio-miranda-asc-acc-f1-the-movie/"])
        // The lens news is still left out after it's read: it doesn't name Miranda.
        XCTAssertEqual(reading.skipped.filter { $0.reason.hasPrefix("another film of that title") }.count, 4)
    }

    /// A page kept for its title is still read only when its text names the film's people.
    func testAPageKeptForItsTitleIsStillCheckedForTheFilm() async {
        NamePriorityFixtures.f1(promotedPage: [
            "A made-up paragraph about a karting championship this summer, shot on 35mm film for its broadcast.",
            "A second made-up paragraph about the karting championship, long enough to be read as prose.",
            "A third made-up paragraph about the karting championship, so the page has enough text to read.",
        ])
        let reading = await client().read(articleTitle: nil, filmTitle: "F1", cinematographers: ["Claudio Miranda"],
                                          directors: ["Joseph Kosinski"], year: 2025)
        XCTAssertTrue(reading.sources.isEmpty)
        XCTAssertTrue(reading.skipped.contains {
            $0.source.url.absoluteString.contains("claudio-miranda") && $0.reason.hasPrefix("another film of that title")
        })
        var details = TMDBMovieDetails(id: 42, title: "F1", releaseDate: "2025-06-27")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Claudio Miranda", job: "Director of Photography")])
        let index = CraftReader.reading(of: details, articleTitle: nil, article: nil, reading: reading, colour: nil).index
        XCTAssertEqual(index.shotOn, [], "a name in a title is never evidence")
    }

    // MARK: E. Blade Runner 2049: the article that doesn't name Deakins

    /// American Cinematographer's search for "Blade Runner 2049" as the site answered it on
    /// 27 October 2026 (titles, addresses and kinds; the pages aren't needed). Its own article,
    /// "Uncanny Valley", names the film but not Deakins; several results after it name him.
    static let bladeRunnerSearch: [(title: String, url: String, subtype: String)] = [
        ("Deakins Honored with BSC Award for Blade Runner 2049", "https://theasc.com/news/deakins-honored-with-bsc-award-for-blade-runner-2049/", "news"),
        ("Uncanny Valley: Blade Runner 2049", "https://theasc.com/article/uncanny-valley-blade-runner-2049/", "article"),
        ("Dive Deeper into Blade Runner 2049 with Roger Deakins, ASC, BSC", "https://theasc.com/article/deakins-blade-runner-2049/", "article"),
    ] + [1, 2, 7, 6, 3, 5, 4].map {
        ("Blade Runner 2049: Roger Deakins, ASC, BSC – Part \($0)", "https://theasc.com/video/clubhouse-conversation-with-roger-deakins-cbe-asc-bsc-part-\($0)/", "video")
    } + [
        ("Watch Blade Runner 2049 Discussion with Roger Deakins, ASC, BSC", "https://theasc.com/article/roger-deakins-asc-bsc-blade-runner-2049-discussion/", "article"),
        ("Roger Deakins, ASC, BSC at Clubhouse for Blade Runner 2049 Discussion", "https://theasc.com/news/roger-deakins-at-clubhouse-for-blade-runner-2049-discussion/", "news"),
        ("Join Roger Deakins, ASC, BSC at Clubhouse for Blade Runner 2049 Discussion", "https://theasc.com/news/join-roger-deakins-asc-bsc-at-clubhouse-for-blade-runner-2049-discussion/", "news"),
        ("Blade Runner 2049: Designing the Future", "https://theasc.com/article/blade-runner-2049-designing-the-future/", "article"),
        ("Dive Deep in Blade Runner 2047 with Roger Deakins, ASC, BSC", "https://theasc.com/article/deakins/", "article"),
        ("Deakins Receives 2nd Annual Sue Gibson, BSC Cinematography Award", "https://theasc.com/news/deakins-receives-the-sue-gibson-bsc-cinematography-award/", "news"),
        ("Roger Deakins, ASC, BSC on his Eclair NPR Camera", "https://theasc.com/video/roger-deakins-asc-bsc-on-his-eclair-npr-camera/", "video"),
        ("Details on Upcoming December Issue of AC", "https://theasc.com/article/details-on-upcoming-december-issue-of-ac/", "article"),
        ("Picture Shop, Sony Collaborate on Signature LUT", "https://theasc.com/article/picture-shop-sony-collaborate-on-signature-lut/", "article"),
        ("Universal Translator: Arrival", "https://theasc.com/article/arrival-cinematography-bradford-young/", "article"),
    ]

    func testBladeRunner2049KeepsItsOwnArticleInTheSitesOrder() async {
        StandInSite.reset()
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: DiscoveryFixtures.ascHits(Self.bladeRunnerSearch))
        let found = await client().ascSearch(filmTitle: "Blade Runner 2049", otherTitles: ["Blade Runner"], cinematographers: ["Roger Deakins"])
        // The first three that name the film, as before: the third names Deakins anyway.
        XCTAssertEqual(found.found.map(\.url.absoluteString), [
            "https://theasc.com/news/deakins-honored-with-bsc-award-for-blade-runner-2049/",
            "https://theasc.com/article/uncanny-valley-blade-runner-2049/",
            "https://theasc.com/article/deakins-blade-runner-2049/",
        ])
        XCTAssertEqual(found.trace.hits.map(\.rejected), [nil, nil, nil] + Array(repeating: .wrongKind, count: 7)
                       + [.overLimit, .overLimit, .overLimit, .overLimit, .notAboutFilm, .notAboutFilm, .wrongKind, .notAboutFilm, .notAboutFilm, .notAboutFilm])
        XCTAssertFalse(found.trace.hits.contains { $0.promotedForName || $0.displacedForName })
        // Without names, the same three.
        let plain = await client().ascSearch(filmTitle: "Blade Runner 2049", otherTitles: ["Blade Runner"])
        XCTAssertEqual(plain.found.map(\.url), found.found.map(\.url))
    }

    /// The risk this change takes: when the site ranks the film's own article last of three and a
    /// result naming the cinematographer comes after it, the article is left over the limit, and
    /// the log says so.
    func testAnArticleInTheLastPlaceCanBeLeftOutForOneNamingTheCinematographer() {
        let hits = [
            (title: "Deakins Honored with BSC Award for Blade Runner 2049", link: "https://theasc.com/news/deakins-honored-with-bsc-award-for-blade-runner-2049/"),
            (title: "Blade Runner 2049: Designing the Future", link: "https://theasc.com/article/blade-runner-2049-designing-the-future/"),
            (title: "Uncanny Valley: Blade Runner 2049", link: "https://theasc.com/article/uncanny-valley-blade-runner-2049/"),
            (title: "Watch Blade Runner 2049 Discussion with Roger Deakins, ASC, BSC", link: "https://theasc.com/article/roger-deakins-asc-bsc-blade-runner-2049-discussion/"),
        ]
        let decided = CameraSources.aboutDecisions("Blade Runner 2049", in: hits, site: "AC", limit: 3, cinematographers: ["Roger Deakins"])
        XCTAssertEqual(decided.decisions.map(\.rejected), [nil, nil, .overLimit, nil])
        XCTAssertEqual(decided.decisions.map(\.displacedForName), [false, false, true, false])
        XCTAssertEqual(decided.decisions.map(\.promotedForName), [false, false, false, true])
        let lines = DiscoveryTrace.hitLines(decided.decisions)
        XCTAssertTrue(lines.contains("  left out (over the limit): Uncanny Valley: Blade Runner 2049 — https://theasc.com/article/uncanny-valley-blade-runner-2049/ (its place went to a result naming the cinematographer)"), "\(lines)")
    }

    /// A page left over the limit that gave a tag before: the tag is carried, the reading read
    /// again, and the tag dropped only after `maxRetries` readings without its page (the usual rule
    /// for a page not found again), never at once.
    func testATagFromAPageLeftOverTheLimitIsCarriedThenDropped() {
        let film = CraftIndex.Evidence(shotOn: .film, text: "The film was shot on 35mm.", source: "American Cinematographer")
        let old = CraftIndex(shotOn: [.film], names: [], evidence: [film], sources: 3, read: ["Wikipedia", "American Cinematographer"], discovery: 3)
        let new = CraftIndex(shotOn: [], names: [], sources: 2, read: ["Wikipedia", "British Cinematographer"])
        let first = CraftIndex.merging(old: old, new: new)
        XCTAssertEqual(first.index.shotOn, [.film])
        XCTAssertEqual(first.carried.first?.misses, 1)
        XCTAssertTrue(first.index.isPartial, "read again later")
        var last = old
        last.evidence = [CraftIndex.Evidence(shotOn: .film, text: film.text, source: film.source, carriedFrom: Date(), carriedRules: 11,
                                             misses: CraftIndex.maxRetries)]
        let dropped = CraftIndex.merging(old: last, new: new)
        XCTAssertEqual(dropped.index.shotOn, [])
        XCTAssertEqual(dropped.dropped.map(\.reason), ["American Cinematographer wasn't found again in \(CraftIndex.maxRetries) readings"])
    }

    // MARK: D. Name matching

    func testHowPlainlyAResultNamesTheCinematographer() {
        func names(_ title: String, _ who: [String], link: String = "https://example.org/a/") -> Int {
            CameraSources.namesCinematographer(title: title, link: link, cinematographers: who)
        }
        XCTAssertEqual(names("Rodrigo Prieto ASC AMC / Barbie", ["Rodrigo Prieto"]), 2, "the whole name")
        XCTAssertEqual(names("Interview / Barbie", ["Rodrigo Prieto"], link: "https://britishcinematographer.co.uk/rodrigo-prieto-asc-amc-barbie/"), 2,
                       "the whole name in the address")
        XCTAssertEqual(names("Prieto on the pinks of Barbie", ["Rodrigo Prieto"]), 1, "the surname alone")
        XCTAssertEqual(names("Interview / Barbie", ["Rodrigo Prieto"], link: "https://example.org/prieto-barbie/"), 0,
                       "the surname alone counts only in the title")
        XCTAssertEqual(names("Tim Burton interview: Snatch remake", ["Tim Maurice-Jones"]), 0, "a given name of three letters alone is no name")
        XCTAssertEqual(names("Hong on Hope", ["Hong Kyung-pyo"]), 1, "the family name first, four letters")
        XCTAssertEqual(names("R. PRIETO, ASC, AMC: Barbie", ["Rodrigo Prieto"]), 1, "an initial, capitals, punctuation")
        XCTAssertEqual(names("Tim Maurice Jones BSC / Snatch", ["Tim Maurice-Jones"]), 2, "a hyphen written as a space")
        XCTAssertEqual(names("Łukasz Żal PSC / The Zone of Interest", ["Lukasz Zal"]), 2, "accents")
        XCTAssertEqual(names("Hong Kyung-pyo / Hope", ["Hong Kyung-pyo"]), 2)
        XCTAssertEqual(names("Kyung-pyo on Hope", ["Hong Kyung-pyo"]), 1)
        XCTAssertEqual(names("Hollywood Reporter roundtable: Green Book", ["Sean Porter"]), 0, "not part of another word")
        XCTAssertEqual(names("Portering the Green Book", ["Sean Porter"]), 0)
        XCTAssertEqual(names("Barbie", ["Rodrigo Prieto"], link: "https://example.org/prietolux-barbie/"), 0)
        XCTAssertEqual(names("Ed on Barbie", ["Rodrigo Ed"]), 0, "a surname under three letters isn't a name of its own")
        XCTAssertEqual(names("Rodrigo Prieto / Barbie", []), 0, "no cinematographer known")
        XCTAssertEqual(names("Linus Sandgren and Rodrigo Prieto / Barbie", ["Linus Sandgren", "Rodrigo Prieto"]), 2, "either of two")
    }

    func testTheWholeNameBeforeTheSurnameAndTheSitesOrderAmongEquals() {
        let hits = [
            (title: "Racing on film: F1", link: "https://britishcinematographer.co.uk/racing-on-film-f1/"),
            (title: "Miranda Richardson joins the F1 premiere", link: "https://britishcinematographer.co.uk/f1-premiere-miranda-richardson/"),
            (title: "Claudio Miranda ASC ACC / F1: The Movie", link: "https://britishcinematographer.co.uk/claudio-miranda-asc-acc-f1-the-movie/"),
            (title: "Claudio Miranda on F1, part two", link: "https://britishcinematographer.co.uk/claudio-miranda-f1-part-two/"),
        ]
        let decided = CameraSources.aboutDecisions("F1", in: hits, site: "BC", limit: 2, cinematographers: ["Claudio Miranda"])
        XCTAssertEqual(decided.found.map(\.url.absoluteString), [
            "https://britishcinematographer.co.uk/racing-on-film-f1/",
            "https://britishcinematographer.co.uk/claudio-miranda-asc-acc-f1-the-movie/",
        ], "the site's first; then the whole name over the surname alone, the earlier of the two")
        XCTAssertEqual(decided.decisions.map(\.rejected), [nil, .overLimit, nil, .overLimit])
        // Kept in the site's order, not the name's: the interview isn't read ahead of the site's first.
        // With no name known, or none matching, it's the site's order exactly as before.
        let plain = CameraSources.aboutDecisions("F1", in: hits, site: "BC", limit: 2)
        XCTAssertEqual(plain.decisions.map(\.rejected), [nil, nil, .overLimit, .overLimit])
        XCTAssertEqual(CameraSources.aboutDecisions("F1", in: hits, site: "BC", limit: 2, cinematographers: ["Jane Doe"]).decisions,
                       plain.decisions)
        // The same answers, the same choice.
        XCTAssertEqual(CameraSources.aboutDecisions("F1", in: hits, site: "BC", limit: 2, cinematographers: ["Claudio Miranda"]).decisions,
                       decided.decisions)
        // Results within the limit are kept whatever the name: none moves ahead of them.
        let three = CameraSources.aboutDecisions("F1", in: Array(hits.prefix(3)), site: "AC", limit: 3, cinematographers: ["Claudio Miranda"])
        XCTAssertEqual(three.decisions.map(\.rejected), [nil, nil, nil])
        XCTAssertEqual(three.decisions.map(\.promotedForName), [false, false, false])
    }

    // MARK: E. The filters before the name

    func testTheNameNeverKeepsAResultTheFiltersLeaveOut() {
        // Names the cinematographer, not the film.
        let notAbout = CameraSources.aboutDecisions("F1", in: [
            (title: "Lens news: F1.4 primes", link: "https://britishcinematographer.co.uk/lens-news-f1-4-primes/"),
            (title: "Claudio Miranda ASC ACC / Top Gun: Maverick", link: "https://britishcinematographer.co.uk/claudio-miranda-asc-acc-top-gun-maverick/"),
        ], site: "BC", limit: 1, cinematographers: ["Claudio Miranda"])
        XCTAssertEqual(notAbout.decisions.map(\.rejected), [nil, .notAboutFilm])
        // Another film of the collection, however plainly it names the cinematographer.
        let other = CameraSources.aboutDecisions("Dune", in: [
            (title: "Dune: a look back", link: "https://britishcinematographer.co.uk/dune-a-look-back/"),
            (title: "Greig Fraser ASC ACS / Dune: Part Two", link: "https://britishcinematographer.co.uk/greig-fraser-asc-acs-dune-part-two/"),
            (title: "Dune at the BAFTAs", link: "https://britishcinematographer.co.uk/dune-at-the-baftas/"),
        ], site: "BC", limit: 2, otherTitles: ["Dune: Part Two"], cinematographers: ["Greig Fraser"])
        XCTAssertEqual(other.decisions.map(\.rejected), [nil, .otherFilm, nil])
        // The same article at another address: once, and lending its name to the one kept.
        let aliased = CameraSources.aboutDecisions("F1", in: [
            (title: "F1 news", link: "https://theasc.com/article/f1-news/"),
            (title: "F1 premiere", link: "https://theasc.com/article/f1-premiere/"),
            (title: "F1 trailer notes", link: "https://theasc.com/article/f1-trailer-notes/"),
            (title: "The look of F1", link: "https://theasc.com/article/the-look-of-f1/"),
            (title: "Claudio Miranda, ASC: F1", link: "https://ascmag.com/articles/the-look-of-f1"),
        ], site: "AC", limit: 3, cinematographers: ["Claudio Miranda"])
        XCTAssertEqual(aliased.decisions.map(\.rejected), [nil, nil, .overLimit, nil, .duplicate])
        XCTAssertEqual(aliased.found.map(\.url.absoluteString).last, "https://theasc.com/article/the-look-of-f1/")
    }

    func testAWrongKindIsLeftOutWhateverItsTitle() async {
        StandInSite.reset()
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: DiscoveryFixtures.ascHits([
            ("F1 news", "https://theasc.com/article/f1-news/", "article"),
            ("F1 premiere", "https://theasc.com/article/f1-premiere/", "article"),
            ("F1 trailer notes", "https://theasc.com/article/f1-trailer-notes/", "article"),
            ("Claudio Miranda on F1", "https://theasc.com/video/claudio-miranda-on-f1/", "video"),
        ]))
        let found = await client().ascSearch(filmTitle: "F1", cinematographers: ["Claudio Miranda"])
        XCTAssertEqual(found.trace.hits.map(\.rejected), [nil, nil, nil, .wrongKind])
        XCTAssertEqual(found.found.count, 3)
    }
}
