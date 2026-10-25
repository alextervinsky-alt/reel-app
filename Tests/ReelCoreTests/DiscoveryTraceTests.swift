import XCTest
@testable import ReelCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension DiscoveryFixtures {
    // MARK: Drift (2019), shot by Mia Torvald: a common title, a round-up, a link that doesn't answer.

    static let driftGallery = page("Cannes 2019 Cinematography: Cameras and Lenses Used to Shoot 40 Films", [
        "Dir: Leo Brandt, DP: Mia Torvald Category: Competition",
        "Format: 35mm Camera: ARRICAM LT Lenses: Cooke S4/i",
        "The Look: Drift follows a ferry crossing in winter, and Torvald kept the camera on the deck throughout.",
        "Dir: Ana Other, DP: Ben Someone Category: Competition",
        "Format: ARRIRAW Camera: ALEXA Mini LF Lenses: Signature Primes",
        "The Look: The second film of the gallery is set in a desert, lit almost entirely by the sun.",
    ])

    static func drift() {
        StandInSite.reset()
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: ascHits([
            ("Drifting Away: A Profile", "https://theasc.com/article/drifting-away-a-profile/", "article"),
            ("Continental Drifts", "https://theasc.com/article/continental-drifts/", "post"),
        ]))
        StandInSite.route("britishcinematographer.co.uk", "wp-json/wp/v2/posts", body: "[]")
        StandInSite.route("en.wikipedia.org", "prop=extlinks", body: extlinks([
            "https://www.indiewire.com/gallery/cannes-2019-cameras-lenses-cinematography/",
            "https://www.ymcinema.com/2019/drift-torvald-interview/",
            "https://www.indiewire.com/",
            "https://variety.com/search/?q=drift",
            "https://deadline.com/category/film/",
            "mailto:press@example.com",
        ]))
        StandInSite.route("en.wikipedia.org", "prop=extracts", body: missingArticle)
        StandInSite.route("www.indiewire.com", "cannes-2019-cameras", body: driftGallery)
        StandInSite.routeFail("www.ymcinema.com", "drift-torvald-interview", code: -1001)
        StandInSite.route("www.kodak.com", "/drift/", status: 404, body: "<p>Not here</p>")
        StandInSite.route("nofilmschool.com", "drift-cinematography", status: 404, body: "<p>Not here</p>")
    }
}

