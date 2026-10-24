import XCTest
@testable import ReelCore

/// Reel 1.9.8: a round-up's spec sheet only from this film's own entry, "It was shot…" after another
/// film's sentence that film's, the reason ranked by how plainly it's said, and the pages a reading
/// couldn't examine kept with it. Shaped like the real pages; the films, people and sites are made up.
final class AttributionAndCoverageTests: XCTestCase {
    private func read(_ texts: [TechSpecs.Text], year: Int? = 2024) -> (specs: TechSpecs, craft: CraftIndex) {
        let specs = TechSpecs.read(texts: texts, cinematographers: ["Jane Doe"], directors: ["Carl Example"], year: year,
                                   title: "The Quiet Harbour")
        return (specs, CraftIndex.make(from: specs, colour: nil, keywords: []))
    }

    private func text(_ paragraphs: [String], source: String = "Fest Weekly") -> TechSpecs.Text {
        TechSpecs.Text(source: source, paragraphs: paragraphs)
    }

    private func cameras(_ specs: TechSpecs) -> [String] { specs.names(.camera).map { $0.lowercased() } }

    // MARK: Whose spec sheet

    /// A festival's camera round-up: each entry's credits line, its sheet, then its commentary. The
    /// sheet after this film's commentary is the next entry's (its credits line isn't on the page),
    /// however much the commentary names this film.
    private let festival = [
        "Dir: Ann Example, DP: Bob Sample Category: Competition",
        "Format: Super 16mm Camera: ARRIFLEX 416 Lenses: Zeiss Ultra 16",
        "The Look: We wanted the beach to feel like a memory of the summer.",
        "Dir: Carl Example, DP: Jane Doe Category: Competition",
        "Format: 6.5K ARRIRAW Camera: ALEXA 65 Lenses: Panavision Sphero 65",
        "The Look: In the first conversation we had about “The Quiet Harbour,” Carl mentioned an IMAX release.",
        "“The Quiet Harbour” is not set in a specific time, and this allows us to mix old and new.",
        "Format: ARRIRAW 3.4K Open Gate, BlackmagicRAW Camera: ALEXA Mini, AMIRA, BlackMagic Pocket Cinema Camera 4K Lenses: ARRI Ultra Prime",
        "The Look: “Sun Over Water” is a skating film set in a snowy countryside.",
        "Dir: Dana Example, DP: Eve Sample Category: Un Certain Regard",
        "Format: 35mm Camera: ARRICAM LT Lenses: Cooke Anamorphic/i",
    ]

    func testARoundUpsSheetIsThisFilmsOnlyInItsOwnEntry() {
        let (specs, craft) = read([text(festival)])
        XCTAssertEqual(specs.roundups, ["Fest Weekly"])
        XCTAssertTrue(cameras(specs).contains { $0.contains("alexa 65") }, "\(specs.names(.camera))")
        for other in ["alexa mini", "amira", "blackmagic", "arriflex", "arricam"] {
            XCTAssertFalse(cameras(specs).contains { $0.contains(other) }, "\(other) is another entry's: \(specs.names(.camera))")
        }
        XCTAssertEqual(craft.shotOn, [.digital])
        XCTAssertTrue(craft.evidence(for: .digital)?.text.contains("ALEXA 65") ?? false, "\(craft.evidence(for: .digital)?.text ?? "")")
        // Kept so through saving and opening again.
        let saved = try? JSONStore.decode(CraftIndex.self, from: JSONStore.encode(craft))
        XCTAssertEqual(saved?.evidence(for: .digital)?.source, "Fest Weekly")
        XCTAssertFalse(saved?.names.contains { $0.lowercased().contains("amira") } ?? true)
    }

    func testAnEntryWithoutItsOwnSheetTakesNoOneElses() {
        var paragraphs = festival
        paragraphs.remove(at: 4)   // this film's own sheet
        let (specs, craft) = read([text(paragraphs)])
        XCTAssertTrue(cameras(specs).isEmpty, "the next sheet isn't this film's: \(specs.names(.camera))")
        XCTAssertEqual(craft.shotOn, [], "nothing said of it: no tag, rather than another film's")
    }

