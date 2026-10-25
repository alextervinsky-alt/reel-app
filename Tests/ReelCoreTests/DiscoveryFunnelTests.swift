import XCTest
@testable import ReelCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Recorded-shape answers for the discovery funnel: the two magazines' search APIs, Wikipedia's
/// external links and extracts, and the pages themselves. Made-up films, people and pages; the
/// response shapes are the sites' own.
enum DiscoveryFixtures {
    static func page(_ title: String, _ paragraphs: [String]) -> String {
        "<html><head><title>\(title)</title></head><body>" + paragraphs.map { "<p>\($0)</p>" }.joined() + "</body></html>"
    }

    static func json(_ object: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), encoding: .utf8)!
    }

    static func ascHits(_ hits: [(title: String, url: String, subtype: String)]) -> String {
        json(hits.map { ["title": $0.title, "url": $0.url, "subtype": $0.subtype] })
    }

    static func bcHits(_ hits: [(title: String, link: String)]) -> String {
        json(hits.map { ["title": ["rendered": $0.title], "link": $0.link] })
    }

    static func extlinks(_ links: [String]) -> String {
        json(["query": ["pages": ["101": ["extlinks": links.map { ["*": $0] }]]]])
    }

    static let missingArticle = #"{"query":{"pages":{"-1":{"missing":""}}}}"#

    static func extract(_ text: String) -> String {
        json(["query": ["pages": ["202": ["extract": text]]]])
    }

    // MARK: The Quiet Harbour (2015), shot by Jane Doe for Carl Example: every channel finds something.

    static let ascSearch = ascHits([
        ("Night Lights: The Quiet Harbour", "https://theasc.com/article/night-lights-the-quiet-harbour/", "article"),
        ("The Quiet Harbour trailer", "https://theasc.com/video/the-quiet-harbour-trailer/", "video"),
        ("Harbour Lights of the Silent Era", "https://theasc.com/article/harbour-lights-silent-era/", "article"),
        ("The Quiet Harbour II: Return", "https://theasc.com/article/the-quiet-harbour-ii-return/", "post"),
        ("ASC Awards: The Quiet Harbour Honoured", "https://theasc.com/news/asc-awards-the-quiet-harbour/", "news"),
        ("Shooting The Quiet Harbour", "https://theasc.com/article/shooting-the-quiet-harbour/", "article"),
        ("The Quiet Harbour Revisited", "https://theasc.com/article/the-quiet-harbour-revisited/", "post"),
    ])

    static let ascArticle = page("Night Lights", [
        "Jane Doe shot The Quiet Harbour on Kodak 5219 with Panaflex cameras, mostly at night on the harbour wall.",
        "Carl Example wanted the town to feel asleep, so Doe lit the streets with sodium vapour practicals only.",
        "The crew built a long dolly track along the quay for the opening shot, which runs for nearly four minutes.",
    ])

    static let ascAwards = page("ASC Awards", [
        "Jane Doe was honoured for The Quiet Harbour at this year's awards, alongside four other nominees.",
    ])

    static let ascOtherFilm = page("Shooting The Quiet Harbour", [
        "This The Quiet Harbour is a 1962 television play, shot in a London studio on live multi-camera video.",
        "Its director worked with a small crew and a single boom microphone for the whole live broadcast.",
        "Only one recording of the broadcast survives, kept at the national archive in a restored copy.",
    ])

    static let bcSearch = bcHits([
        ("Jane Doe / The Quiet Harbour", "https://britishcinematographer.co.uk/jane-doe-the-quiet-harbour/"),
        ("Lighting the night", "https://britishcinematographer.co.uk/lighting-the-night/"),
    ])

    static let bcArticle = page("Jane Doe / The Quiet Harbour", [
        "Doe used Cooke anamorphic/i lenses on The Quiet Harbour, choosing them for the way they render the harbour lights.",
        "We lit the interiors with practicals and a single soft source bounced off the ceiling of each room.",
        "Carl Example and Doe storyboarded the night sequences together in the months before the shoot began.",
    ])

    static let citedLinks = extlinks([
        "https://ascmag.com/articles/night-lights-the-quiet-harbour",
        "http://www.indiewire.com/2015/05/the-quiet-harbour-jane-doe-cinematography-interview-1201/",
        "https://variety.com/2015/film/news/the-quiet-harbour-box-office-1201/",
        "https://www.boxofficemojo.com/release/rl1/",
        "https://www.indiewire.com/tag/the-quiet-harbour/",
        "https://theasc.com/article/night-lights-the-quiet-harbour/",
        "https://www.kodak.com/en/motion/blog-post/the-quiet-harbour/",
    ])

    static let indiewire = page("Jane Doe on The Quiet Harbour", [
        "Doe says the harbour itself became the main light source, with the boats' lamps doing much of the work at night.",
        "She and Carl Example tested several film stocks before deciding on a single stock for the whole film.",
        "The shoot lasted forty days, nearly all of them at night, on the real quay rather than on a stage.",
    ])

    static let kodak = page("The Quiet Harbour", [
        "Cinematographer Jane Doe captured The Quiet Harbour on KODAK VISION3 500T 5219 35mm film for every night scene.",
        "Doe says the stock's latitude let her hold detail in the harbour's darkest corners without extra light.",
        "The negative was processed at a lab in London, and dailies were viewed on film each evening.",
    ])

    static let person = extract("Jane Doe is an English cinematographer known for her night work.\nShe shot The Quiet Harbour for Carl Example, on 35mm film through a long night shoot on the coast.\nHer later work includes television.")

    /// Every site of The Quiet Harbour answering as above.
    static func quietHarbour() {
        StandInSite.reset()
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: ascSearch)
        StandInSite.route("theasc.com", "night-lights-the-quiet-harbour", body: ascArticle)
        StandInSite.route("theasc.com", "asc-awards-the-quiet-harbour", body: ascAwards)
        StandInSite.route("theasc.com", "shooting-the-quiet-harbour", body: ascOtherFilm)
        StandInSite.route("britishcinematographer.co.uk", "wp-json/wp/v2/posts", body: bcSearch)
        StandInSite.route("britishcinematographer.co.uk", "jane-doe-the-quiet-harbour", body: bcArticle)
        StandInSite.route("en.wikipedia.org", "prop=extlinks", body: citedLinks)
        StandInSite.route("en.wikipedia.org", "prop=extracts", body: person)
        StandInSite.route("www.indiewire.com", "the-quiet-harbour-jane-doe", body: indiewire)
        StandInSite.route("www.kodak.com", "blog-post/the-quiet-harbour", body: kodak)
        StandInSite.route("www.kodak.com", "page/the-quiet-harbour", status: 404, body: "<p>Not here</p>")
        StandInSite.route("nofilmschool.com", "the-quiet-harbour-cinematography", status: 404, body: "<p>Not here</p>")
    }

    // MARK: Lantern Bay (2018), shot by Ann Sample: more found than the limits let through.

    static func lanternBay() {
        StandInSite.reset()
        let article = { (n: Int) in
            page("Lantern Bay \(n)", [
                "Ann Sample shot Lantern Bay on the Sony Venice 2, part \(n) of the magazine's coverage of the film.",
                "Sample says the bay's lighthouse was the key light for most of the night exteriors, part \(n).",
                "The production spent a week in tests before the shoot began in the spring, part \(n) of the series.",
            ])
        }
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: ascHits((1...4).map {
            ("Lantern Bay, part \($0)", "https://theasc.com/article/lantern-bay-part-\($0)/", "article")
        }))
        for n in 1...4 { StandInSite.route("theasc.com", "lantern-bay-part-\(n)/", body: article(n)) }
        StandInSite.route("britishcinematographer.co.uk", "wp-json/wp/v2/posts", body: bcHits((1...3).map {
            ("Lantern Bay \($0)", "https://britishcinematographer.co.uk/lantern-bay-\($0)/")
        }))
        for n in 1...3 { StandInSite.route("britishcinematographer.co.uk", "lantern-bay-\(n)/", body: article(10 + n)) }
        StandInSite.route("en.wikipedia.org", "prop=extlinks", body: extlinks((1...10).map {
            "https://www.ymcinema.com/2018/lantern-bay-ann-sample-\($0)/"
        }))
        StandInSite.route("en.wikipedia.org", "prop=extracts", body: extract("Ann Sample is a Danish cinematographer and photographer.\nShe works mostly in commercials and music videos across Europe."))
        for n in 1...10 { StandInSite.route("www.ymcinema.com", "lantern-bay-ann-sample-\(n)/", body: article(20 + n)) }
        StandInSite.route("www.kodak.com", "lantern-bay", status: 404, body: "<p>Not here</p>")
        StandInSite.route("nofilmschool.com", "lantern-bay", status: 404, body: "<p>Not here</p>")
    }

    // MARK: Paper Moon Road: no article, no cinematographer; one search empty, the other down.

    static func paperMoonRoad() {
        StandInSite.reset()
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: "[]")
        StandInSite.routeFail("britishcinematographer.co.uk", "wp-json/wp/v2/posts", code: -1001)
    }

    // MARK: Salt Flats: a search answering with a page, an article with no links, a namesake.

    static func saltFlats() {
        StandInSite.reset()
        StandInSite.route("theasc.com", "wp-json/wp/v2/search", body: "<html><body><p>Welcome to the magazine. Find our latest issues and events below.</p></body></html>")
        StandInSite.route("britishcinematographer.co.uk", "wp-json/wp/v2/posts", body: "[]")
        StandInSite.route("en.wikipedia.org", "prop=extlinks", body: missingArticle)
        StandInSite.route("en.wikipedia.org", "prop=extracts", body: extract("Bob Plain is an English footballer and later a youth coach.\nHe played for several clubs on the south coast in the 1990s."))
        StandInSite.route("www.kodak.com", "salt-flats", status: 404, body: "<p>Not here</p>")
        StandInSite.route("nofilmschool.com", "salt-flats", status: 404, body: "<p>Not here</p>")
    }
}

