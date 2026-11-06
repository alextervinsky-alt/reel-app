import XCTest
@testable import ReelCore

/// 1.10.10: what earlier readings recorded is kept until it's disproved (legacy findings, abstentions,
/// article identity), the library is upgraded from format 5 safely, and the retry schedule is the one
/// the code says.
final class KnowledgeIntegrityTests: XCTestCase {
    let then = Date(timeIntervalSince1970: 1_790_000_000)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func input(accepted: [TechSpecs.Spec] = [], judged: [TechSpecs.Judgement] = [], read: [String: [String]] = [:],
               articles: Set<String> = [], unanswered: Set<String> = []) -> SourceReconciliation.Input {
        var input = SourceReconciliation.Input(accepted: accepted, judged: judged, mentioned: [], shotOn: [:], read: read, fetched: [:],
                                               unanswered: unanswered, incomplete: [], rules: 19)
        input.articles = articles
        return input
    }

    func previous(_ claims: [CraftIndex.Claim]) -> CraftIndex {
        var index = CraftIndex(readAt: then, shotOn: [], names: claims.map(\.name))
        index.claims = claims
        return index
    }

    // MARK: Legacy findings

    func testALegacyFindingIsKeptReadingAfterReadingUntilConfirmedOrDenied() {
        let legacy = CraftIndex.Claim(name: "Technocrane", kind: "name", text: nil, source: "", status: .pending, since: then, rules: 17)
        var index = previous([legacy])
        // Ten readings that don't mention it: kept, shown apart, never retired, no tries used.
        for _ in 0..<10 {
            let claims = SourceReconciliation.reconcile(previous: index, with: input(read: ["Wikipedia": ["Nothing about cranes."]]), now: now)
            XCTAssertEqual(claims.first?.status, .legacy)
            XCTAssertEqual(claims.first?.misses, 0)
            XCTAssertTrue(claims.first?.awaitingVerification ?? false)
            XCTAssertFalse(claims.first?.supports ?? true, "not shown as found")
            index = previous(claims)
        }
        // A reading that accepts it confirms it.
        let found = "The Technocrane carried the camera over the crowd."
        let confirmed = SourceReconciliation.reconcile(
            previous: index,
            with: input(accepted: [TechSpecs.Spec(kind: .support, name: "Technocrane", evidence: found, source: "Lens Weekly")],
                        read: ["Lens Weekly": [found]]), now: now)
        XCTAssertTrue(confirmed.contains { $0.name == "Technocrane" && $0.status == .confirmed })
        // A reading whose own text denies it retires it, with the reason.
        let denial = "We never used a Technocrane."
        let denied = SourceReconciliation.reconcile(
            previous: index,
            with: input(judged: [TechSpecs.Judgement(kind: .support, name: "Technocrane", evidence: denial, source: "Lens Weekly", reason: .denied)],
                        read: ["Lens Weekly": [denial]]), now: now)
        XCTAssertEqual(denied.first?.status, .retired)
        XCTAssertTrue(denied.first?.reason?.hasPrefix(ClaimReason.denied.label) ?? false)
        // Another reason (another production, say) doesn't retire a finding it can't be tied to.
        let other = SourceReconciliation.reconcile(
            previous: index,
            with: input(judged: [TechSpecs.Judgement(kind: .support, name: "Technocrane", evidence: "On Glass Rivers we had a Technocrane.",
                                                     source: "Lens Weekly", reason: .otherProduction)],
                        read: ["Lens Weekly": ["On Glass Rivers we had a Technocrane."]]), now: now)
        XCTAssertEqual(other.first?.status, .legacy)
    }

    func testAnAbstentionDisprovesNothing() {
        let passage = "It was presented in its theatrical 2.35:1 widescreen aspect ratio."
        let old = CraftIndex.Claim(name: "2.35:1", kind: "format", text: passage, source: "Lens Weekly", status: .confirmed, since: then, rules: 18)
        let claims = SourceReconciliation.reconcile(
            previous: previous([old]),
            with: input(judged: [TechSpecs.Judgement(kind: .format, name: "2.35:1", evidence: passage, source: "Lens Weekly", reason: .presentation)],
                        read: ["Lens Weekly": [passage]]), now: now)
        XCTAssertEqual(claims.first?.status, .pending, "held back, not retired")
        XCTAssertTrue(claims.first?.awaitingVerification ?? false)
    }