    func testAnotherFilmsSheetDoesntOverrideThisFilmsProse() {
        // The film's own article says what it was shot on; the round-up's stray sheet adds nothing.
        var paragraphs = festival
        paragraphs.remove(at: 4)
        let (specs, craft) = read([text(["Doe shot The Quiet Harbour on two ARRI Alexa 65 cameras."], source: "Lens Weekly"), text(paragraphs)])
        XCTAssertEqual(craft.shotOn, [.digital], "the tag stands on its own evidence")
        XCTAssertEqual(craft.evidence(for: .digital)?.source, "Lens Weekly")
        XCTAssertFalse(cameras(specs).contains { $0.contains("amira") })
    }

    func testAnEarlierProductionsCameraIsntThisFilms() {
        let article = text([
            "The project's long gestation led to Doe and Example's first collaboration, on his 2007 feature Glass Rivers. It was shot using Sony HDW-F900 CineAlta cameras — a unique digital production solution at the time.",
            "The filmmakers selected a grand canvas for The Quiet Harbour, using two ARRI Alexa 65 cameras for main unit.",
        ], source: "Lens Weekly")
        let (specs, craft) = read([article])
        XCTAssertFalse(cameras(specs).contains { $0.contains("f900") || $0.contains("cinealta") }, "\(specs.names(.camera))")
        XCTAssertTrue(cameras(specs).contains { $0.contains("alexa 65") })
        XCTAssertTrue(craft.evidence(for: .digital)?.text.contains("Alexa 65") ?? false)
        // "It" after a sentence about this film is this film.
        let own = read([text(["Doe and Example talked for years about The Quiet Harbour. It was shot using two ARRI Alexa 65 cameras."], source: "Lens Weekly")])
        XCTAssertTrue(cameras(own.specs).contains { $0.contains("alexa 65") })
    }

    func testOneFilmsOwnArticleIsReadInFull() {
        let (specs, craft) = read([text(["Doe shot the film on the Sony Venice 2 with Cooke S7/i lenses.",
                                         "Format: Digital Camera: Sony Venice 2 Lenses: Cooke S7/i"], source: "Lens Weekly")])
        XCTAssertTrue(specs.roundups.isEmpty)
        XCTAssertEqual(craft.shotOn, [.digital])
        XCTAssertEqual(craft.evidence(for: .digital)?.text, "Doe shot the film on the Sony Venice 2 with Cooke S7/i lenses.",
                       "said in so many words over the sheet")
    }

    func testThisFilmsOwnSheetBeatsAMention() {
        let (_, craft) = read([text(["Doe used the Alexa 65 for the night work.", "Cameras: Alexa 65 | Lenses: Moviecam | Format: 2.39:1"], source: "Lens Weekly")])
        XCTAssertEqual(craft.evidence(for: .digital)?.text, "Cameras: Alexa 65 | Lenses: Moviecam | Format: 2.39:1")
    }

    // MARK: The strongest reason

    /// The lab's story: a sentence about capturing the film in IMAX, then one about lenses that would
    /// be used on the IMAX cameras. The first is the reason, though the second names camera models.
    func testCapturingTheFilmInIMAXBeatsLensesThatWouldBeUsed() {
        let lab = text([
            "\"It's an intimate drama,\" says cinematographer Jane Doe, as she reveals details about capturing Carl Example's thriller, The Quiet Harbour, in IMAX (15-perf) format using KODAK 65mm large-format film, including, for the very first time, sections on 65mm B&W shot in IMAX.",
            "Such close focus lenses are not readily available off-the-shelf, and Doe turned to Panavision to deliver a range of optics – including Hasselblad and Panavision System 65 lenses – that would be used on the IMAX MKIV, IMAX MSM 9802 and Panavision Panaflex System 65 Studio cameras during production.",
        ], source: "Stock House")
        let (_, craft) = read([lab])
        XCTAssertTrue(craft.shotOn.contains(.imax))
        let why = craft.evidence(for: .imax)
        XCTAssertTrue(why?.text.contains("capturing Carl Example's thriller, The Quiet Harbour, in IMAX") ?? false, "\(why?.text ?? "")")
        XCTAssertEqual(why?.source, "Stock House")
        XCTAssertEqual(why?.shotOn, .imax, "the reason is for the tag it's shown with")
        XCTAssertEqual(craft.label(for: .imax), "IMAX", "scope not changed by guesswork")
        // Said in so many words beats both.
        let direct = read([text(["The Quiet Harbour was shot with IMAX cameras."], source: "Lens Weekly"), lab]).craft
        XCTAssertEqual(direct.evidence(for: .imax)?.text, "The Quiet Harbour was shot with IMAX cameras.")
    }