/// What the discovery funnel decides, for fixed answers: what's asked for, found, read and left out.
/// Written against 1.9.9's discovery before the trace was added, and run unchanged after it, so they
/// show the trace changes no decision.
final class DiscoveryFunnelTests: XCTestCase {
    private func client() -> CameraSourcesClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StandInSite.self]
        return CameraSourcesClient(session: URLSession(configuration: config))
    }

    private func asked(_ host: String) -> [String] {
        StandInSite.asked(of: host).map { $0.absoluteString }.sorted()
    }

    func testEveryChannelsDecisionsForAFilmWithSourcesEverywhere() async {
        DiscoveryFixtures.quietHarbour()
        let reading = await client().read(articleTitle: "The Quiet Harbour", filmTitle: "The Quiet Harbour", cinematographers: ["Jane Doe"],
                                          directors: ["Carl Example"], year: 2015, otherTitles: ["The Quiet Harbour II: Return"])
        // Read, in order.
        XCTAssertEqual(reading.sources.map(\.url.absoluteString), [
            "https://theasc.com/article/night-lights-the-quiet-harbour/",
            "https://britishcinematographer.co.uk/jane-doe-the-quiet-harbour/",
            "https://www.kodak.com/en/motion/blog-post/the-quiet-harbour/",
            "https://www.indiewire.com/2015/05/the-quiet-harbour-jane-doe-cinematography-interview-1201/",
        ])
        XCTAssertEqual(reading.sources.last?.cited?.absoluteString,
                       "http://www.indiewire.com/2015/05/the-quiet-harbour-jane-doe-cinematography-interview-1201/")
        // Not read, and why.
        XCTAssertEqual(reading.skipped.map { $0.source.url.absoluteString }, [
            "https://theasc.com/news/asc-awards-the-quiet-harbour/",
            "https://theasc.com/article/shooting-the-quiet-harbour/",
            "https://ascmag.com/articles/night-lights-the-quiet-harbour",
        ])
        XCTAssertEqual(reading.skipped.map(\.reason), [
            "too little text to read",
            "another film of that title: it doesn't name the film's cinematographer, director or year",
            "the same article as https://theasc.com/article/night-lights-the-quiet-harbour/, which was read",
        ])
        XCTAssertEqual(reading.skipped.map(\.limit), [.thin, nil, nil])
        XCTAssertEqual(reading.more.map(\.url.absoluteString), ["https://theasc.com/news/asc-awards-the-quiet-harbour/"])
        XCTAssertEqual(reading.unanswered, [])
        XCTAssertEqual(reading.cinematographer?.aboutThisFilm.count, 1)
        // What was asked for, site by site (in parallel, so as sets).
        XCTAssertEqual(asked("theasc.com").count, 4, "\(asked("theasc.com"))")
        XCTAssertTrue(asked("theasc.com").contains { $0.contains("wp-json/wp/v2/search") && $0.contains("search=The%20Quiet%20Harbour") },
                      "the query is the title")
        XCTAssertEqual(asked("ascmag.com"), [])
        XCTAssertEqual(asked("britishcinematographer.co.uk").count, 2)
        XCTAssertEqual(asked("en.wikipedia.org").count, 2)
        XCTAssertEqual(asked("www.kodak.com"), [
            "https://www.kodak.com/en/motion/blog-post/the-quiet-harbour/",
            "https://www.kodak.com/en/motion/blog-post/the-quiet-harbour/",
            "https://www.kodak.com/en/motion/page/the-quiet-harbour/",
        ], "the story guess and the cited link are each asked for")
        XCTAssertEqual(asked("nofilmschool.com"), ["https://nofilmschool.com/the-quiet-harbour-cinematography"])
        XCTAssertEqual(asked("www.indiewire.com").count, 1)
        XCTAssertEqual(asked("variety.com") + asked("www.boxofficemojo.com"), [])
        // What it all comes to.
        var details = TMDBMovieDetails(id: 31, title: "The Quiet Harbour", releaseDate: "2015-01-01")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Jane Doe", job: "Director of Photography"),
                                                       TMDBCrewMember(name: "Carl Example", job: "Director")])
        let index = CraftReader.reading(of: details, articleTitle: nil, article: nil, reading: reading, colour: nil).index
        XCTAssertEqual(Set(index.shotOn), [.film, .anamorphic])
        XCTAssertEqual(index.evidence(for: .film)?.source, "American Cinematographer")
        XCTAssertEqual(index.sources, 5, "four pages and the cinematographer's article")
        XCTAssertEqual(index.coverage, .limited, "the awards page was too thin")
    }

    func testTheLimitsOnWhatsFoundAskedForAndRead() async {
        DiscoveryFixtures.lanternBay()
        let reading = await client().read(articleTitle: "Lantern Bay", filmTitle: "Lantern Bay", cinematographers: ["Ann Sample"],
                                          directors: [], year: 2018)
        // Three of four from American Cinematographer, two of three from British Cinematographer,
        // eight of ten of Wikipedia's links; eight asked for, six read.
        XCTAssertEqual(asked("theasc.com").filter { !$0.contains("wp-json") }, (1...3).map { "https://theasc.com/article/lantern-bay-part-\($0)/" })
        XCTAssertEqual(asked("britishcinematographer.co.uk").filter { !$0.contains("wp-json") },
                       (1...2).map { "https://britishcinematographer.co.uk/lantern-bay-\($0)/" })
        XCTAssertEqual(asked("www.ymcinema.com"), (1...3).map { "https://www.ymcinema.com/2018/lantern-bay-ann-sample-\($0)/" })
        XCTAssertEqual(reading.sources.count, 6)
        XCTAssertEqual(reading.sources.last?.url.absoluteString, "https://www.ymcinema.com/2018/lantern-bay-ann-sample-1/")
        XCTAssertEqual(reading.skipped.map(\.reason), ["six sources were already read", "six sources were already read"])
        XCTAssertEqual(reading.skipped.map(\.limit), [nil, nil])
        XCTAssertNil(reading.cinematographer?.aboutThisFilm.first, "the article doesn't name the film")
        XCTAssertEqual(reading.unanswered, [])
    }

    func testNothingFoundOneSearchEmptyTheOtherDown() async {
        DiscoveryFixtures.paperMoonRoad()
        let reading = await client().read(articleTitle: nil, filmTitle: "Paper Moon Road", cinematographers: [], directors: [], year: 2001)
        XCTAssertEqual(reading.sources, [])
        XCTAssertEqual(reading.skipped, [])
        XCTAssertEqual(reading.unanswered, ["British Cinematographer"])
        XCTAssertNil(reading.cinematographer)
        XCTAssertEqual(asked("en.wikipedia.org"), [], "no article to take links from, no cinematographer to look up")
        XCTAssertEqual(asked("www.kodak.com") + asked("nofilmschool.com"), [], "no story guesses without a cinematographer")
        XCTAssertEqual(asked("theasc.com").count, 1)
    }

    func testASearchAnsweredWithAPageAnArticleWithoutLinksAndANamesake() async {
        DiscoveryFixtures.saltFlats()
        let reading = await client().read(articleTitle: "Salt Flats", filmTitle: "Salt Flats", cinematographers: ["Bob Plain"], directors: [], year: 2010)
        XCTAssertEqual(reading.sources, [])
        XCTAssertEqual(reading.skipped, [])
        XCTAssertEqual(reading.unanswered, ["American Cinematographer"], "a page in place of the search: not \"nothing written\"")
        XCTAssertNil(reading.cinematographer, "a footballer of the same name isn't the cinematographer")
        XCTAssertEqual(asked("www.kodak.com").count, 2)
        XCTAssertEqual(asked("nofilmschool.com").count, 1)
    }
}
