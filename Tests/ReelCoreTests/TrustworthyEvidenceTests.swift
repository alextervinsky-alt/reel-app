import XCTest
@testable import ReelCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reel 1.9.7: each tag's reason is its strongest sentence, cited "http://" pages are read over
/// HTTPS, and a page that's gone or refused is told from a site that didn't answer. The sentences
/// are shaped like the real ones; the films, people and sites are made up.
final class TrustworthyEvidenceTests: XCTestCase {
    private func craft(_ texts: [(source: String?, paragraphs: [String])], title: String = "The Quiet Harbour") -> CraftIndex {
        let read = texts.map { text in
            text.source.map { TechSpecs.Text(source: $0, paragraphs: text.paragraphs) }
                ?? TechSpecs.Text(source: nil, sections: [FilmArticle.Section(id: 0, title: "Filming", paragraphs: text.paragraphs)],
                                  isInterview: false)
        }
        let specs = TechSpecs.read(texts: read, cinematographers: ["Jane Doe"], directors: ["Carl Example"], title: title)
        return CraftIndex.make(from: specs, colour: nil, keywords: [])
    }

    private func craft(_ paragraphs: [String], source: String = "Lens Weekly") -> CraftIndex {
        craft([(source, paragraphs)])
    }

    // MARK: The strongest reason

    /// A remark at a prize-giving read first, a summary that only says the film was used, and the
    /// lab's statement that the film was shot on it: the statement is the reason.
    func testTheStatementThatTheFilmWasShotOnItIsTheReason() {
        let reading = craft([
            ("British Lens", ["“I think celluloid is very important – four out of five films nominated for a prize and a lot more films shot on film that are not nominated. The audience really responds in a different way to films that are shot on film and I thought that was very important to say when I had a chance.”"]),
            ("Lens Weekly", ["Doe, the director and key collaborators discuss using custom optics, 65mm film negative and other tools to create “experiential cinema” for The Quiet Harbour."]),
            ("Stock House", ["Doe shot The Quiet Harbour on KODAK 65mm large format negative film stocks, using KODAK VISION3 250D Color Negative Film 5207 for exteriors."]),
        ])
        XCTAssertEqual(reading.shotOn, [.film])
        XCTAssertEqual(reading.evidence(for: .film)?.source, "Stock House")
        XCTAssertTrue(reading.evidence(for: .film)?.text.hasPrefix("Doe shot The Quiet Harbour on KODAK") ?? false,
                      "\(reading.evidence(for: .film)?.text ?? "")")
    }

    func testFilmsInGeneralAreNotThisFilm() {
        XCTAssertEqual(craft(["Films that are shot on film just feel different to an audience."]).shotOn, [])
        let both = craft(["Films that are shot on film just feel different to an audience.", "The film was shot on Kodak 5219."])
        XCTAssertEqual(both.evidence(for: .film)?.text, "The film was shot on Kodak 5219.")
        // One film, said of itself, still is.
        XCTAssertEqual(craft(["It is a film that was shot on 35mm film stock."]).shotOn, [.film])
    }

    func testAStatementAboutThisFilmBeatsAnEarlierMention() {
        let film = craft(["Doe relied on Kodak 5219 for the interiors.", "The Quiet Harbour was shot on 35mm film."])
        XCTAssertEqual(film.evidence(for: .film)?.text, "The Quiet Harbour was shot on 35mm film.")
        let digital = craft(["Doe used the Alexa for some pickups.", "The Quiet Harbour was shot on the Sony Venice 2."])
        XCTAssertEqual(digital.evidence(for: .digital)?.text, "The Quiet Harbour was shot on the Sony Venice 2.")
        // Said in so many words both times: the gear named over Reel's own word.
        let named = craft(["The film was shot on film.", "The film was shot on Kodak Vision3 500T 5219."])
        XCTAssertEqual(named.evidence(for: .film)?.text, "The film was shot on Kodak Vision3 500T 5219.")
        // Equal: the first read (the interviews before the film's article).
        let equal = craft([("Lens Weekly", ["We shot the film on Kodak 5219."]), (nil, ["The film was shot on Kodak 5219 stock."])])
        XCTAssertEqual(equal.evidence(for: .film)?.source, "Lens Weekly")
    }