/// Reel 1.10.0: the discovery trace records what each way of finding pages decided, from the
/// decisions themselves, and the reading log says it (DISCOVERY). The same fixtures as
/// `DiscoveryFunnelTests`, whose assertions (written before the trace) still hold unchanged.
final class DiscoveryTraceTests: XCTestCase {
    private func client() -> CameraSourcesClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StandInSite.self]
        return CameraSourcesClient(session: URLSession(configuration: config))
    }

    private func asked(_ host: String) -> [String] { StandInSite.asked(of: host).map(\.absoluteString).sorted() }

    private func details(_ id: Int, _ title: String, _ year: String, dp: String?) -> TMDBMovieDetails {
        var details = TMDBMovieDetails(id: id, title: title, releaseDate: year + "-01-01")
        details.credits = TMDBCredits(cast: [], crew: dp.map { [TMDBCrewMember(name: $0, job: "Director of Photography")] } ?? [])
        return details
    }

    /// The log's DISCOVERY section, without its heading.
    private func discovery(_ log: String) -> [String] {
        guard let start = log.range(of: "\nDISCOVERY (") else { return [] }
        return Array(log[start.upperBound...].split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
            .prefix { !$0.isEmpty }.map(String.init))
    }

    private func reasons(_ hits: [DiscoveryTrace.Hit]) -> [DiscoveryTrace.Rejection?] { hits.map(\.rejected) }

    func testEveryChannelTracedForAFilmWithSourcesEverywhere() async {
        DiscoveryFixtures.quietHarbour()
        let reading = await client().read(articleTitle: "The Quiet Harbour", filmTitle: "The Quiet Harbour", cinematographers: ["Jane Doe"],
                                          directors: ["Carl Example"], year: 2015, otherTitles: ["The Quiet Harbour II: Return"])
        guard let trace = reading.discovery else { return XCTFail("no trace") }
        // American Cinematographer: every result, in the site's order, as the filters decided.
        XCTAssertEqual(trace.searches.map(\.site), ["American Cinematographer", "British Cinematographer"])
        XCTAssertEqual(trace.searches[0].query, "The Quiet Harbour")
        XCTAssertEqual(trace.searches[0].outcome, .answered(7))
        XCTAssertEqual(reasons(trace.searches[0].hits), [nil, .wrongKind, .notAboutFilm, .otherFilm, nil, nil, .overLimit])
        // British Cinematographer.
        XCTAssertEqual(trace.searches[1].outcome, .answered(2))
        XCTAssertEqual(reasons(trace.searches[1].hits), [nil, .notAboutFilm])
        // Wikipedia's links, in the article's order.
        XCTAssertEqual(trace.cited?.outcome, .answered(7))
        XCTAssertEqual(trace.cited.map { reasons($0.links) }, [nil, nil, .newsNotCamera, .unlistedSite, .navigation, nil, nil])
        // Story guesses and the cinematographer.
        XCTAssertEqual(trace.guesses.map(\.result), [.found, .failed("gone: not found over HTTPS (404)"), .failed("gone: not found over HTTPS (404)")])
        XCTAssertNil(trace.guessesNotAttempted)
        XCTAssertEqual(trace.person, .found("Jane Doe", paragraphs: 1))
        // Assembly: what the channels kept became what was asked for.
        XCTAssertEqual(trace.assembly.candidates, 8)
        XCTAssertEqual(trace.assembly.foundTwice, ["https://theasc.com/article/night-lights-the-quiet-harbour/"])
        XCTAssertEqual(trace.assembly.otherAddresses, ["https://ascmag.com/articles/night-lights-the-quiet-harbour"])
        XCTAssertEqual(trace.assembly.overLimit, [])
        // What the trace says was asked for is what was asked for.
        let pagesAsked = Set(trace.assembly.asked)
        let actuallyAsked = Set((asked("theasc.com") + asked("britishcinematographer.co.uk") + asked("www.indiewire.com"))
            .filter { !$0.contains("wp-json") })
            .union(["https://www.kodak.com/en/motion/blog-post/the-quiet-harbour/"])
        XCTAssertEqual(pagesAsked, actuallyAsked)
        XCTAssertEqual(trace.assembly.asked.count, 6)
        // Read pages are among those asked for; nothing read that wasn't.
        XCTAssertTrue(Set(reading.sources.map(\.url.absoluteString)).isSubset(of: pagesAsked))
    }

    func testTheLogSaysHowPagesWereFound() async {
        DiscoveryFixtures.quietHarbour()
        let reading = await client().read(articleTitle: "The Quiet Harbour", filmTitle: "The Quiet Harbour", cinematographers: ["Jane Doe"],
                                          directors: ["Carl Example"], year: 2015, otherTitles: ["The Quiet Harbour II: Return"])
        let log = CraftReader.reading(of: details(31, "The Quiet Harbour", "2015", dp: "Jane Doe"), articleTitle: nil, article: nil,
                                      reading: reading, colour: nil).log
        XCTAssertTrue(log.contains("\n\nDISCOVERY (how pages were found; what was read is under READ, what wasn't under NOT READ)\n"), log)
        XCTAssertLessThan(log.range(of: "\nDISCOVERY (")!.lowerBound, log.range(of: "\nREAD\n")!.lowerBound, "before READ")
        XCTAssertEqual(discovery(log), [
            "• American Cinematographer search for “The Quiet Harbour”: 7 results; 3 kept (at most 3), 4 left out: 1 not an article, post or news item; 1 doesn't name the film in its title or address; 1 about another film of its collection; 1 over the limit",
            "  kept: Night Lights: The Quiet Harbour — https://theasc.com/article/night-lights-the-quiet-harbour/",
            "  kept: ASC Awards: The Quiet Harbour Honoured — https://theasc.com/news/asc-awards-the-quiet-harbour/",
            "  kept: Shooting The Quiet Harbour — https://theasc.com/article/shooting-the-quiet-harbour/",
            "  left out (not an article, post or news item): The Quiet Harbour trailer — https://theasc.com/video/the-quiet-harbour-trailer/",
            "  left out (doesn't name the film in its title or address): Harbour Lights of the Silent Era — https://theasc.com/article/harbour-lights-silent-era/",
            "  left out (about another film of its collection): The Quiet Harbour II: Return — https://theasc.com/article/the-quiet-harbour-ii-return/",
            "  left out (over the limit): The Quiet Harbour Revisited — https://theasc.com/article/the-quiet-harbour-revisited/",
            "• British Cinematographer search for “The Quiet Harbour”: 2 results; 1 kept (at most 2), 1 left out: 1 doesn't name the film in its title or address",
            "  kept: Jane Doe / The Quiet Harbour — https://britishcinematographer.co.uk/jane-doe-the-quiet-harbour/",
            "  left out (doesn't name the film in its title or address): Lighting the night — https://britishcinematographer.co.uk/lighting-the-night/",
            "• Wikipedia's cited links: 7 links; 4 kept (at most 8), 3 left out: 1 a front, tag, search or category page; 1 not a site Reel reads; 1 a news page not about the camera work",
            "  kept: https://ascmag.com/articles/night-lights-the-quiet-harbour",
            "  kept: http://www.indiewire.com/2015/05/the-quiet-harbour-jane-doe-cinematography-interview-1201/",
            "  kept: https://theasc.com/article/night-lights-the-quiet-harbour/",
            "  kept: https://www.kodak.com/en/motion/blog-post/the-quiet-harbour/",
            "  left out (a front, tag, search or category page): https://www.indiewire.com/tag/the-quiet-harbour/",
            "  left out (not a site Reel reads): https://www.boxofficemojo.com/release/rl1/",
            "  left out (a news page not about the camera work): https://variety.com/2015/film/news/the-quiet-harbour-box-office-1201/",
            "• Story pages (Kodak, No Film School), guessed from the title:",
            "  Kodak: https://www.kodak.com/en/motion/blog-post/the-quiet-harbour/ — found, and it names the cinematographer",
            "  Kodak: https://www.kodak.com/en/motion/page/the-quiet-harbour/ — gone: not found over HTTPS (404)",
            "  No Film School: https://nofilmschool.com/the-quiet-harbour-cinematography — gone: not found over HTTPS (404)",
            "• The cinematographer's Wikipedia article: Jane Doe — 1 paragraph naming the film, read with the rest",
            "• Pages: 8 kept above; 1 found twice, asked for once; 1 another address of an article kept (under NOT READ); 6 asked for; at most 6 read (see READ and NOT READ)",
        ])
        // The sections that were there before say what they said.
        XCTAssertTrue(log.contains("\nNOT READ\n• American Cinematographer: "), log)
        XCTAssertTrue(log.contains(" — too little text to read\n  https://theasc.com/news/asc-awards-the-quiet-harbour/"), log)
    }

    func testTheLimitsAreSaidAsLimits() async {
        DiscoveryFixtures.lanternBay()
        let reading = await client().read(articleTitle: "Lantern Bay", filmTitle: "Lantern Bay", cinematographers: ["Ann Sample"], directors: [], year: 2018)
        guard let trace = reading.discovery else { return XCTFail("no trace") }
        XCTAssertEqual(reasons(trace.searches[0].hits), [nil, nil, nil, .overLimit])
        XCTAssertEqual(reasons(trace.searches[1].hits), [nil, nil, .overLimit])
        XCTAssertEqual(trace.cited?.outcome, .answered(10))
        XCTAssertEqual(trace.cited.map { reasons($0.links) }, Array(repeating: nil, count: 8) + [.overLimit, .overLimit])
        XCTAssertEqual(trace.assembly.candidates, 13)
        XCTAssertEqual(trace.assembly.asked.count, 8)
        XCTAssertEqual(trace.assembly.overLimit, (4...8).map { "https://www.ymcinema.com/2018/lantern-bay-ann-sample-\($0)/" },
                       "not asked for: over the limit, not left out as irrelevant")
        XCTAssertEqual(asked("www.ymcinema.com"), (1...3).map { "https://www.ymcinema.com/2018/lantern-bay-ann-sample-\($0)/" })
        XCTAssertEqual(trace.person, .found("Ann Sample", paragraphs: 0))
        let log = CraftReader.reading(of: details(32, "Lantern Bay", "2018", dp: "Ann Sample"), articleTitle: nil, article: nil,
                                      reading: reading, colour: nil).log
        let lines = discovery(log)
        XCTAssertTrue(lines.contains("• Pages: 13 kept above; 8 asked for; 5 not asked for, over the limit of 8; at most 6 read (see READ and NOT READ)"), "\(lines)")
        XCTAssertTrue(lines.contains("  not asked for (over the limit): https://www.ymcinema.com/2018/lantern-bay-ann-sample-4/"))
        XCTAssertTrue(lines.contains("• The cinematographer's Wikipedia article: Ann Sample — no paragraph names the film"))
        XCTAssertTrue(log.contains("six sources were already read"), "the read limit, as before, under NOT READ")
    }

    func testNothingFoundIsSaidChannelByChannel() async {
        DiscoveryFixtures.paperMoonRoad()
        let reading = await client().read(articleTitle: nil, filmTitle: "Paper Moon Road", cinematographers: [], directors: [], year: 2001)
        guard let trace = reading.discovery else { return XCTFail("no trace") }
        XCTAssertEqual(trace.searches[0].outcome, .answered(0), "answered, with nothing")
        XCTAssertEqual(trace.searches[1].outcome, .failed("didn't answer: timed out (read again later)"), "didn't answer: not \"no results\"")
        XCTAssertEqual(trace.cited?.outcome, .notAttempted("no Wikipedia article for the film"))
        XCTAssertEqual(trace.guessesNotAttempted, "no cinematographer known (a page is kept only when it names them)")
        XCTAssertEqual(trace.person, .notAttempted("no cinematographer known"))
        let log = CraftReader.reading(of: details(33, "Paper Moon Road", "2001", dp: nil), articleTitle: nil, article: nil,
                                      reading: reading, colour: nil).log
        XCTAssertEqual(discovery(log), [
            "• American Cinematographer search for “Paper Moon Road”: no results",
            "• British Cinematographer search for “Paper Moon Road”: didn't answer: timed out (read again later)",
            "• Wikipedia's cited links: not tried: no Wikipedia article for the film",
            "• Story pages (Kodak, No Film School): not tried: no cinematographer known (a page is kept only when it names them)",
            "• The cinematographer's Wikipedia article: not looked up: no cinematographer known",
            "• Pages: 0 kept above; 0 asked for; at most 6 read (see READ and NOT READ)",
        ])
    }

    func testAPageInPlaceOfResultsNoArticleAndANamesake() async {
        DiscoveryFixtures.saltFlats()
        let reading = await client().read(articleTitle: "Salt Flats", filmTitle: "Salt Flats", cinematographers: ["Bob Plain"], directors: [], year: 2010)
        guard let trace = reading.discovery else { return XCTFail("no trace") }
        XCTAssertEqual(trace.searches[0].outcome, .notASearchAnswer)
        XCTAssertEqual(trace.searches[1].outcome, .answered(0))
        XCTAssertEqual(trace.cited?.outcome, .answeredNone("Wikipedia has no article of that title now"))
        XCTAssertEqual(trace.guesses.count, 3)
        XCTAssertTrue(trace.guesses.allSatisfy { $0.result == .failed("gone: not found over HTTPS (404)") })
        XCTAssertEqual(trace.person, .notACinematographer("Bob Plain"))
        let lines = DiscoveryTrace.describe(.notASearchAnswer, kept: [], limit: 3)
        XCTAssertEqual(lines, "answered with a page, not search results (read again later)")
    }

    /// A common one-word title, a round-up found through Wikipedia's links, pages that aren't
    /// articles, a link that doesn't answer, and no article for the cinematographer.
    func testACommonTitleARoundUpAndALinkThatDidntAnswer() async {
        DiscoveryFixtures.drift()
        let reading = await client().read(articleTitle: "Drift (2019 film)", filmTitle: "Drift", cinematographers: ["Mia Torvald"],
                                          directors: ["Leo Brandt"], year: 2019)
        guard let trace = reading.discovery else { return XCTFail("no trace") }
        // The search answered; nothing in it was about the film.
        XCTAssertEqual(trace.searches[0].outcome, .answered(2))
        XCTAssertEqual(reasons(trace.searches[0].hits), [.notAboutFilm, .notAboutFilm])
        XCTAssertEqual(trace.searches[1].outcome, .answered(0))
        // Wikipedia's links: the round-up and the interview kept; navigation and a non-address not.
        XCTAssertEqual(trace.cited.map { reasons($0.links) }, [nil, nil, .navigation, .navigation, .navigation, .notAnAddress])
        XCTAssertEqual(asked("variety.com") + asked("deadline.com"), [], "left out before asking")
        XCTAssertEqual(asked("www.indiewire.com"), ["https://www.indiewire.com/gallery/cannes-2019-cameras-lenses-cinematography/"])
        // Asked for in pick's order (craft sites first), the round-up read, the interview didn't answer.
        XCTAssertEqual(trace.assembly.asked, ["https://www.ymcinema.com/2019/drift-torvald-interview/",
                                              "https://www.indiewire.com/gallery/cannes-2019-cameras-lenses-cinematography/"])
        XCTAssertEqual(reading.sources.map(\.url.absoluteString), ["https://www.indiewire.com/gallery/cannes-2019-cameras-lenses-cinematography/"])
        XCTAssertEqual(reading.unanswered, ["Y.M.Cinema"])
        XCTAssertEqual(reading.skipped.first?.limit, .unanswered)
        XCTAssertEqual(trace.person, .noArticle("Mia Torvald"))
        XCTAssertEqual(trace.guesses.map(\.result), Array(repeating: .failed("gone: not found over HTTPS (404)"), count: 3))
        // What the reading comes to: the round-up read for its own entry only.
        let index = CraftReader.reading(of: details(34, "Drift", "2019", dp: "Mia Torvald"), articleTitle: nil, article: nil,
                                        reading: reading, colour: nil).index
        XCTAssertEqual(index.shotOn, [.film])
        XCTAssertFalse(index.names.contains { $0.lowercased().contains("alexa") }, "\(index.names)")
        XCTAssertEqual(index.coverage, .partial, "the interview didn't answer: read again later")
    }

    /// Many results of one reason: a few examples and a count, not every address.
    func testLargeGroupsAreShortened() {
        let hits = (1...12).map { DiscoveryTrace.Hit(title: "", url: "https://example.org/\($0)", rejected: .unlistedSite) }
        let lines = DiscoveryTrace.hitLines(hits, titled: false)
        XCTAssertEqual(lines.count, DiscoveryTrace.examples + 1)
        XCTAssertEqual(lines.last, "  … and 7 more not a site Reel reads")
        var cited = DiscoveryTrace.Cited(outcome: .answered(500), requestLimit: 500, limit: 8)
        cited.links = hits
        var trace = DiscoveryTrace()
        trace.cited = cited
        XCTAssertTrue(trace.lines().contains { $0.hasSuffix("(Reel asks for at most 500; the article may cite more)") })
    }

    /// The filters say what they decided; what they return is what they returned before.
    func testTheFiltersDecisionsAreTheirOwn() {
        let links = ["https://theasc.com/article/a-film-jane-doe/", "https://example.org/2015/05/a-film-review/", "https://www.indiewire.com/tag/x/"]
        let both = CameraSources.pickDecisions(links, cinematographers: ["Jane Doe"])
        XCTAssertEqual(both.picked.map(\.url), CameraSources.pick(links, cinematographers: ["Jane Doe"]).map(\.url))
        XCTAssertEqual(both.decisions.map(\.rejected), [nil, .unlistedSite, .navigation])
        let hits = [(title: "A Film", link: "https://theasc.com/article/a-film/"), (title: "Other", link: "https://theasc.com/article/other/")]
        let about = CameraSources.aboutDecisions("A Film", in: hits, site: "American Cinematographer", limit: 3)
        XCTAssertEqual(about.found.map(\.url), CameraSources.about("A Film", in: hits, site: "American Cinematographer", limit: 3).map(\.url))
        XCTAssertEqual(about.decisions.map(\.rejected), [nil, .notAboutFilm])
    }

    /// Discovery 3: the thin readings and collection films are read again, the rest aren't.
    func testDiscoveryThreeReadsAgainOnlyThinReadingsAndCollectionFilms() {
        XCTAssertEqual(CraftIndex.currentDiscovery, 3)
        XCTAssertEqual(CraftIndex.currentVersion, 11, "no rule changed")
        let now = Date()
        func reading(sources: Int, tags: [ShotOn]) -> CraftIndex {
            var index = CraftIndex(version: 11, readAt: now, shotOn: tags, names: [], sources: sources)
            index.discovery = 2
            return index
        }
        let wikipediaOnly = reading(sources: 1, tags: [.film]), untagged = reading(sources: 4, tags: []), full = reading(sources: 4, tags: [.film])
        XCTAssertEqual(CraftQueue.state(craft: wikipediaOnly, attempt: nil, hasFacts: true, inCollection: false, now: now), .stale)
        XCTAssertEqual(CraftQueue.state(craft: untagged, attempt: nil, hasFacts: true, inCollection: false, now: now), .stale)
        XCTAssertEqual(CraftQueue.state(craft: full, attempt: nil, hasFacts: true, inCollection: false, now: now), .complete)
        XCTAssertEqual(CraftQueue.state(craft: full, attempt: nil, hasFacts: true, inCollection: true, now: now), .stale, "a collection's films too")
    }
}