    // MARK: Article identity

    func testAnotherArticleOfTheSameSiteIsNotAReadingOfThisOne() {
        let passage = "We lit the courtroom with SkyPanels through the high windows."
        let article = CraftIndex.articleIdentity(URL(string: "https://www.lensweekly.example/quiet-harbour/")!)
        XCTAssertEqual(article, CameraSources.identity(URL(string: "https://www.lensweekly.example/quiet-harbour/")!))
        XCTAssertEqual(CraftIndex.articleIdentity(URL(string: "http://lensweekly.example/quiet-harbour")!), article)
        let old = CraftIndex.Claim(name: "SkyPanels", kind: "light", text: passage, source: "Lens Weekly", status: .confirmed, since: then, rules: 18,
                                   article: article)
        // This reading read a different Lens Weekly article: the finding's own article wasn't read.
        let claims = SourceReconciliation.reconcile(
            previous: previous([old]),
            with: input(read: ["Lens Weekly": ["An interview about another film entirely."]], articles: ["lensweekly.example/other-film"]), now: now)
        XCTAssertEqual(claims.first?.status, .carried)
        XCTAssertEqual(claims.first?.misses, 0, "no try used: a reading that didn't read its article can't settle it")
        // Its own article read in full, and the passage gone: pending, then retired after `maxRetries`.
        var index = previous([old])
        var last: CraftIndex.Claim?
        for _ in 0...CraftIndex.maxRetries {
            let read = SourceReconciliation.reconcile(previous: index, with: input(read: ["Lens Weekly": ["The page now says nothing of lights."]],
                                                                                    articles: [article]), now: now)
            last = read.first
            index = previous(read)
        }
        XCTAssertEqual(last?.status, .retired)
        // The same name in two articles of one site is two findings (dedup by name, source and article).
        let a = CraftIndex.Claim(name: "SkyPanels", kind: "light", text: passage, source: "Lens Weekly", status: .confirmed, since: then, rules: 19, article: "a")
        let b = CraftIndex.Claim(name: "SkyPanels", kind: "light", text: passage, source: "Lens Weekly", status: .confirmed, since: then, rules: 19, article: "b")
        XCTAssertNotEqual(a.key, b.key)
        XCTAssertNotEqual(a.fingerprint, b.fingerprint)
    }

    // MARK: Library format 6

    /// A library as an earlier Reel wrote it: built here, then given the older version number (and a
    /// status, for a newer Reel's file).
    func libraryJSON(version: Int, status: String, text: String?) -> Data {
        var film = FilmEntry(driveID: "d1", relativePath: "A/a.mkv", fileName: "a.mkv", size: 1, modified: nil, addedAt: then)
        var craft = CraftIndex(readAt: then, shotOn: [], names: ["Technocrane"])
        craft.claims = [CraftIndex.Claim(name: "Technocrane", kind: "name", text: text, source: text == nil ? "" : "Lens Weekly",
                                         status: .pending, since: then, rules: 17, misses: 2)]
        film.craft = craft
        var json = String(decoding: try! JSONStore.encode(LibraryFile(films: [film])), as: UTF8.self)
        json = json.replacingOccurrences(of: "\"version\":\(LibraryFile.currentVersion)", with: "\"version\":\(version)")
        json = json.replacingOccurrences(of: "\"status\":\"pending\"", with: "\"status\":\"\(status)\"")
        return Data(json.utf8)
    }