    /// The review of 1.9.7: Film and Digital are ranked by how much of the film is said too.
    func testTheWholeFilmBeatsPartOfIt() {
        let film = craft(["We shot entirely on Kodak 5219 35mm film.", "The film was shot on 16mm film stock for the dream sequences."])
        XCTAssertEqual(film.evidence(for: .film)?.text, "We shot entirely on Kodak 5219 35mm film.")
        XCTAssertEqual(film.label(for: .film), "Film", "never in part")
        // A bare "it" may be a scene: not said of the film in so many words.
        let scene = craft(["The battle sequence took weeks, and it was shot on 65mm film stock.", "Doe used Kodak 5219 for the rest."])
        XCTAssertEqual(scene.evidence(for: .film)?.text, "The battle sequence took weeks, and it was shot on 65mm film stock.", "the first read, as neither is direct")
    }

    func testOneOfTheFewFilmsShotThatWayIsThisFilm() {
        XCTAssertEqual(craft(["The Quiet Harbour is one of the few films that were shot entirely on 65mm film stock."]).shotOn, [.film])
        XCTAssertEqual(craft(["It was among the first feature films that were shot on the Sony Venice 2."]).shotOn, [.digital])
    }

    func testShortAndPunctuatedTitles() {
        func direct(_ sentence: String, _ words: String, title: String) -> Bool {
            guard let range = sentence.range(of: words) else { return false }
            return TechSpecs.saidDirectly(sentence, at: range, title: title)
        }
        XCTAssertFalse(direct("Doe shot her close-ups on the Alexa Mini.", "Alexa Mini", title: "Her"), "her, not Her")
        XCTAssertTrue(direct("Doe shot Her on the Alexa Mini.", "Alexa Mini", title: "Her"))
        XCTAssertTrue(direct("Doe shot Mother! on 35mm film.", "35mm", title: "Mother!"))
        XCTAssertTrue(direct("Doe shot Schindler’s List on Double-X.", "Double-X", title: "Schindler's List"))
        XCTAssertFalse(direct("Doe shot the film's opening on 16mm.", "16mm", title: "The Quiet Harbour"), "the film's opening")
        XCTAssertFalse(direct("It was originally shot on 16mm, but the studio wanted 35mm.", "16mm", title: "The Quiet Harbour"))
    }

    func testScopeStillComesFirst() {
        // A stated share outweighs a sentence saying the film was shot with it.
        let share = craft(["The Quiet Harbour was shot with IMAX cameras.", "About 40 minutes were shot with IMAX cameras."])
        XCTAssertEqual(share.label(for: .imax), "IMAX (in part)")
        // Part of the film said in so many words doesn't outweigh the whole said plainly.
        let lenses = craft(["The Quiet Harbour was shot with anamorphic lenses for the flashbacks.", "Doe used anamorphic lenses throughout the shoot."])
        XCTAssertEqual(lenses.label(for: .anamorphic), "Anamorphic")
        XCTAssertEqual(craft(["The flashbacks were shot with anamorphic lenses."]).label(for: .anamorphic), "Anamorphic (in part)")
        XCTAssertEqual(craft(["The entire film was shot with IMAX cameras."]).label(for: .imax), "IMAX")
        // Each tag from its own sentence: Film and IMAX aren't interchangeable.
        let mixed = craft(["The Quiet Harbour was shot on 35mm film, with about 30 minutes shot with IMAX cameras."])
        XCTAssertEqual(mixed.shotOn, [.film, .imax])
        XCTAssertEqual(mixed.label(for: .imax), "IMAX (in part)")
        XCTAssertEqual(mixed.label(for: .film), "Film")
    }

