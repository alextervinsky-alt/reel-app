import XCTest
@testable import ReelCore

/// 1.10.9: earlier findings, read again (`SourceReconciliation`). A reading never drops an earlier
/// finding just because its rules no longer extract it: each is settled by its own source.
final class SourceReconciliationTests: XCTestCase {
    let then = Date(timeIntervalSince1970: 1_790_000_000)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    let passage = "We lit the courtroom with SkyPanels through the high windows."
    let page = "https://example.org/the-quiet-harbour/"

    func claim(_ name: String, kind: String = "light", text: String?, source: String = "Lens Weekly", status: CraftIndex.Claim.Status = .confirmed,
               misses: Int = 0) -> CraftIndex.Claim {
        CraftIndex.Claim(name: name, kind: kind, text: text, source: source, status: status, since: then, rules: 17, misses: misses)
    }

    func previous(_ claims: [CraftIndex.Claim]) -> CraftIndex {
        var index = CraftIndex(readAt: then, shotOn: [], names: claims.map(\.name))
        index.claims = claims
        return index
    }

    func input(accepted: [TechSpecs.Spec] = [], judged: [TechSpecs.Judgement] = [], mentioned: [TechSpecs.Spec] = [],
               read: [String: [String]] = [:], fetched: [String: [[String]]] = [:], unanswered: Set<String> = [], incomplete: Set<String> = [])
        -> SourceReconciliation.Input {
        SourceReconciliation.Input(accepted: accepted, judged: judged, mentioned: mentioned, shotOn: [:], read: read, fetched: fetched,
                                   unanswered: unanswered, incomplete: incomplete, rules: 18)
    }

    func spec(_ name: String, evidence: String, source: String = "Lens Weekly") -> TechSpecs.Spec {
        TechSpecs.Spec(kind: .light, name: name, evidence: evidence, source: source)
    }

    func outcome(_ claims: [CraftIndex.Claim], _ name: String) -> CraftIndex.Claim? {
        claims.first { $0.name == name }
    }

    func testConfirmedAgainKeepsItsHistory() {
        let result = SourceReconciliation.reconcile(previous: previous([claim("SkyPanels", text: passage)]),
                                                    with: input(accepted: [spec("SkyPanels", evidence: passage)], read: ["Lens Weekly": [passage]]), now: now)
        XCTAssertEqual(outcome(result, "SkyPanels")?.status, .confirmed)
        XCTAssertEqual(outcome(result, "SkyPanels")?.since, then, "first found then")
        XCTAssertEqual(result.count, 1)
    }

    func testExplicitlyDisprovedIsRetiredWithItsReason() {
        let denied = "We avoided SkyPanels; the courtroom was lit with tungsten."
        let result = SourceReconciliation.reconcile(
            previous: previous([claim("SkyPanels", text: denied)]),
            with: input(judged: [TechSpecs.Judgement(kind: .light, name: "SkyPanels", evidence: denied, source: "Lens Weekly", reason: .denied)],
                        read: ["Lens Weekly": [denied]]), now: now)
        XCTAssertEqual(outcome(result, "SkyPanels")?.status, .retired)
        XCTAssertEqual(outcome(result, "SkyPanels")?.reason, ClaimReason.denied.label)
    }

    /// Sources are labelled by site, so a page read in full without the passage may be another article
    /// of that site: not shown at once, and retired ("no longer in …") when `maxRetries` readings in a
    /// row don't find it.
    func testAPassageNoLongerOnAFullyReadPageIsRetired() {
        let other = input(read: ["Lens Weekly": ["The page now says something else entirely about the courtroom."]])
        let first = SourceReconciliation.reconcile(previous: previous([claim("SkyPanels", text: passage)]), with: other, now: now)
        XCTAssertEqual(outcome(first, "SkyPanels")?.status, .pending)
        XCTAssertFalse(outcome(first, "SkyPanels")?.supports ?? true, "not shown")
        let last = SourceReconciliation.reconcile(previous: previous([claim("SkyPanels", text: passage, status: .pending, misses: CraftIndex.maxRetries)]),
                                                  with: other, now: now)
        XCTAssertEqual(outcome(last, "SkyPanels")?.status, .retired)
        XCTAssertTrue(outcome(last, "SkyPanels")?.reason?.contains("no longer") ?? false)
        // Found again in the meantime: confirmed.
        let back = SourceReconciliation.reconcile(previous: previous([claim("SkyPanels", text: passage, status: .pending, misses: 2)]),
                                                  with: input(accepted: [spec("SkyPanels", evidence: passage)], read: ["Lens Weekly": [passage]]), now: now)
        XCTAssertEqual(outcome(back, "SkyPanels")?.status, .confirmed)
    }