    func testWhatWouldBeUsedIsWeakerThanWhatWas() {
        let (_, craft) = read([text(["Doe said the Alexa 65 would be used for the night exteriors.",
                                     "Doe used the ARRI Alexa Mini for the interiors."], source: "Lens Weekly")])
        XCTAssertEqual(craft.evidence(for: .digital)?.text, "Doe used the ARRI Alexa Mini for the interiors.")
        XCTAssertTrue(TechSpecs.saidAsIntended("The lenses would be used on the IMAX cameras.",
                                               at: "The lenses would be used on the IMAX cameras.".range(of: "IMAX")!))
        XCTAssertFalse(TechSpecs.saidAsIntended("The lenses were used on the IMAX cameras.",
                                                at: "The lenses were used on the IMAX cameras.".range(of: "IMAX")!))
    }

    func testGeneralRemarksAndInterviewersStillArentReasons() {
        let (_, craft) = read([text(["BB: So you shot the film on 35mm film stock?",
                                     "Films that are shot on film feel different to an audience.",
                                     "The Quiet Harbour was shot on Kodak 5219."], source: "Lens Weekly")])
        XCTAssertEqual(craft.evidence(for: .film)?.text, "The Quiet Harbour was shot on Kodak 5219.")
    }

    // MARK: What a reading couldn't examine

    private func details() -> TMDBMovieDetails {
        var details = TMDBMovieDetails(id: 11, title: "The Quiet Harbour", releaseDate: "2024-01-01")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Jane Doe", job: "Director of Photography")])
        return details
    }

    private let readPage = CameraReading.Source(title: "Harbour light", site: "Lens Weekly", url: URL(string: "https://lens.example/harbour")!,
                                                paragraphs: ["Doe shot The Quiet Harbour on Kodak 5219 with Panaflex cameras, in the harbour itself."])

    private func page(_ site: String, _ path: String) -> CameraReading.Source {
        CameraReading.Source(title: site, site: site, url: URL(string: "https://\(path)")!, paragraphs: [])
    }

    /// A reading of the made-up film with these pages not read.
    private func reading(skipped: [CameraReading.Skipped], unanswered: [String] = []) -> CraftReader.Reading {
        CraftReader.reading(of: details(), articleTitle: nil, article: nil,
                            reading: CameraReading(sources: [readPage], more: [], cinematographer: nil, unanswered: unanswered, skipped: skipped),
                            colour: nil)
    }

    private func skipped(_ site: String, _ path: String, _ failure: SourceFailure) -> CameraReading.Skipped {
        CameraReading.Skipped(source: page(site, path), reason: failure.reason, limit: failure.limit)
    }

    func testEveryPageReadIsFullCoverage() {
        let full = reading(skipped: [])
        XCTAssertEqual(full.index.coverage, .full)
        let merged = CraftIndex.merging(old: nil, new: full.index)
        XCTAssertTrue(CraftLog.stored(merged).contains("Complete: every page found was read"))
        // Another film's page, another craft's, one more than was read: not limits.
        let deliberate = reading(skipped: [CameraReading.Skipped(source: page("Lens Weekly", "lens.example/other"), reason: "another film of that title")])
        XCTAssertEqual(deliberate.index.coverage, .full)
    }