    func testRejectedSentencesStillCantBeTheReason() {
        // A transfer, an interviewer's line, a speech, a plan: never the reason, however strong they look.
        let transfer = craft(["The lab supervised transferring images captured in IMAX format onto 35mm colour negative film."])
        XCTAssertEqual(transfer.shotOn, [.imax])
        XCTAssertEqual(craft(["BB: The film was shot on film, wasn't it?"]).shotOn, [])
        XCTAssertEqual(craft(["BB: So the film was shot on 35mm film stock."]).shotOn, [], "the interviewer")
        XCTAssertEqual(craft(["On accepting her award, Doe said the film was shot on film."]).shotOn, [])
        XCTAssertEqual(craft(["The original plan had been to shoot the film on 16mm film stock."]).shotOn, [])
    }

    func testDirectStatements() {
        func direct(_ sentence: String, _ words: String) -> Bool {
            guard let range = sentence.range(of: words) else { return false }
            return TechSpecs.saidDirectly(sentence, at: range, title: "Dune: Part Two")
        }
        XCTAssertTrue(direct("Fraser shot Dune: Part Two on the Alexa 65.", "Alexa 65"))
        XCTAssertTrue(direct("Dune was shot on the Alexa LF.", "Alexa LF"), "the title before its colon")
        XCTAssertTrue(direct("The film was mostly shot with Kodak 5219.", "Kodak 5219"))
        XCTAssertTrue(direct("We shot the whole film on the Alexa 65.", "Alexa 65"))
        XCTAssertFalse(direct("Cameras: Alexa 65 | Lenses: Moviecam | Format: 2.39:1", "Alexa 65"), "1.9.8: a spec sheet is its own rank (`Spec.sheet`)")
        XCTAssertFalse(direct("They discuss using the Alexa 65 for the deserts.", "Alexa 65"))
        XCTAssertFalse(direct("The film was shot in Jordan, but the Alexa 65 was used for the deserts.", "Alexa 65"),
                       "said in another part of the sentence")
    }

    // MARK: Cited addresses

    func testCitedHTTPAddressesAreReadOverHTTPS() {
        let old = URL(string: "http://www.theasc.example/ac_magazine/July2008/Harbour/page1.php?part=2#top")!
        XCTAssertEqual(CameraSources.secure(old).absoluteString, "https://www.theasc.example/ac_magazine/July2008/Harbour/page1.php?part=2#top")
        let https = URL(string: "https://lens.example/a?b=1")!
        XCTAssertEqual(CameraSources.secure(https), https, "already HTTPS: as it is")
        XCTAssertEqual(CameraSources.secure(CameraSources.secure(old)), CameraSources.secure(old), "stable")
        XCTAssertEqual(CameraSources.secure(URL(string: "http://lens.example:80/a")!).absoluteString, "https://lens.example/a")
        XCTAssertEqual(CameraSources.secure(URL(string: "ftp://lens.example/a")!).absoluteString, "ftp://lens.example/a")
    }

    func testTheSamePageIsReadOnce() {
        XCTAssertEqual(CameraSources.identity(URL(string: "http://www.lens.example/harbour-interview/")!),
                       CameraSources.identity(URL(string: "https://lens.example/harbour-interview")!))
        XCTAssertEqual(CameraSources.identity(URL(string: "https://lens.example/a?id=3&utm_source=x")!),
                       CameraSources.identity(URL(string: "https://lens.example/a?id=3")!))
        XCTAssertNotEqual(CameraSources.identity(URL(string: "https://lens.example/a?id=3")!),
                          CameraSources.identity(URL(string: "https://lens.example/a?id=4")!))
        XCTAssertEqual(CameraSources.identity(URL(string: "https://lens.example/a?id=3&ref=rss&fbclid=x&mc_cid=1")!),
                       CameraSources.identity(URL(string: "https://lens.example/a?id=3")!), "where it was shared from")
        XCTAssertEqual(CameraSources.identity(URL(string: "https://lens.example/a?b=2&a=1")!),
                       CameraSources.identity(URL(string: "https://lens.example/a?a=1&b=2")!))
        let picked = CameraSources.pick(["http://www.theasc.com/ac_magazine/July2008/Harbour/page1.php",
                                         "https://theasc.com/ac_magazine/July2008/Harbour/page1.php",
                                         "https://theasc.com/article/harbour-doe-interview/"], cinematographers: ["Jane Doe"])
        XCTAssertEqual(picked.count, 2, "one page cited twice is read once")
        let legacy = picked.first { $0.url.path.contains("July2008") }
        XCTAssertEqual(legacy?.url.absoluteString, "https://www.theasc.com/ac_magazine/July2008/Harbour/page1.php")
        XCTAssertEqual(legacy?.cited?.absoluteString, "http://www.theasc.com/ac_magazine/July2008/Harbour/page1.php", "the address as cited is kept")
        XCTAssertNil(picked.first { $0.url.path.contains("article") }?.cited)
    }