    func testAPassageThereButNotSettledIsPendingNotDropped() {
        // The page was fetched and set aside (e.g. judged a passing mention): the passage is there,
        // but these rules didn't tie it to the film or rule it out.
        let result = SourceReconciliation.reconcile(previous: previous([claim("SkyPanels", text: passage)]),
                                                    with: input(fetched: ["Lens Weekly": [["Intro paragraph about the director.", passage, "More."]]]), now: now)
        XCTAssertEqual(outcome(result, "SkyPanels")?.status, .pending)
        XCTAssertFalse(outcome(result, "SkyPanels")?.supports ?? true, "not shown as found")
    }

    func testAnUnavailableOrIncompleteSourceCarriesTheFinding() {
        let down = SourceReconciliation.reconcile(previous: previous([claim("SkyPanels", text: passage)]),
                                                  with: input(unanswered: ["Lens Weekly"]), now: now)
        XCTAssertEqual(outcome(down, "SkyPanels")?.status, .carried)
        XCTAssertEqual(outcome(down, "SkyPanels")?.misses, 0, "a site that's down doesn't use up a try")
        let shell = SourceReconciliation.reconcile(previous: previous([claim("SkyPanels", text: passage)]),
                                                   with: input(read: ["Lens Weekly": ["Menu", "Teaser"]], incomplete: ["Lens Weekly"]), now: now)
        XCTAssertEqual(outcome(shell, "SkyPanels")?.status, .carried, "an incomplete page isn't a full reading")
        // Carried only so long: a page not found again in four readings is retired.
        let gone = SourceReconciliation.reconcile(previous: previous([claim("SkyPanels", text: passage, status: .carried, misses: CraftIndex.maxRetries)]),
                                                  with: input(), now: now)
        XCTAssertEqual(outcome(gone, "SkyPanels")?.status, .retired)
    }

    func testIndependentSourcesKeepTheirOwnSupport() {
        let other = "Their gaffer rigged SkyPanels outside the courtroom windows."
        let result = SourceReconciliation.reconcile(
            previous: previous([claim("SkyPanels", text: passage), claim("SkyPanels", text: other, source: "Grip Notes")]),
            with: input(accepted: [spec("SkyPanels", evidence: other, source: "Grip Notes")],
                        judged: [TechSpecs.Judgement(kind: .light, name: "SkyPanels", evidence: passage, source: "Lens Weekly", reason: .otherProduction)],
                        read: ["Lens Weekly": [passage], "Grip Notes": [other]]), now: now)
        let lens = result.first { $0.source == "Lens Weekly" }, grip = result.first { $0.source == "Grip Notes" }
        XCTAssertEqual(lens?.status, .retired, "one source ruled out")
        XCTAssertEqual(grip?.status, .confirmed, "the other still supports it")
        // What's shown: supported by any source.
        XCTAssertTrue(result.contains { $0.name == "SkyPanels" && $0.supports })
    }

    func testTheOutcomeDoesntDependOnSourceOrder() {
        let a = claim("SkyPanels", text: passage)
        let b = claim("Kino Flos", text: "Kino Flos lit the corridor.", source: "Grip Notes")
        let input = self.input(accepted: [spec("Kino Flos", evidence: "Kino Flos lit the corridor.", source: "Grip Notes")],
                               read: ["Grip Notes": ["Kino Flos lit the corridor."]], unanswered: ["Lens Weekly"])
        let one = SourceReconciliation.reconcile(previous: previous([a, b]), with: input, now: now)
        let two = SourceReconciliation.reconcile(previous: previous([b, a]), with: input, now: now)
        XCTAssertEqual(Set(one.map { "\($0.name)|\($0.source)|\($0.status)" }), Set(two.map { "\($0.name)|\($0.source)|\($0.status)" }))
    }

    /// A reading from before 1.10.9 stored no passages for its gear names: those can only be
    /// confirmed again, never ruled out by a passage; until then they're pending, and retired after
    /// `maxRetries` readings that don't confirm them.
    func testANameFromBeforeIsPendingUntilConfirmed() {
        var old = CraftIndex(readAt: then, shotOn: [], names: ["Technocrane", "Kino Flos"])
        old.version = 17
        let result = SourceReconciliation.reconcile(previous: old, with: input(accepted: [spec("Kino Flos", evidence: "Kino Flos lit the corridor.")],
                                                                               read: ["Lens Weekly": ["Kino Flos lit the corridor."]]), now: now)
        XCTAssertEqual(outcome(result, "Technocrane")?.status, .pending)
        XCTAssertEqual(outcome(result, "Kino Flos")?.status, .confirmed)
        XCTAssertEqual(result.filter { $0.name == "Kino Flos" }.count, 1, "confirmed once, not twice")
    }

