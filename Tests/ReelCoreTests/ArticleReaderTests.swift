import XCTest
@testable import ReelCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reel 1.10.5: only the article's own paragraphs are read from a page. The pages are made up, but
/// shaped like the real ones: Definition's "You might also like" cards (whole `<article>`s nested in
/// the article), British Cinematographer's news ticker and post grid (Beaver Builder), American
/// Cinematographer's Elementor post content and related grid, Kodak's `<main>`, IndieWire's
/// unmarked blocks. No real page, title or person is used.
final class ArticleReaderTests: XCTestCase {
    static let teaser = "Sony’s new X-OCN format promises Raw image capture performance but at lower data rates."
    static let body = [
        "We might be deep into the digital age, but some of the year's most talked-about films were shot on celluloid.",
        "Jane Doe shot The Quiet Harbour on Kodak 35mm film, and the lab work was done photochemically in London.",
        "Labs report that demand for processing has grown every year since 2020, and stock prices have followed.",
    ]
    static func p(_ text: String) -> String { "<p>" + text + "</p>" }

    /// Definition: the cards are `<article>`s inside the article, each with its own excerpt, in
    /// containers named like the article's ("post-content", "entry-content").
    static func definitionPage(bodyExtra: [String] = []) -> String {
        """
        <!doctype html><html><head><title>Taking stock – Shooting on film | Lens Weekly</title>
        <link rel="canonical" href="https://lensweekly.example/features/taking-stock/" /></head>
        <body class="single has-sidebar"><header class="site-header"><nav><p>Home Features Reviews News Subscribe to the magazine today</p></nav></header>
        <section class="section container-single"><div class="wrapper flex">
        <main id="main" class="single-post-content bg-white">
        <article class="single-post"><h1>Taking stock – Shooting on film</h1>
        <section class="section text-editor-layout"><div class="wrapper content content-flow">
        \((body + bodyExtra).map(p).joined(separator: "\n"))
        </div></section>
        <section class="section"><h3>You might also like</h3><div class="grid">
          <article class="relative h-full"><div class="post-content h-full"><div class="item-content entry-content">
            <h4><a href="/features/raw-but-not-as-we-know-it/">Raw but not as we know it</a></h4>
            <div class="excerpt"><p>\(teaser)</p></div></div></div></article>
          <article class="relative h-full"><div class="post-content h-full"><div class="item-content entry-content">
            <h4><a href="/features/another/">Another feature</a></h4>
            <div class="excerpt"><p>In early 2019 a newsroom moved to large-format cameras for its documentaries, shot on the ARRI Alexa LF.</p></div></div></div></article>
        </div></section>
        </article></main></div></section>
        <footer><p>All rights reserved. Lens Weekly is published by a made-up company in a made-up town.</p></footer>
        </body></html>
        """
    }

    // MARK: A. Definition-style