    func testAPageNotFoundOverHTTPSIsALimitNotARead() {
        let gone = SourceFailure.of(status: 404, data: Data(), requested: URL(string: "https://old.example/2008/harbour/page1.php")!, landed: nil)
        XCTAssertEqual(gone, .gone("not found over HTTPS (404)"), "what was seen, not that it's nowhere")
        let limited = reading(skipped: [skipped("Old Weekly", "old.example/2008/harbour/page1.php", gone!),
                                        skipped("Old Weekly", "old.example/2008/harbour/page2.php", gone!)])
        XCTAssertEqual(limited.index.limits.count, 2)
        XCTAssertEqual(limited.index.limits.first?.kind, .gone)
        XCTAssertEqual(limited.index.limits.first?.url, "https://old.example/2008/harbour/page1.php")
        XCTAssertEqual(limited.index.coverage, .limited)
        let merged = CraftIndex.merging(old: nil, new: limited.index)
        XCTAssertNil(merged.index.retryAt, "not retried soon: a page that isn't there")
        let log = CraftLog.stored(merged)
        XCTAssertTrue(log.contains("Complete, with limits: 2 pages found couldn't be examined: 2 gone: not found over HTTPS (404)."), log)
        XCTAssertFalse(log.contains("every page found was read"))
    }

    func testTimeoutsServerErrorsAndWaitsAreRetried() {
        for failure in [SourceFailure.unanswered("timed out"), .unanswered("the server failed (500)"), .wait("too many requests (429)")] {
            XCTAssertEqual(failure.limit, .unanswered)
            let partial = reading(skipped: [skipped("Slow Weekly", "slow.example/harbour", failure)], unanswered: ["Slow Weekly"])
            XCTAssertEqual(partial.index.coverage, .partial)
            let merged = CraftIndex.merging(old: nil, new: partial.index)
            XCTAssertNotNil(merged.index.retryAt)
            XCTAssertTrue(CraftLog.stored(merged).contains("Incomplete: Slow Weekly didn't answer."))
        }
    }

    func testRestrictedThinAndUnknownPagesAreLimits() {
        let refused = reading(skipped: [skipped("Members Weekly", "members.example/harbour", .restricted("refused (403): a sign-in, a paywall or access denied"))])
        XCTAssertEqual(refused.index.coverage, .limited)
        // A page that loaded with too little to read wasn't examined.
        let teaser = CameraReading.Source(title: "Teaser", site: "Thin Weekly", url: URL(string: "https://thin.example/a")!, paragraphs: ["Subscribe."])
        XCTAssertEqual(CameraSources.limit(page: teaser, failure: nil, otherFilm: false), .thin)
        XCTAssertNil(CameraSources.limit(page: teaser, failure: nil, otherFilm: true), "another film's page isn't a limit")
        let full = CameraReading.Source(title: "Harbour light", site: "Lens Weekly", url: URL(string: "https://lens.example/b")!,
                                        paragraphs: ["One.", "Two.", "Three."])
        XCTAssertNil(CameraSources.limit(page: full, failure: nil, otherFilm: false), "a page with text to read, skipped for another reason")
        XCTAssertEqual(CameraSources.limit(page: nil, failure: nil, otherFilm: false), .unknown, "a failure Reel can't name isn't a read")
        let thin = reading(skipped: [CameraReading.Skipped(source: teaser, reason: "too little text to read", limit: .thin)])
        XCTAssertEqual(thin.index.coverage, .limited)
        // A kind saved by a later Reel: never taken for a page read.
        let saved = #"{"site":"Future Weekly","url":"https://future.example/a","kind":"somethingNew","detail":"?"}"#
        let decoded = try? JSONDecoder().decode(CraftIndex.SourceLimit.self, from: Data(saved.utf8))
        XCTAssertEqual(decoded?.kind, .unknown)
        var withUnknown = readingIndex()
        withUnknown.limits = [decoded!]
        XCTAssertEqual(withUnknown.coverage, .limited)
    }