    func testAVersionFiveLibraryIsUpgradedWithoutLosingAnything() throws {
        let opening = LibraryOpening.decide(libraryJSON(version: 5, status: "pending", text: nil))
        guard case .loaded(let file) = opening else { return XCTFail("not loaded: \(opening)") }
        XCTAssertEqual(file.version, 6)
        XCTAssertTrue(opening.writable)
        let claim = try XCTUnwrap(file.films.first?.craft?.claims?.first)
        XCTAssertEqual(claim.status, .legacy)
        XCTAssertEqual(claim.misses, 0)
        XCTAssertEqual(claim.name, "Technocrane")
        XCTAssertEqual(file.films.first?.craft?.names, ["Technocrane"])
        // Upgrading again changes nothing; writing and reading back keeps it.
        XCTAssertEqual(LibraryMigration.upgrade(file), file)
        let written = try JSONStore.encode(LibraryFile(films: file.films, writtenBy: "1.10.10 (999)", scans: ["d1": .init(at: now, complete: true, films: 1)]))
        guard case .loaded(let again) = LibraryOpening.decide(written) else { return XCTFail() }
        XCTAssertEqual(again.films, file.films)
        XCTAssertEqual(again.writtenBy, "1.10.10 (999)")
        XCTAssertEqual(again.scans?["d1"]?.complete, true)
        // One 1.10.9 retired only because it couldn't be confirmed without a passage is restored, as legacy.
        var retired = String(decoding: libraryJSON(version: 5, status: "retired", text: nil), as: UTF8.self)
        retired = retired.replacingOccurrences(of: "\"misses\":2", with: "\"misses\":5,\"reason\":\"found by rules 17; no passage was kept to read again; not settled in 4 readings\"")
        guard case .loaded(let restored) = LibraryOpening.decide(Data(retired.utf8)) else { return XCTFail() }
        XCTAssertEqual(restored.films.first?.craft?.claims?.first?.status, .legacy)
        // A pending finding with its passage is left pending.
        guard case .loaded(let kept) = LibraryOpening.decide(libraryJSON(version: 5, status: "pending", text: "We had a Technocrane.")) else { return XCTFail() }
        XCTAssertEqual(kept.films.first?.craft?.claims?.first?.status, .pending)
    }

    /// An interrupted upgrade: the upgrade happens in memory on opening and reaches the disk only through
    /// the ordinary atomic save. Until then the version 5 file is as it was, and opening it again
    /// upgrades it again, to the same result.
    func testAnInterruptedUpgradeIsSimplyDoneAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("reel-upgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Library.json")
        let original = libraryJSON(version: 5, status: "pending", text: nil)
        try original.write(to: url)
        let first = LibraryOpening.open(url)
        // (Quit before saving.)
        XCTAssertEqual(try Data(contentsOf: url), original, "opening never writes")
        let second = LibraryOpening.open(url)
        XCTAssertEqual(first, second)
        // The save completes: version 6 on disk, read back the same.
        try JSONStore.save(LibraryFile(films: second.films), to: url)
        guard case .loaded(let saved) = LibraryOpening.open(url) else { return XCTFail() }
        XCTAssertEqual(saved.version, 6)
        XCTAssertEqual(saved.films, second.films)
    }

    func testANewerLibraryIsNeverWritten() {
        let opening = LibraryOpening.decide(libraryJSON(version: 7, status: "someNewStatus", text: nil))
        guard case .newer(let version, let file) = opening else { return XCTFail("\(opening)") }
        XCTAssertEqual(version, 7)
        XCTAssertFalse(opening.writable)
        // An unknown status reads as pending: kept, not shown as found.
        XCTAssertEqual(file?.films.first?.craft?.claims?.first?.status, .pending)
    }

    // MARK: The retry schedule

    /// The schedule as the code has it (`CraftIndex.retryDelay`), which the handoff documents: a reading
    /// with a site that didn't answer is tried again after 6 hours, 1 day, 3 days, 7 days, then every 30
    /// days; a reading complete but for a carried finding, after 7 days.
    func testTheRetryScheduleIsTheDocumentedOne() {
        let hour: TimeInterval = 3600, day: TimeInterval = 86_400
        XCTAssertEqual((1...7).map { CraftIndex.retryDelay($0, unanswered: true) }, [6 * hour, day, 3 * day, 7 * day, 30 * day, 30 * day, 30 * day])
        XCTAssertEqual(CraftIndex.retryDelay(0, unanswered: true), 6 * hour)
        XCTAssertEqual(CraftIndex.retryDelay(1, unanswered: false), 7 * day)
        XCTAssertEqual(CraftIndex.retryDelay(9, unanswered: false), 7 * day)
        XCTAssertEqual(CraftIndex.maxRetries, 4)
        // retryAt follows it: a first reading with a site down is read again 6 hours later.
        var index = CraftIndex(readAt: now, shotOn: [], names: [])
        index.unanswered = ["IndieWire"]
        let merged = CraftIndex.merging(old: nil, new: index, now: now)
        XCTAssertEqual(merged.index.retryAt, now.addingTimeInterval(6 * hour))
    }
}