    func testARedirectToTheFrontPageIsGone() {
        let asked = URL(string: "https://lens.example/2009/11/harbour-terabytes.html")!
        XCTAssertTrue(CameraSources.isFrontPage(URL(string: "https://lens.example/")!, for: asked))
        XCTAssertTrue(CameraSources.isFrontPage(URL(string: "https://www.lens.example/index.php")!, for: asked))
        XCTAssertFalse(CameraSources.isFrontPage(URL(string: "https://lens.example/articles/harbour-terabytes")!, for: asked), "moved, not gone")
        XCTAssertEqual(SourceFailure.of(status: 200, data: Data(), requested: asked, landed: URL(string: "https://lens.example/")!),
                       .gone("moved to the site's front page"))
        XCTAssertNil(SourceFailure.of(status: 200, data: Data(), requested: asked, landed: URL(string: "https://lens.example/articles/harbour")!))
        // A search answered by the front page isn't a page that's gone: it fails as a search, noted.
        XCTAssertNil(SourceFailure.of(status: 200, data: Data(), requested: asked, landed: URL(string: "https://lens.example/")!, page: false))
    }

    // MARK: What a failure means

    func testFailuresAreToldApart() {
        let asked = URL(string: "https://lens.example/harbour")!
        func of(_ status: Int, _ body: String = "<html><body><p>Hello</p></body></html>") -> SourceFailure? {
            SourceFailure.of(status: status, data: Data(body.utf8), requested: asked, landed: nil)
        }
        XCTAssertNil(of(200))
        XCTAssertEqual(of(404), .gone("not found over HTTPS (404)"), "as seen: over HTTPS")
        XCTAssertEqual(of(410), .gone("not found over HTTPS (410)"))
        XCTAssertEqual(of(403), .restricted("refused (403): a sign-in, a paywall or access denied"), "a 403 isn't taken for gone")
        XCTAssertEqual(of(403, "<html><head><title>Just a moment...</title>"), .wait("a challenge page in place of the page"))
        XCTAssertEqual(of(429), .wait("too many requests (429)"))
        XCTAssertEqual(of(500), .unanswered("the server failed (500)"))
        XCTAssertEqual(of(503), .unanswered("the server failed (503)"))
        for failure in [of(404), of(403)] { XCTAssertEqual(failure?.retried, false) }
        for failure in [of(429), of(500), of(503), of(403, "<title>just a moment")] { XCTAssertEqual(failure?.retried, true) }
        XCTAssertEqual(SourceFailure.of(error: URLError(.timedOut)), .unanswered("timed out"))
        XCTAssertEqual(SourceFailure.of(error: URLError(.cannotFindHost)), .unanswered("the site's address wasn't found"))
        XCTAssertEqual(SourceFailure.of(error: URLError(.networkConnectionLost)).retried, true)
        XCTAssertEqual(SourceFailure.of(error: NSError(domain: NSURLErrorDomain, code: -1022)),
                       .restricted("only over plain HTTP, which Reel doesn't load"), "no plain-HTTP fallback")
        XCTAssertEqual(SourceFailure.of(error: URLError(.secureConnectionFailed)).retried, true, "a failed secure connection may pass")
        XCTAssertEqual(of(408)?.retried, true, "a request that took too long")
        XCTAssertEqual(of(425)?.retried, true)
        XCTAssertEqual(of(407)?.retried, true, "a proxy on Reel's own side")
        XCTAssertEqual(SourceFailure.of(error: NSError(domain: NSURLErrorDomain, code: -1007)), .restricted("its redirects go round in a loop"))
        XCTAssertEqual(SourceFailure.of(error: NSError(domain: NSURLErrorDomain, code: -1202)), .restricted("its certificate isn't valid"))
        // Cited as plain HTTP and no HTTPS to be had: not retried every month.
        XCTAssertEqual(SourceFailure.of(error: URLError(.secureConnectionFailed), upgraded: true), .restricted("only over plain HTTP, which Reel doesn't load"))
        XCTAssertEqual(SourceFailure.of(error: URLError(.cannotConnectToHost), upgraded: true).retried, false)
        XCTAssertEqual(SourceFailure.of(error: URLError(.timedOut), upgraded: true).retried, true, "a timeout may pass")
        XCTAssertEqual(SourceFailure.of(error: NSError(domain: "Elsewhere", code: -1022)), .unanswered("no answer"), "only URL errors by their codes")
    }