    func testATeaserCardIsntTheArticle() {
        let article = ArticleReader.read(Self.definitionPage())
        XCTAssertEqual(article.paragraphs, Self.body)
        XCTAssertFalse(article.paragraphs.contains(Self.teaser))
        XCTAssertEqual(article.boundary, .container)
        XCTAssertEqual(article.leftOut, 3, "two teasers and the footer (the menu line is too short to be prose)")
        XCTAssertEqual(article.canonical?.absoluteString, "https://lensweekly.example/features/taking-stock/")
        XCTAssertEqual(HTMLText.title(Self.definitionPage()), "Taking stock – Shooting on film", "not the teaser's title")
        // What reaches the reading: no X-OCN, no Digital.
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: "Lens Weekly", paragraphs: article.paragraphs)],
                                   cinematographers: ["Jane Doe"], title: "The Quiet Harbour")
        XCTAssertFalse((specs.specs + specs.mentioned).contains { $0.name.contains("X-OCN") })
        XCTAssertEqual(CraftIndex.make(from: specs, colour: nil, keywords: []).shotOn, [.film])
    }

    /// The same sentence written in the article itself is the article's (whether it's this film's
    /// is for the reading to say).
    func testTheSameSentenceInTheArticleIsRead() {
        let article = ArticleReader.read(Self.definitionPage(bodyExtra: [Self.teaser]))
        XCTAssertEqual(article.paragraphs.last, Self.teaser)
        XCTAssertEqual(article.paragraphs.filter { $0 == Self.teaser }.count, 1)
    }

    // MARK: B. British Cinematographer-style

    func testANewsTickerAndPostGridArentTheInterview() {
        let ticker = "Sony launches Rialto 65 Camera Extension System, “expanding Venice 2 to 65mm format”"
        let grid = "Buy a subscription - still the best way to read the magazine in print and online every month."
        let interview = [
            "With over twenty years of experience as a cinematographer, Jane Doe has built a reputation for bold work.",
            "“We shot The Quiet Harbour on the ARRI Alexa 35 with Cooke S4 lenses,” says Doe, “and lit from the water.”",
        ]
        let html = """
        <html><head><title>Jane Doe / The Quiet Harbour</title></head><body>
        <div class="fl-row"><div class="pp-content-ticker-wrap"><div class="pp-content-ticker swiper-container"><div class="swiper-wrapper">
          <div class="pp-content-ticker-item swiper-slide"><div class="pp-content-ticker-content"><div class="pp-content-ticker-item-title-wrap"><p>\(ticker)</p></div></div></div>
        </div></div></div></div>
        <div class="fl-module fl-module-rich-text"><div class="fl-module-content"><div class="fl-rich-text"><p>Home » Features » Production Profiles » Camera » Jane Doe / The Quiet Harbour</p></div></div></div>
        <div class="fl-col"><div class="fl-col-content"><h1>Jane Doe / The Quiet Harbour</h1>
          <div class="fl-module fl-module-fl-post-content bb-inner-content"><div class="fl-module-content">
          \(interview.map(Self.p).joined())
          <p>See <a href="https://lensweekly.example/kit">the kit list</a> for every lens and filter that went out on the truck each morning.</p>
          </div></div></div></div>
        <div class="fl-post-grid"><div class="fl-post-column"><div class="fl-post-grid-post"><div class="post-content"><p>\(grid)</p></div></div></div></div>
        </body></html>
        """
        let article = ArticleReader.read(html)
        XCTAssertEqual(article.boundary, .container)
        XCTAssertEqual(article.paragraphs, interview + ["See the kit list for every lens and filter that went out on the truck each morning."],
                       "a paragraph with a link is still the article's")
        XCTAssertFalse(article.paragraphs.contains(ticker))
        XCTAssertFalse(article.paragraphs.contains(grid))
    }

    // MARK: C. Structure

    func testTheMarkedArticleBodyComesFirst() {
        let html = "<html><body><div class=\"page\"><div itemprop=\"articleBody\">" + Self.body.map(Self.p).joined()
            + "</div><div class=\"also\">" + ["A longer piece of unrelated prose that is not the article, about something else entirely, goes on here.",
                                              "And another unrelated paragraph of prose that is not the article, about something else entirely."].map(Self.p).joined()
            + "</div></div></body></html>"
        let article = ArticleReader.read(html)
        XCTAssertEqual(article.boundary, .articleBody)
        XCTAssertEqual(article.paragraphs, Self.body)
    }

    func testOfSeveralArticlesTheOneWithTheHeadline() {
        let other = "An unrelated story about a festival line-up, with a long excerpt that runs to several sentences of prose."
        let html = "<html><body><article><h2>Elsewhere</h2>" + Self.p(other) + "</article><article><h1>The piece</h1>"
            + Self.body.map(Self.p).joined() + "</article><article>" + Self.p(other + " Again.") + "</article></body></html>"
        let article = ArticleReader.read(html)
        XCTAssertEqual(article.boundary, .article)
        XCTAssertEqual(article.paragraphs, Self.body)
    }

    /// Two article bodies of like weight, no headline in either: no telling which. Nothing is read
    /// (not the whole page).
    func testTwoArticlesNoHeadlineIsNotRead() {
        let other = ["A different story entirely, of about the same length as the first, with prose in each of its paragraphs.",
                     "It goes on for another paragraph of similar prose, so neither article outweighs the other on the page.",
                     "And a third paragraph, to make the two articles carry the same weight of text on this page."]
        let html = "<html><body><article>" + Self.body.map(Self.p).joined() + "</article><article>" + other.map(Self.p).joined()
            + "</article></body></html>"
        let article = ArticleReader.read(html)
        XCTAssertNil(article.boundary)
        XCTAssertEqual(article.paragraphs, [])
        XCTAssertEqual(article.leftOut, 6)
    }

    func testMainWithAnAsideAndAKodakLikePage() {
        let html = "<html><body><header><p>Products Solutions Support About Contact the company directly here</p></header><main>"
            + "<div class=\"blog_matrix__block\"><div class=\"c_text\">" + Self.body.map(Self.p).joined() + "</div></div>"
            + "<aside><p>Related: the best stocks for night exteriors, a guide for cinematographers shooting this winter.</p></aside>"
            + "</main><footer><p>© 2026 A made-up company. All rights reserved. Terms of use and privacy.</p></footer></body></html>"
        let article = ArticleReader.read(html)
        XCTAssertEqual(article.boundary, .main)
        XCTAssertEqual(article.paragraphs, Self.body)
    }

    /// No marked container (hashed class names): the region holding the prose, without the
    /// newsletter box.
    func testAnUnmarkedPageIsReadFromItsProseRegion() {
        let html = "<html><body><div class=\"_main_10r4d_1\"><div class=\"_gutenbergContent_1njrp_1\"><div class=\"_inner_1njrp_1\">"
            + Self.body.map(Self.p).joined() + "</div></div></div>"
            + "<div class=\"_newsletter_ixyx8_1\"><div class=\"_right_ixyx8_1\"><p>Get the latest craft news in your inbox every week, from our editors and critics.</p></div></div>"
            + "</body></html>"
        let article = ArticleReader.read(html)
        XCTAssertEqual(article.boundary, .region)
        XCTAssertEqual(article.paragraphs, Self.body)
        XCTAssertEqual(article.leftOut, 1)
    }

    func testTwoRegionsOfLikeWeightAreNotRead() {
        let other = Self.body.map { $0.replacingOccurrences(of: "film", with: "story") }
        let html = "<html><body><div class=\"a\">" + Self.body.map(Self.p).joined() + "</div><div class=\"b\">"
            + other.map(Self.p).joined() + "</div></body></html>"
        XCTAssertNil(ArticleReader.read(html).boundary)
    }

    /// A round-up laid out as a list of entries, each its own `<article>` (IndieWire's festival
    /// galleries): the list is the article; the reading then keeps to this film's entry.
    func testARoundUpsEntriesAreReadAsOne() {
        let entries = [
            ("Dir: Carl Example DP: Jane Doe", "Format: 6.5K ARRIRAW Camera: ALEXA 65 and ALEXA Mini LF Lenses: Panavision Sphero 65"),
            ("Dir: Fay Example DP: Gus Sample", "Format: 35mm Camera: ARRICAM LT Lenses: Cooke Anamorphic/i"),
            ("Dir: Ann Example DP: Bob Sample", "Format: 4.5K ARRIRAW Camera: ALEXA LF Lenses: Zeiss Supreme Primes"),
        ]
        let items: [String] = entries.map { entry in
            "<li class=\"list-item\"><article class=\"list-entry\"><h2>A film</h2><p>" + entry.0 + "</p><p>" + entry.1 + "</p></article></li>"
        }
        // As on the real gallery, the intro and the list sit in a column named "_sidebar_…", which
        // holds most of the page's prose: the page's layout, not a sidebar beside the article.
        let intro = "<p>Once again we asked the cinematographers what they shot on, and here is the list they sent.</p>"
        let letter = "<div class=\"_newsletter_ixyx8_1\"><p>By providing your information, you agree to our terms of use and our privacy policy.</p></div>"
        let html: String = "<html><body><h1>Festival Cinematography: Cameras and Lenses Used to Shoot 3 Films</h1><div class=\"_sidebar_10r4d_1\">" + intro
            + "<ul class=\"gallery\">" + items.joined() + "</ul></div>" + letter + "</body></html>"
        let article = ArticleReader.read(html)
        XCTAssertEqual(article.boundary, .entries)
        let expected: [String] = entries.flatMap { entry in [entry.0, entry.1] }
        XCTAssertEqual(article.paragraphs, expected)
        // Cards: a row of short teasers beside an unmarked article are left out.
        let card = "<article class=\"card\"><h3>More</h3><p>Another story from the site, teased here in a single line of text for you.</p></article>"
        let cards: String = String(repeating: card, count: 3)
        let more: [String] = ["A fourth paragraph of the article itself, so the article holds most of the page's prose by far.",
                              "And a fifth paragraph of the article, for good measure, saying more about how it was all shot."]
        let articleBody: String = (Self.body + more).map(Self.p).joined()
        let page: String = "<html><body><h1>The piece</h1><div class=\"body\">" + articleBody + "</div><div class=\"more\">" + cards + "</div></body></html>"
        let read = ArticleReader.read(page)
        XCTAssertEqual(read.boundary, .region)
        XCTAssertEqual(read.paragraphs.count, 5)
        XCTAssertFalse(read.paragraphs.contains { $0.hasPrefix("Another story") })
    }

    /// A block named like a component is left out while it's beside the article (a sidebar of
    /// other stories); comments stay out even when they fill most of the page.
    func testASidebarBesideTheArticleAndLongCommentsStayOut() {
        let side = ["Most read this week: a round-up of the season's festival cameras, with every lens listed.",
                    "Also popular: how a documentary crew lit a whole night shoot with two practical lamps."]
        let page: String = "<html><body><h1>The piece</h1><div class=\"body\">" + Self.body.map(Self.p).joined()
            + "</div><div class=\"widget-sidebar\">" + side.map(Self.p).joined() + "</div></body></html>"
        let read = ArticleReader.read(page)
        XCTAssertEqual(read.paragraphs, Self.body)
        let comment = "I loved this piece, and I shot my own short on the ARRI Alexa 35 last year with a rented kit."
        let comments: String = String(repeating: Self.p(comment), count: 8)
        let commented: String = "<html><body><main><h1>The piece</h1><div class=\"body\">" + Self.body.map(Self.p).joined()
            + "</div><section id=\"comments\" class=\"comments-area\">" + comments + "</section></main></body></html>"
        let withComments = ArticleReader.read(commented)
        XCTAssertEqual(withComments.boundary, .main)
        XCTAssertEqual(withComments.paragraphs, Self.body)
    }

    func testQuotesCaptionsAndListsAndBrokenMarkup() {
        let quote = "“We wanted every night scene to feel like it was lit by the harbour itself,” Doe says of the look."
        // A pull quote is the article's; a caption under a photo is left out, as before.
        let html = "<html><body><article><h1>T</h1>" + Self.body.map(Self.p).joined() + "<blockquote><p>" + quote + "</p></blockquote>"
            + "<figure><img src=\"a.jpg\"><figcaption><p>Jane Doe on set with the ARRI Alexa 35 and a Cooke zoom at dawn by the water.</p></figcaption></figure>"
            + "</article></body></html>"
        let article = ArticleReader.read(html)
        XCTAssertEqual(article.paragraphs, Self.body + [quote])
        // Paragraphs never closed, a div left open, a page cut off mid-tag: still read.
        let broken = "<html><body><div class=\"entry-content\"><p>" + Self.body[0] + "<p>" + Self.body[1] + "<div><p>" + Self.body[2]
            + "</div><p>Cut off here, in the middle of a sentence that goes on for a while and then <a hr"
        let read = ArticleReader.read(broken)
        XCTAssertEqual(Array(read.paragraphs.prefix(3)), Self.body)
        XCTAssertEqual(read.boundary, .container)
    }

    /// A page with no prose at all is an empty article (too little text), not a page that couldn't
    /// be read; a plain page of paragraphs is read as it was.
    func testNoProseAndPlainPages() {
        let empty = ArticleReader.read("<html><body><p>Not here</p></body></html>")
        XCTAssertNotNil(empty.boundary)
        XCTAssertEqual(empty.paragraphs, [])
        let plain = ArticleReader.read("<html><body>" + Self.body.map(Self.p).joined() + "</body></html>")
        XCTAssertEqual(plain.paragraphs, Self.body)
        XCTAssertEqual(plain.leftOut, 0)
        XCTAssertEqual(HTMLText.paragraphs("<html><body>" + Self.body.map(Self.p).joined() + "</body></html>"), Self.body)
    }

    // MARK: D. Fails closed, through the client

    private func client() -> CameraSourcesClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StandInSite.self]
        return CameraSourcesClient(session: URLSession(configuration: config))
    }

    func testAPageWhoseArticleCantBeToldApartIsNotReadAndNotEmpty() async {
        StandInSite.reset()
        defer { StandInSite.reset() }
        let other = ["A different story entirely, of about the same length as the first, with prose in each of its paragraphs.",
                     "It goes on for another paragraph of similar prose, so neither article outweighs the other on the page.",
                     "And a third paragraph, to make the two articles carry the same weight of text on this page."]
        StandInSite.route("unbounded.example", "two", body: "<html><body><article>" + Self.body.map(Self.p).joined() + "</article><article>"
                          + other.map(Self.p).joined() + "</article></body></html>")
        StandInSite.route("unbounded.example", "one", body: Self.definitionPage())
        let got = await client().page(URL(string: "https://unbounded.example/two/")!, site: "Lens Weekly", title: nil)
        XCTAssertNil(got.source)
        XCTAssertEqual(got.failure, .restricted(CameraSources.unboundedArticle))
        XCTAssertEqual(got.failure?.limit, .restricted, "a limit: not complete with nothing found")
        XCTAssertFalse(got.failure?.retried ?? true, "not asked again on every pass")
        let read = await client().page(URL(string: "https://unbounded.example/one/")!, site: "Lens Weekly", title: nil)
        XCTAssertEqual(read.source?.paragraphs, Self.body)
        XCTAssertEqual(read.source?.boundary, .container)
        XCTAssertEqual(read.source?.leftOut, 3)
    }

    /// The log says how each article was found: by what, how many paragraphs were read and left
    /// out, and the address the page gives for itself when it isn't the one read.
    func testTheLogSaysHowTheArticleWasFound() throws {
        let article = ArticleReader.read(Self.definitionPage())
        var page = CameraReading.Source(title: "Taking stock – Shooting on film", site: "Lens Weekly",
                                        url: URL(string: "https://lensweekly.example/taking-stock/?ref=search")!, paragraphs: article.paragraphs)
        page.boundary = article.boundary
        page.leftOut = article.leftOut
        page.canonical = article.canonical
        let reading = CameraReading(sources: [page], more: [], cinematographer: nil, unanswered: [], skipped: [])
        let json = #"{"id": 78, "title": "The Quiet Harbour", "release_date": "2023-05-01", "credits": {"cast": [], "crew": [{"name": "Jane Doe", "job": "Director of Photography"}]}}"#
        let details = try JSONDecoder().decode(TMDBMovieDetails.self, from: Data(json.utf8))
        let evaluated = CraftReader.evaluate(details, article: nil, reading: reading, colour: nil, otherTitles: [], now: Date())
        let log = CraftLog.text(details: details, articleTitle: nil, articleRead: false, reading: reading, specs: evaluated.specs,
                                index: evaluated.index)
        XCTAssertTrue(log.contains("• Lens Weekly: Taking stock – Shooting on film (3 paragraphs)"), log)
        XCTAssertTrue(log.contains("article found by the site's article container; 3 paragraphs on the page left out as not the article's"), log)
        XCTAssertTrue(log.contains("the page gives its address as https://lensweekly.example/features/taking-stock/"), log)
        XCTAssertFalse(log.contains("X-OCN"), log)
    }

    // MARK: E. The finding a teaser made, corrected

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// 1.10.4 read the teaser and stored Digital (X-OCN) from it; read again by 1.10.5 the page's
    /// article is read without it: Digital, said only there, is dropped; Film stays.
    func testAFalseFindingFromATeaserIsDroppedWhenTheArticleIsReadAgain() {
        // 1. As 1.10.4 read the page: every paragraph, the teaser too.
        let everything = Self.body + [Self.teaser]
        let oldSpecs = TechSpecs.read(texts: [TechSpecs.Text(source: "Lens Weekly", paragraphs: everything),
                                              TechSpecs.Text(source: "Film Monthly", paragraphs: ["Jane Doe shot The Quiet Harbour on VistaVision, on Kodak film."])],
                                      cinematographers: ["Jane Doe"], title: "The Quiet Harbour")
        var old = CraftIndex.make(from: oldSpecs, colour: nil, keywords: [], now: start)
        old.version = 13
        old.read = ["Lens Weekly", "Film Monthly", "Wikipedia"]
        XCTAssertEqual(Set(old.shotOn), [.film, .digital], "the teaser's Digital, as 1.10.4 stored it")
        XCTAssertEqual(old.evidence(for: .digital)?.text, Self.teaser)
        // 2. Read again: the article without the teaser.
        let article = ArticleReader.read(Self.definitionPage())
        let newSpecs = TechSpecs.read(texts: [TechSpecs.Text(source: "Lens Weekly", paragraphs: article.paragraphs),
                                              TechSpecs.Text(source: "Film Monthly", paragraphs: ["Jane Doe shot The Quiet Harbour on VistaVision, on Kodak film."])],
                                      cinematographers: ["Jane Doe"], title: "The Quiet Harbour")
        var new = CraftIndex.make(from: newSpecs, colour: nil, keywords: [], now: start)
        new.read = ["Lens Weekly", "Film Monthly", "Wikipedia"]
        XCTAssertEqual(CraftQueue.state(craft: old, attempt: nil, hasFacts: true, inCollection: false, now: start), .olderRules)
        let merged = CraftIndex.merging(old: old, new: new, now: start)
        XCTAssertEqual(merged.index.shotOn, [.film])
        XCTAssertEqual(merged.dropped.map(\.reason), ["Lens Weekly was read again and, by rules \(CraftIndex.currentVersion), doesn't say so"])
        XCTAssertFalse(merged.index.names.contains { $0.contains("X-OCN") })
        // Read again once more: the same (idempotent).
        XCTAssertEqual(CraftIndex.merging(old: merged.index, new: new, now: start).index.shotOn, [.film])
        XCTAssertEqual(CraftIndex.merging(old: merged.index, new: new, now: start).dropped, [])
    }

    /// Another source that does say Digital keeps it, and the reason becomes that source's.
    func testAnIndependentSourceKeepsTheTag() {
        let old = CraftIndex(version: 13, readAt: start, shotOn: [.film, .digital], names: ["X-OCN"],
                             evidence: [CraftIndex.Evidence(shotOn: .film, text: "Jane Doe shot The Quiet Harbour on VistaVision.", source: "Film Monthly"),
                                        CraftIndex.Evidence(shotOn: .digital, text: Self.teaser, source: "Lens Weekly")],
                             sources: 3, read: ["Lens Weekly", "Film Monthly", "Wikipedia"])
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: "Lens Weekly", paragraphs: ArticleReader.read(Self.definitionPage()).paragraphs),
                                           TechSpecs.Text(source: "Film Monthly", paragraphs: ["Jane Doe shot The Quiet Harbour on VistaVision.",
                                                                                               "The night scenes were shot digitally on the Sony Venice 2."])],
                                   cinematographers: ["Jane Doe"], title: "The Quiet Harbour")
        var new = CraftIndex.make(from: specs, colour: nil, keywords: [], now: start)
        new.read = ["Lens Weekly", "Film Monthly", "Wikipedia"]
        let merged = CraftIndex.merging(old: old, new: new, now: start)
        XCTAssertTrue(merged.index.shotOn.contains(.digital))
        XCTAssertEqual(merged.index.evidence(for: .digital)?.source, "Film Monthly")
        XCTAssertTrue(merged.index.shotOn.contains(.film))
    }

    /// The source that said it didn't answer: the finding is kept (marked so) and read again; its
    /// article couldn't be told apart: kept too, for a few readings; another site's reading never
    /// takes it away.
    func testAFailedOrUnboundedSourceKeepsWhatItSaid() {
        let old = CraftIndex(version: 13, readAt: start, shotOn: [.film, .digital], names: [],
                             evidence: [CraftIndex.Evidence(shotOn: .film, text: "Jane Doe shot The Quiet Harbour on VistaVision.", source: "Film Monthly"),
                                        CraftIndex.Evidence(shotOn: .digital, text: "We shot it on the Sony Venice 2.", source: "Lens Weekly")],
                             sources: 3, read: ["Lens Weekly", "Film Monthly", "Wikipedia"])
        let filmOnly = CraftIndex.Evidence(shotOn: .film, text: "Jane Doe shot The Quiet Harbour on VistaVision.", source: "Film Monthly")
        // Lens Weekly didn't answer.
        let down = CraftIndex(readAt: start, shotOn: [.film], names: [], evidence: [filmOnly], sources: 2, read: ["Film Monthly", "Wikipedia"],
                              unanswered: ["Lens Weekly"])
        let kept = CraftIndex.merging(old: old, new: down, now: start)
        XCTAssertEqual(Set(kept.index.shotOn), [.film, .digital])
        XCTAssertEqual(kept.carried.first?.source, "Lens Weekly")
        XCTAssertNotNil(kept.index.retryAt)
        // Lens Weekly answered, but its article couldn't be told apart.
        var unbounded = CraftIndex(readAt: start, shotOn: [.film], names: [], evidence: [filmOnly], sources: 2, read: ["Film Monthly", "Wikipedia"])
        unbounded.limits = [CraftIndex.SourceLimit(site: "Lens Weekly", url: "https://lensweekly.example/a/", kind: .restricted,
                                                   detail: "not read: " + CameraSources.unboundedArticle)]
        var merged = CraftIndex.merging(old: old, new: unbounded, now: start)
        XCTAssertEqual(Set(merged.index.shotOn), [.film, .digital], "not a sign the tag is wrong")
        XCTAssertEqual(merged.carried.first?.misses, 1)
        XCTAssertTrue(CraftLog.stored(merged).contains("its article couldn't be told apart on Lens Weekly's page this time"))
        // …for a few readings, then the reading stands.
        for _ in 0..<CraftIndex.maxRetries { merged = CraftIndex.merging(old: merged.index, new: unbounded, now: start) }
        XCTAssertEqual(merged.index.shotOn, [.film])
        // Read again, and it doesn't say so: dropped.
        let reread = CraftIndex(readAt: start, shotOn: [.film], names: [], evidence: [filmOnly], sources: 3,
                                read: ["Lens Weekly", "Film Monthly", "Wikipedia"])
        XCTAssertEqual(CraftIndex.merging(old: old, new: reread, now: start).index.shotOn, [.film])
    }

    // MARK: Review round 1

    /// R1: one page of the site couldn't be told apart, another of its pages was read and doesn't
    /// say so: the page that said it may be the one not read, so the tag is carried, not dropped.
    func testAnotherPageOfTheSiteReadDoesntEraseWhatAnUnboundedPageSaid() {
        let old = CraftIndex(version: 13, readAt: start, shotOn: [.film, .digital], names: [],
                             evidence: [CraftIndex.Evidence(shotOn: .film, text: "Jane Doe shot The Quiet Harbour on VistaVision.", source: "Film Monthly"),
                                        CraftIndex.Evidence(shotOn: .digital, text: "We shot it on the Sony Venice 2.", source: "Lens Weekly")],
                             sources: 3, read: ["Lens Weekly", "Film Monthly", "Wikipedia"])
        let filmOnly = CraftIndex.Evidence(shotOn: .film, text: "Jane Doe shot The Quiet Harbour on VistaVision.", source: "Film Monthly")
        var new = CraftIndex(readAt: start, shotOn: [.film], names: [], evidence: [filmOnly], sources: 3,
                             read: ["Lens Weekly", "Film Monthly", "Wikipedia"])
        new.limits = [CraftIndex.SourceLimit(site: "Lens Weekly", url: "https://lensweekly.example/a/", kind: .restricted,
                                             detail: SourceFailure.restricted(CameraSources.unboundedArticle).reason)]
        var merged = CraftIndex.merging(old: old, new: new, now: start)
        XCTAssertEqual(Set(merged.index.shotOn), [.film, .digital])
        XCTAssertEqual(merged.index.evidence(for: .digital)?.source, "Lens Weekly")
        for _ in 0..<CraftIndex.maxRetries { merged = CraftIndex.merging(old: merged.index, new: new, now: start) }
        XCTAssertEqual(merged.index.shotOn, [.film])
        XCTAssertEqual(merged.dropped.map(\.reason), ["its article couldn't be told apart on Lens Weekly's page in \(CraftIndex.maxRetries) readings"])
        XCTAssertTrue(SourceFailure.restricted(CameraSources.unboundedArticle).reason.hasPrefix("not read: "), "not \"not open to Reel\"")
    }

    /// R2: a guessed story page (Kodak's) whose article can't be told apart is noted with the
    /// reading, as a limit, so the reading isn't "complete" and what Kodak said before is kept.
    func testAGuessedStoryThatCantBeToldApartIsNoted() async {
        StandInSite.reset()
        defer { StandInSite.reset() }
        let other = ["A different story entirely, of about the same length as the first, with prose in each of its paragraphs.",
                     "It goes on for another paragraph of similar prose, so neither article outweighs the other on the page.",
                     "And a third paragraph, to make the two articles carry the same weight of text on this page."]
        StandInSite.route("www.kodak.com", "blog-post/the-quiet-harbour", body: "<html><body><article>" + Self.body.map(Self.p).joined()
                          + "</article><article>" + other.map(Self.p).joined() + "</article></body></html>")
        StandInSite.route("www.kodak.com", "page/the-quiet-harbour", status: 404, body: "<p>Not here</p>")
        StandInSite.route("nofilmschool.com", "the-quiet-harbour", status: 404, body: "<p>Not here</p>")
        let stories = await client().storySearch(filmTitle: "The Quiet Harbour", cinematographers: ["Jane Doe"])
        XCTAssertEqual(stories.found, [])
        XCTAssertEqual(stories.unbounded.map(\.source.site), ["Kodak"])
        XCTAssertEqual(stories.unbounded.first?.limit, .restricted)
        let reading = await client().reading(searched: [], fromSites: [], fromArticle: [], stories: [], person: nil, cinematographers: ["Jane Doe"],
                                             directors: [], year: 2023, unanswered: UnansweredSites(), unboundedStories: stories.unbounded)
        XCTAssertEqual(reading.skipped.map(\.source.site), ["Kodak"])
        XCTAssertTrue(reading.skipped.first?.reason.contains(CameraSources.unboundedArticle) ?? false)
    }

    /// R3: every paragraph inside a component: the article couldn't be told apart (not a thin page);
    /// a page wrapped in one form (and without a headline in it) is read.
    func testAllProseInComponentsFailsClosedAndAFormWrappedPageIsRead() {
        let comments = "<html><body><div class=\"comments\">" + Self.body.map(Self.p).joined() + "</div></body></html>"
        XCTAssertNil(ArticleReader.read(comments).boundary)
        let form = "<html><body><h1>Site</h1><form id=\"aspnetForm\"><div class=\"page\">" + Self.body.map(Self.p).joined()
            + "</div></form></body></html>"
        XCTAssertEqual(ArticleReader.read(form).paragraphs, Self.body)
    }

    /// R4: a short article in its container beside a large related block: the container wins; the
    /// related block isn't taken for the page's layout.
    func testAShortArticleBesideALargeRelatedBlock() {
        let related: [String] = (1...5).map { (n: Int) -> String in
            "Related story number \(n): a festival round-up of cameras and lenses, shot on the ARRI Alexa 35 and Kodak film."
        }
        let short: [String] = Array(Self.body.prefix(2))
        let html: String = "<html><body><h1>The piece</h1><div class=\"entry-content\">" + short.map(Self.p).joined()
            + "<div class=\"related-posts\">" + related.map(Self.p).joined() + "</div></div></body></html>"
        let article = ArticleReader.read(html)
        XCTAssertEqual(article.boundary, .container)
        XCTAssertEqual(article.paragraphs, short)
    }

    /// R5: the article beside three cards, side by side, the headline outside them all: not a
    /// round-up; the article is read without the cards.
    func testAnArticleBesideCardsIsntARoundUp() {
        let card: String = "<article><p>Another story from the site, teased here in a line of text that runs a little long.</p></article>"
        let more: [String] = ["A fourth paragraph of the article itself, so the article holds most of the page's prose by far.",
                              "And a fifth paragraph of the article, for good measure, saying more about how it was all shot."]
        let html: String = "<html><body><header><h1>The piece</h1></header><main><article>" + (Self.body + more).map(Self.p).joined()
            + "</article>" + String(repeating: card, count: 3) + "</main></body></html>"
        let article = ArticleReader.read(html)
        XCTAssertEqual(article.boundary, .article)
        XCTAssertEqual(article.paragraphs, Self.body + more)
    }

    /// R6: an unmarked region of 60%, beside two teaser blocks of 20%: only the 60% is read; many
    /// small blocks of one article are read together.
    func testAnUnmarkedArticleBesideTeaserBlocks() {
        let teaserA = "A teaser for another story on the site, which talks about digital cameras at some length here."
        let teaserB = "A second teaser for yet another story, about lenses and lighting on a documentary shoot abroad."
        let html: String = "<html><body><div class=\"x\">" + (Self.body + Self.body.map { $0 + " Again." }).map(Self.p).joined()
            + "</div><div class=\"y\">" + Self.p(teaserA) + Self.p(teaserA + " More.") + "</div><div class=\"z\">" + Self.p(teaserB)
            + Self.p(teaserB + " More.") + "</div></body></html>"
        let article = ArticleReader.read(html)
        XCTAssertEqual(article.boundary, .region)
        XCTAssertFalse(article.paragraphs.contains(teaserA))
        XCTAssertFalse(article.paragraphs.contains(teaserB))
        XCTAssertEqual(article.paragraphs.count, 6)
        let blocks: String = (Self.body + Self.body.map { $0 + " Again." }).map { "<div class=\"wp-block\">" + Self.p($0) + "</div>" }.joined()
        XCTAssertEqual(ArticleReader.read("<html><body><div class=\"content\">" + blocks + "</div></body></html>").paragraphs.count, 6)
    }

    /// R7, R8: a hero `<article>` holding the headline and a one-line dek beside the body's
    /// `<article>`: the body is read. A logo `<h1>` in a ticker doesn't make the ticker the article's.
    func testAHeroBesideTheBodyAndALogoHeadline() {
        let dek = "A short line under the headline, introducing the piece."
        let more: [String] = ["A fourth paragraph of the article itself, so the article holds most of the page's prose by far.",
                              "And a fifth paragraph of the article, for good measure, saying more about how it was all shot."]
        let hero: String = "<html><body><article class=\"hero\"><h1>The piece</h1><p>" + dek + " It runs on a little.</p></article><article class=\"body\">"
            + (Self.body + more).map(Self.p).joined() + "</article></body></html>"
        XCTAssertEqual(ArticleReader.read(hero).paragraphs, Self.body + more)
        let ticker = "Sony launches a camera extension system, expanding its cinema line to 65mm format this year."
        let logo: String = "<html><head><title>The piece | Lens Weekly</title></head><body><div class=\"news-ticker\"><h1>Lens Weekly</h1><p>"
            + ticker + "</p></div><div class=\"page\"><h1>The piece</h1>" + Self.body.map(Self.p).joined() + "</div></body></html>"
        let read = ArticleReader.read(logo)
        XCTAssertFalse(read.paragraphs.contains(ticker))
        XCTAssertEqual(read.paragraphs, Self.body)
    }

    /// R9: a round-up whose entries are `<article>`s inside the page's own `<article>`: entries,
    /// not cards. R10: items and paragraphs left open.
    func testNestedRoundUpEntriesAndOpenItems() {
        let entries: [String] = ["Dir: Carl Example DP: Jane Doe", "Dir: Fay Example DP: Gus Sample", "Dir: Ann Example DP: Bob Sample"]
        let sheet = "Format: 6.5K ARRIRAW Camera: ALEXA 65 Lenses: Panavision Sphero 65"
        let items: String = entries.map { "<article class=\"entry\"><h2>A film</h2><p>" + $0 + "</p><p>" + sheet + "</p></article>" }.joined()
        let html: String = "<html><body><article><h1>Festival cameras</h1><p>We asked the cinematographers what they shot on, and here is the list.</p><section>"
            + items + "</section></article></body></html>"
        let read = ArticleReader.read(html)
        XCTAssertTrue(read.paragraphs.contains(entries[0]))
        XCTAssertTrue(read.paragraphs.contains(entries[2]))
        let open: String = "<html><body><div class=\"entry-content\"><ul><li><p>" + Self.body[0] + "<li><p>" + Self.body[1] + "<li><p>" + Self.body[2]
            + "</ul></div></body></html>"
        XCTAssertEqual(ArticleReader.read(open).paragraphs, Self.body, "each once, not nested in the one before")
        let slash: String = "<html><body><div/><div class=\"entry-content\"><a href=/news/>News</a>" + Self.body.map(Self.p).joined() + "</div></body></html>"
        XCTAssertEqual(ArticleReader.read(slash).paragraphs, Self.body)
    }

    // MARK: Review round 2

    /// R16: an unmarked article in a "_sidebar_…" column, and a stray paragraph outside it: the
    /// column is read, not the leftover. R17: a short article beside three unmarked cards of
    /// smaller size, the headline outside them all: not a round-up.
    func testTheLayoutColumnOverALeftoverAndAShortArticleBesideCards() {
        let more: [String] = ["A fourth paragraph of the article itself, so the article holds most of the page's prose by far.",
                              "And a fifth paragraph of the article, for good measure, saying more about how it was all shot."]
        let stray = "A short note from the site about its events this autumn, set apart in a box of its own here."
        let column: String = "<html><body><h1>The piece</h1><div class=\"_sidebar_x_1\"><div class=\"_inner_y_1\">" + (Self.body + more).map(Self.p).joined()
            + "</div></div><div class=\"box\">" + Self.p(stray) + "</div></body></html>"
        XCTAssertEqual(ArticleReader.read(column).paragraphs, Self.body + more)
        let card: String = "<article><p>Another story from the site, teased here in a line of text that runs on for a bit more than one line.</p></article>"
        let cards: String = "<html><body><header><h1>The piece</h1></header><main><article>" + Self.body.map(Self.p).joined() + "</article>"
            + String(repeating: card, count: 3) + "</main></body></html>"
        let read = ArticleReader.read(cards)
        XCTAssertEqual(read.boundary, .article)
        XCTAssertEqual(read.paragraphs, Self.body)
        // A related block never becomes the layout, however much of the page it fills.
        let related: [String] = (1...6).map { (n: Int) -> String in "Related story \(n): a long excerpt about a different film and how it was shot on film." }
        let page: String = "<html><body><h1>The piece</h1><div class=\"x\">" + Self.body.prefix(2).map(Self.p).joined()
            + "</div><div class=\"related-posts\">" + related.map(Self.p).joined() + "</div></body></html>"
        XCTAssertEqual(ArticleReader.read(page).paragraphs, Array(Self.body.prefix(2)))
    }

    /// TheWrap's shape (live, found by a CI probe): the headline in a hero `<article>` with one line,
    /// the interview's container in a wrapper named "content-wrapper--has-sidebar" beside a real
    /// sidebar. A wrapper that has a sidebar isn't one: the interview is read, the sidebar isn't.
    func testAnInterviewInAHasSidebarWrapper() {
        let more: [String] = ["A fourth paragraph of the interview itself, so the body holds most of the page's prose by far.",
                              "And a fifth paragraph of the interview, for good measure, saying more about how it was all shot."]
        let side = "Most read: a festival round-up of cameras and lenses, with every lens listed for each film."
        let html: String = "<html><head><title>The piece | Lens Weekly</title></head><body><article class=\"hero\"><h1>The piece</h1>"
            + "<p>A short line under the headline, introducing the piece at some length.</p></article>"
            + "<div class=\"content-wrapper content-wrapper--has-sidebar\"><div class=\"article-content\">" + (Self.body + more).map(Self.p).joined()
            + "</div><aside class=\"sidebar\"><p>" + side + "</p></aside></div></body></html>"
        let read = ArticleReader.read(html)
        XCTAssertGreaterThanOrEqual(read.paragraphs.count, 5)
        XCTAssertTrue(read.paragraphs.contains(Self.body[1]))
        XCTAssertFalse(read.paragraphs.contains(side))
    }

    /// Round 3, N1/N2: a short genuine article stays the article — beside four unmarked excerpts in
    /// `<main>`, and beside a "sidebar" column of post cards holding most of the page's prose.
    func testAShortArticleBesideExcerptsOrASidebarOfCards() {
        let short: [String] = Array(Self.body.prefix(2))
        let excerpts: [String] = (1...4).map { (n: Int) -> String in "Lens news \(n): a new zoom arrives for full-frame cinema cameras, in a short excerpt." }
        let news: String = "<html><body><main><article><h1>The piece</h1>" + short.map(Self.p).joined() + "</article><div class=\"more-news\">"
            + excerpts.map(Self.p).joined() + "</div></main></body></html>"
        XCTAssertEqual(ArticleReader.read(news).paragraphs, short)
        let cards: String = (1...4).map { (n: Int) -> String in
            "<article class=\"card\"><p>Card \(n): another story from the site, its excerpt running on for a good long line or two here.</p></article>"
        }.joined()
        let column: String = "<html><body><div class=\"page\"><h1>The piece</h1>" + short.map(Self.p).joined() + "</div><div class=\"sidebar\">"
            + cards + "</div></body></html>"
        XCTAssertEqual(ArticleReader.read(column).paragraphs, short)
    }

    /// No Film School (live, found by a CI probe): the article body's own class carries "-ads" in
    /// another of its names ("article-body main-article-body-ads"). The body's mark wins.
    func testAnArticleBodyWhoseClassAlsoNamesAds() {
        let html: String = "<html><body><h1>The piece</h1><div class=\"mb-2 article-body main-article-body-ads\">" + Self.body.map(Self.p).joined()
            + "</div><div class=\"ads-slot\"><p>Advertisement: the best camera bags of the year, reviewed and ranked for you here.</p></div></body></html>"
        let read = ArticleReader.read(html)
        XCTAssertEqual(read.boundary, .container)
        XCTAssertEqual(read.paragraphs, Self.body)
    }

    /// Round 4, F1/F2: a related block whose class also contains a container name stays out; a real
    /// sidebar with a "has-…" modifier stays a sidebar.
    func testRelatedPostContentAndASidebarWithAModifierStayOut() {
        let related: [String] = (1...3).map { (n: Int) -> String in "Related \(n): a long excerpt of another story on the site, about a different film entirely." }
        let html: String = "<html><body><h1>The piece</h1><div class=\"entry-content\">" + Self.body.map(Self.p).joined() + "</div>"
            + "<div class=\"related-post-content\">" + related.map(Self.p).joined() + "</div></body></html>"
        XCTAssertEqual(ArticleReader.read(html).paragraphs, Self.body)
        let widgets: [String] = (1...4).map { (n: Int) -> String in "Popular \(n): a festival round-up of cameras and lenses, with every lens listed for each film." }
        let side: String = "<html><body><main><h1>The piece</h1>" + Self.body.map(Self.p).joined() + "<div class=\"sidebar has-background\">"
            + widgets.map(Self.p).joined() + "</div></main></body></html>"
        XCTAssertEqual(ArticleReader.read(side).paragraphs, Self.body)
    }

    /// 1.10.6: a page that comes back as a shell (IndieWire's gallery, now and then: a footer and a
    /// newsletter box) is a site that didn't answer — read again later, its old evidence carried —
    /// not a page whose article couldn't be told apart.
    func testAShellPageIsReadAgainLater() async {
        let shell = "<html><head><title>Festival cameras</title></head><body><div class=\"_newsletter_ab_1\"><p>By providing your information, you agree to our terms of use and our privacy policy.</p></div>"
            + "<footer><p>© 2026 A made-up company. All rights reserved. Terms of use, privacy and accessibility.</p></footer></body></html>"
        let article = ArticleReader.read(shell)
        XCTAssertNil(article.boundary)
        XCTAssertTrue(article.incomplete)
        XCTAssertFalse(ArticleReader.read(Self.definitionPage()).incomplete)
        StandInSite.reset()
        defer { StandInSite.reset() }
        StandInSite.route("shell.example", "gallery", body: shell)
        let noting = UnansweredSites()
        let got = await client().page(URL(string: "https://shell.example/gallery/")!, site: "Lens Weekly", title: nil, noting: noting)
        XCTAssertNil(got.source)
        XCTAssertEqual(got.failure, .unanswered(CameraSources.incompletePage))
        XCTAssertTrue(got.failure?.retried ?? false, "read again later")
        let unanswered = await noting.all()
        XCTAssertEqual(unanswered, ["Lens Weekly"])
        // What its site said before is carried, as when a site doesn't answer.
        let old = CraftIndex(version: 14, readAt: start, shotOn: [.digital], names: [],
                             evidence: [CraftIndex.Evidence(shotOn: .digital, text: "We shot it on the Sony Venice 2.", source: "Lens Weekly")],
                             sources: 2, read: ["Lens Weekly", "Wikipedia"])
        let new = CraftIndex(readAt: start, shotOn: [], names: [], evidence: [], sources: 1, read: ["Wikipedia"], unanswered: ["Lens Weekly"])
        let merged = CraftIndex.merging(old: old, new: new, now: start)
        XCTAssertEqual(merged.index.shotOn, [.digital])
        XCTAssertNotNil(merged.index.retryAt)
    }

    func testRulesVersion() {
        XCTAssertEqual(CraftIndex.currentVersion, 15)
        XCTAssertEqual(CraftIndex.currentDiscovery, 5)
        XCTAssertEqual(CraftIndex.findingChanged, 2)
        XCTAssertEqual(LibraryFile.currentVersion, 3)
    }
}
