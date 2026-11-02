import XCTest
@testable import ReelCore

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
                                                   detail: "not open to Reel: " + CameraSources.unboundedArticle)]
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

    func testRulesVersion() {
        XCTAssertEqual(CraftIndex.currentVersion, 14)
        XCTAssertEqual(CraftIndex.currentDiscovery, 5)
        XCTAssertEqual(CraftIndex.findingChanged, 2)
        XCTAssertEqual(LibraryFile.currentVersion, 3)
    }
}