    private func readingIndex() -> CraftIndex { reading(skipped: []).index }

    func testLimitsSurviveSavingAndOlderReadingsOpen() throws {
        let index = reading(skipped: [skipped("Old Weekly", "old.example/a", .gone("not found over HTTPS (404)"))]).index
        let reopened = try JSONStore.decode(CraftIndex.self, from: JSONStore.encode(index))
        XCTAssertEqual(reopened.limits, index.limits)
        XCTAssertEqual(reopened.coverage, .limited)
        let older = #"{"version":9,"readAt":"2026-10-23T17:00:00Z","shotOn":["film"],"names":[],"sources":2,"discovery":2,"read":["Wikipedia"]}"#
        let old = try JSONStore.decode(CraftIndex.self, from: Data(older.utf8))
        XCTAssertEqual(old.limits, [])
        XCTAssertEqual(CraftQueue.state(craft: old, attempt: nil, hasFacts: true, inCollection: false), .olderRules, "read again by rules 10")
    }

    func testANewFailureReplacesAnEarlierFullReading() {
        let full = CraftIndex.merging(old: nil, new: reading(skipped: []).index).index
        XCTAssertEqual(full.coverage, .full)
        let gone = CraftIndex.merging(old: full, new: reading(skipped: [skipped("Old Weekly", "old.example/a", .gone("not found over HTTPS (404)"))]).index).index
        XCTAssertEqual(gone.coverage, .limited, "not the earlier reading's full coverage")
        let slow = CraftIndex.merging(old: full, new: reading(skipped: [skipped("Slow Weekly", "slow.example/a", .unanswered("timed out"))],
                                                              unanswered: ["Slow Weekly"]).index).index
        XCTAssertEqual(slow.coverage, .partial)
        // The site answers next time: its limit goes, and the reading is complete again.
        let answered = CraftIndex.merging(old: slow, new: reading(skipped: []).index).index
        XCTAssertEqual(answered.coverage, .full)
        XCTAssertNil(answered.retryAt)
        XCTAssertTrue(answered.limits.isEmpty)
    }

    func testSettingsCountsFullLimitedAndPartialApart() {
        func film(_ id: Int, _ craft: CraftIndex) -> FilmEntry {
            var entry = FilmEntry(driveID: "Main", relativePath: "\(id).mkv", fileName: "\(id).mkv", size: 1, modified: nil, addedAt: Date())
            entry.tmdb = TMDBMovieDetails(id: id, title: "Film \(id)")
            entry.funFacts = FunFacts(facts: [], articleTitle: nil, fetchedAt: Date())
            entry.craft = craft
            return entry
        }
        let full = CraftIndex.merging(old: nil, new: reading(skipped: []).index).index
        let limited = CraftIndex.merging(old: nil, new: reading(skipped: [skipped("Old Weekly", "old.example/a", .gone("not found over HTTPS (404)"))]).index).index
        let partial = CraftIndex.merging(old: nil, new: reading(skipped: [skipped("Slow Weekly", "slow.example/a", .unanswered("timed out"))],
                                                                unanswered: ["Slow Weekly"]).index).index
        let coverage = CraftQueue.coverage(of: [film(1, full), film(2, limited), film(3, partial)])
        XCTAssertEqual(coverage.read, 3)
        XCTAssertEqual(coverage.limited, 1)
        XCTAssertEqual(coverage.partial, 1)
        // Each film's log says what the counts say.
        XCTAssertTrue(CraftLog.stored(CraftIndex.Merged(index: full, carried: [], dropped: [])).contains("Complete: every page found was read"))
        XCTAssertTrue(CraftLog.stored(CraftIndex.Merged(index: limited, carried: [], dropped: [])).contains("Complete, with limits"))
        XCTAssertTrue(CraftLog.stored(CraftIndex.Merged(index: partial, carried: [], dropped: [])).contains("Incomplete"))
    }
}