    /// A rule change between versions: the old tag's own sentence is read again by the new rules. If
    /// it now says the gear wasn't this film's, the tag is retired with why; if the rules can't settle
    /// it, the tag is kept as pending and not shown, instead of silently disappearing.
    func testATagFoundByOldRulesIsReconciledNotSilentlyDropped() {
        var old = CraftIndex(readAt: then, shotOn: [.film], names: ["16 mm"],
                             evidence: [CraftIndex.Evidence(shotOn: .film, text: passage, source: "Lens Weekly")], read: ["Lens Weekly"])
        old.version = 17
        var new = CraftIndex(readAt: now, shotOn: [], names: [], read: ["Lens Weekly"])
        new.claims = SourceReconciliation.reconcile(previous: old, with: input(fetched: ["Lens Weekly": [["Opening.", passage, "Close."]]]), now: now)
        let merged = CraftIndex.merging(old: old, new: new, now: now)
        XCTAssertEqual(merged.index.shotOn, [], "not shown as found")
        XCTAssertTrue(merged.dropped.first?.reason.hasPrefix("pending reassessment") ?? false, "\(merged.dropped)")
        XCTAssertEqual(merged.index.claims?.first { $0.kind == "shotOn" }?.status, .pending, "kept, inspectable")
    }

    /// Migration: a version 4 library decodes as it is (no step to interrupt: claims are nil until
    /// each film is read again), and a decoded file not saved leaves the original untouched.
    func testAVersionFourLibraryReadsAsItIsAndAnInterruptedMigrationChangesNothing() throws {
        var craft = CraftIndex(readAt: then, shotOn: [.digital], names: ["ARRI Alexa 35"],
                               evidence: [CraftIndex.Evidence(shotOn: .digital, text: "Shot on the ARRI Alexa 35.", source: "Wikipedia")])
        craft.version = 17
        craft.discovery = 7
        var film = FilmEntry(driveID: "Main", relativePath: "Q.mkv", fileName: "Q.mkv", size: 1, modified: nil, addedAt: then)
        film.craft = craft
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(LibraryFile(films: [film]))) as? [String: Any])
        object["version"] = 4
        let original = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(LibraryFile.self, from: original)
        XCTAssertNil(decoded.films.first?.craft?.claims)
        XCTAssertEqual(decoded.films.first?.craft?.names, ["ARRI Alexa 35"])
        XCTAssertTrue(decoded.films.first?.craft?.isStale(now: now) ?? false, "read again by the new rules")
        // Interrupted before anything is written: the bytes on disk are what they were.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("reel-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Library.json")
        try original.write(to: file)
        _ = try JSONDecoder().decode(LibraryFile.self, from: Data(contentsOf: file))
        XCTAssertEqual(try Data(contentsOf: file), original)
        // Written by this Reel: version 5, which a 1.10.8 (version 4) Reel treats as newer and never writes over.
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(LibraryFile(films: decoded.films))) as? [String: Any])
        XCTAssertEqual(written["version"] as? Int, 5)
    }

    /// End to end through the reader: an earlier finding whose page is read again and now says it
    /// was another production's is retired, with the reason in the log.
    func testTheReaderReconcilesAgainstWhatItRead() throws {
        var details = TMDBMovieDetails(id: 1, title: "The Quiet Harbour", releaseDate: "2022-06-01")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Jane Doe", job: "Director of Photography")])
        let text = "On Glass Rivers (2019), Doe lit everything with SkyPanels."
        let source = CameraReading.Source(title: "Jane Doe on The Quiet Harbour", site: "American Cinematographer",
                                          url: URL(string: "https://theasc.com/article/the-quiet-harbour/")!,
                                          paragraphs: ["The Quiet Harbour was shot on the Sony Venice.", text, "It was a long shoot."])
        var old = CraftIndex(readAt: then, shotOn: [], names: ["SkyPanels"])
        old.claims = [claim("SkyPanels", text: text, source: "American Cinematographer")]
        let reading = CraftReader.reading(of: details, articleTitle: nil, article: nil, reading: CameraReading(sources: [source], more: [], cinematographer: nil),
                                          colour: nil, previous: old, now: now)
        let sky = reading.index.claims?.first { $0.name == "SkyPanels" }
        XCTAssertEqual(sky?.status, .retired, "\(String(describing: reading.index.claims))")
        XCTAssertFalse(reading.index.names.contains("SkyPanels"))
        XCTAssertTrue(reading.log.contains("EARLIER FINDINGS, READ AGAIN"))
    }
}