/// 1.10.10: the clause model and the stage of a ratio, on their own.
final class ClauseModelTests: XCTestCase {
    func roles(_ sentence: String) -> [(ClauseMap.Role, String)] {
        let map = ClauseMap(sentence)
        return map.clauses.map { ($0.role, map.text($0).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))) }
    }

    func testRelativeAppositiveDashesAndComparisonsAreDependent() {
        let relative = roles("Colourist Ada Bloom at Lumen Lab, who has also worked on Quiet Fields, shaped the final look.")
        XCTAssertTrue(relative.contains { $0.0 == .relative && $0.1.contains("Quiet Fields") })
        XCTAssertTrue(relative.contains { $0.0 == .main && $0.1.contains("Colourist Ada Bloom") })
        let appositive = roles("The primary aspect ratio was 2:1, a tribute to Ann Vale's Glass Rivers, with select scenes at 1.43:1.")
        XCTAssertTrue(appositive.contains { $0.0 == .appositive && $0.1.contains("tribute") })
        let dashes = roles("As on Glass Rivers – their previous collaboration – Doe opted for 35mm.")
        XCTAssertEqual(dashes.first?.0, .comparison)
        XCTAssertTrue(dashes.contains { $0.0 == .main && $0.1.contains("Doe opted for 35mm") })
        // A time apart isn't a comparison: it governs what follows.
        XCTAssertFalse(roles("When I was in France working on Glass Rivers, I was into bleach bypass.").contains { $0.0 == .comparison })
    }

    func testARelativeClauseAboutAnotherProductionsNameIsThatProductions() {
        let sentence = "The streets had a glow which recalled scenes from Ann Vale's Glass Rivers, which was shot in candlelight."
        let production = ClauseProduction(sentence) { TechSpecs.aboutOtherFilm($0, year: 2024, people: [], title: "Harbour") }
        let offset = sentence.distance(from: sentence.startIndex, to: sentence.range(of: "candlelight")!.lowerBound)
        XCTAssertTrue(production.isOther(offset..<(offset + 11)))
    }

    func stage(_ sentence: String, _ ratio: String) -> FormatStage? {
        FormatStage.of(sentence, at: sentence.range(of: ratio)!, name: ratio)
    }

    func testTheStageOfARatio() {
        XCTAssertEqual(stage("Shooting full-frame 5K, but with a widescreen 2.39:1 extraction.", "2.39:1"), .extraction)
        XCTAssertEqual(stage("For sequences designed to be 2.39:1 in any presentation, he chose anamorphic lenses.", "2.39:1"), .sequence)
        XCTAssertEqual(stage("The primary aspect ratio was 2:1.", "2:1"), .framing)
        XCTAssertEqual(stage("Those shots were cropped to match the 2.39:1 aspect ratio of the rest of the movie.", "2.39:1"), .extraction)
        XCTAssertEqual(stage("The home release presents the film in 2.35:1.", "2.35:1"), .homeMedia)
        XCTAssertEqual(stage("The 4K restoration is in 1.66:1.", "1.66:1"), .restoration)
        XCTAssertEqual(stage("We shot in 1.85:1.", "1.85:1"), .capture)
        XCTAssertEqual(stage("It was released theatrically in 1.85:1.", "1.85:1"), .theatrical)
        // Not said: no stage is guessed.
        XCTAssertNil(stage("It was presented in its 2.35:1 widescreen aspect ratio.", "2.35:1"))
        XCTAssertFalse(FormatStage.homeMedia.isFilmImage)
        XCTAssertTrue(FormatStage.extraction.isFilmImage)
    }
}