    // MARK: Over the network (a stand-in for the sites)

    private func client() -> CameraSourcesClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StandInSite.self]
        return CameraSourcesClient(session: URLSession(configuration: config))
    }

    private let article = "<html><head><title>Harbour light</title></head><body>"
        + "<p>Doe shot The Quiet Harbour on Kodak 5219 with Panaflex cameras, and the light came mostly from the windows.</p>"
        + "<p>The night exteriors were lit with a single large source on a crane, far above the harbour wall.</p>"
        + "<p>Doe and the director spent a month testing lenses before choosing a set of old spherical primes.</p></body></html>"

    func testAPageCitedOverHTTPIsAskedForOverHTTPS() async {
        StandInSite.answer("legacy.example", status: 200, body: article)
        let read = await client().page(URL(string: "http://legacy.example/2008/harbour/page1.php?part=1")!, site: "Lens Weekly", title: nil)
        XCTAssertNil(read.failure)
        XCTAssertEqual(read.source?.paragraphs.count, 3)
        XCTAssertEqual(read.source?.url.absoluteString, "https://legacy.example/2008/harbour/page1.php?part=1")
        XCTAssertEqual(StandInSite.asked(of: "legacy.example").map { $0.scheme }, ["https"], "never over plain HTTP")
        XCTAssertEqual(StandInSite.asked(of: "legacy.example").first?.query, "part=1")
    }

    func testOnlyASiteThatDidntAnswerLeavesTheReadingIncomplete() async {
        StandInSite.answer("gone.example", status: 404, body: "<p>Not here</p>")
        StandInSite.answer("refused.example", status: 403, body: "<p>Members only</p>")
        StandInSite.answer("failing.example", status: 500, body: "")
        StandInSite.fail("slow.example", code: -1001)
        StandInSite.fail("plain.example", code: -1200)
        let noting = UnansweredSites()
        let client = client()
        let gone = await client.page(URL(string: "https://gone.example/harbour")!, site: "Gone Weekly", title: nil, noting: noting)
        let refused = await client.page(URL(string: "https://refused.example/harbour")!, site: "Members Weekly", title: nil, noting: noting)
        let failing = await client.page(URL(string: "https://failing.example/harbour")!, site: "Failing Weekly", title: nil, noting: noting)
        let slow = await client.page(URL(string: "https://slow.example/harbour")!, site: "Slow Weekly", title: nil, noting: noting)
        let plain = await client.page(URL(string: "http://plain.example/1999/harbour.html")!, site: "Plain Weekly", title: nil, noting: noting)
        XCTAssertEqual(plain.failure, .restricted("only over plain HTTP, which Reel doesn't load"), "cited as HTTP, no HTTPS")
        XCTAssertEqual(gone.failure, .gone("not found over HTTPS (404)"))
        XCTAssertEqual(refused.failure?.retried, false)
        XCTAssertEqual(failing.failure, .unanswered("the server failed (500)"))
        XCTAssertEqual(slow.failure, .unanswered("timed out"))
        let unanswered = await noting.all()
        XCTAssertEqual(Set(unanswered), ["Failing Weekly", "Slow Weekly"], "a page gone or refused isn't a site that didn't answer")
        for result in [gone, refused, failing, slow] { XCTAssertNil(result.source, "a failed fetch isn't an empty page") }
    }

    // MARK: The reading, the log and reading again

    func testTheLogSaysWhereAPageWasRead() {
        var details = TMDBMovieDetails(id: 9, title: "The Quiet Harbour", releaseDate: "2020-01-01")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Jane Doe", job: "Director of Photography")])
        var source = CameraReading.Source(title: "Harbour light", site: "Lens Weekly", url: URL(string: "https://legacy.example/2008/harbour")!,
                                          paragraphs: ["Doe shot The Quiet Harbour on Kodak 5219 with Panaflex cameras, in the harbour itself."])
        source.cited = URL(string: "http://legacy.example/2008/harbour")
        let gone = CameraReading.Source(title: "Old interview", site: "Gone Weekly", url: URL(string: "https://gone.example/harbour")!, paragraphs: [])
        let reading = CameraReading(sources: [source], more: [], cinematographer: nil,
                                    skipped: [CameraReading.Skipped(source: gone, reason: SourceFailure.gone("not found (404)").reason)])
        let log = CraftReader.reading(of: details, articleTitle: nil, article: nil, reading: reading, colour: nil).log
        XCTAssertTrue(log.contains("https://legacy.example/2008/harbour  (cited as http://legacy.example/2008/harbour)"), log)
        XCTAssertTrue(log.contains("• Gone Weekly: Old interview — gone: not found (404)"), log)
        XCTAssertFalse(log.contains("DIDN'T ANSWER"), "a page that's gone isn't a site that didn't answer")
    }

    func testASiteThatAnswersAgainFillsInTheReading() {
        let then = Date(timeIntervalSince1970: 1_790_000_000)
        let partial = CraftIndex.merging(old: nil, new: CraftIndex(readAt: then, shotOn: [], names: [], sources: 1, read: ["Wikipedia"],
                                                                   unanswered: ["Lens Weekly"]), now: then).index
        XCTAssertTrue(partial.isPartial)
        let later = then.addingTimeInterval(7 * 3600)
        XCTAssertTrue(CraftQueue.isDue(craft: partial, attempt: nil, hasFacts: true, inCollection: false, now: later))
        let answered = CraftIndex(readAt: later, shotOn: [.film], names: ["Kodak 5219"],
                                  evidence: [CraftIndex.Evidence(shotOn: .film, text: "Doe shot it on Kodak 5219.", source: "Lens Weekly")],
                                  sources: 2, read: ["Lens Weekly", "Wikipedia"])
        let merged = CraftIndex.merging(old: partial, new: answered, now: later).index
        XCTAssertEqual(merged.shotOn, [.film])
        XCTAssertFalse(merged.isPartial)
        XCTAssertNil(merged.retryAt)
        XCTAssertEqual(CraftQueue.state(craft: merged, attempt: nil, hasFacts: true, inCollection: false, now: later), .complete)
    }
}

/// A stand-in for the sites: answers by host, and remembers what was asked.
final class StandInSite: URLProtocol {
    private struct Answer {
        let status: Int
        let body: String
        let error: Int?
    }

    private static let lock = NSLock()
    private static var answers: [String: Answer] = [:]
    private static var requests: [URL] = []

    /// How `host` answers from now on (and what it was asked before is forgotten).
    static func answer(_ host: String, status: Int, body: String) {
        lock.lock(); defer { lock.unlock() }
        answers[host] = Answer(status: status, body: body, error: nil)
        requests.removeAll { $0.host == host }
    }

    static func fail(_ host: String, code: Int) {
        lock.lock(); defer { lock.unlock() }
        answers[host] = Answer(status: 0, body: "", error: code)
        requests.removeAll { $0.host == host }
    }

    static func asked(of host: String) -> [URL] {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { $0.host == host }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self.requests.append(url)
        let answer = Self.answers[url.host ?? ""]
        Self.lock.unlock()
        guard let answer, answer.error == nil else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: answer?.error ?? -1003))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
