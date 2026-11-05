import XCTest
@testable import ReelCore

/// 1.10.9 review findings, each pinned by the reviewer's own kind of sentence or state: common prose
/// that isn't a denial, a plan or a habit; Shot on support per source; pending findings that stay
/// pending; retired names not brought back; bounded question context; VFX grounds; titles across a
/// sentence's end. Made-up films and people; real gear names.
final class ReviewRegressionTests: XCTestCase {
    func reason(_ sentence: String, _ gear: String, _ kind: TechSpecs.Kind) -> ClaimReason? {
        guard let range = sentence.range(of: gear) else { XCTFail("no \(gear) in \(sentence)"); return nil }
        return ClaimFrame.reason(sentence, at: range, kind: kind, name: gear)
    }

    // MARK: V1 — ordinary prose is not a denial, a plan, a test, a habit, scenery or a capability

    func testOrdinaryProseIsNotSetAside() {
        let cases: [(String, String, TechSpecs.Kind)] = [
            ("Steadicam wasn't the only tool; Doe used it for every corridor scene.", "Steadicam", .support),
            ("Most of the harbour scenes had already been shot on the Alexa 65 when the storm came.", "Alexa 65", .camera),
            ("Doe planned a single Technocrane move for the finale and pulled it off on the last night.", "Technocrane", .support),
            ("The studio wanted IMAX cameras for the finale and got them.", "IMAX", .camera),
            ("They tested everything and shot the film on Kodak 35mm.", "Kodak", .format),
            ("Compared with the first week, the Steadicam work in the corridors went much faster.", "Steadicam", .support),
            ("Doe generally shot handheld, with an Easyrig taking the weight.", "Easyrig", .support),
            ("His go-to lenses on the shoot were Cooke S4s.", "Cooke S4s", .lens),
            ("Everyone was on the Technocrane platform for the final shot.", "Technocrane", .support),
            ("The gaffer put SkyPanels on the car for the driving scenes.", "SkyPanels", .light),
            ("An Astera tube lit the character's face in the close-ups.", "Astera", .light),
            ("The light from the windows allows Doe's SkyPanels to blend in.", "SkyPanels", .light),
            ("We couldn't have done the stairwell shot without the Steadicam.", "Steadicam", .support),
            ("Doe didn't hesitate to put the Alexa 65 on a Technocrane.", "Alexa 65", .camera),
            ("Doe didn't hesitate to put the Alexa 65 on a Technocrane.", "Technocrane", .support),
        ]
        for (sentence, gear, kind) in cases {
            XCTAssertNil(reason(sentence, gear, kind), sentence)
        }
        // The narrowed patterns still catch what they're for.
        XCTAssertEqual(reason("We didn't use a Steadicam on the boat.", "Steadicam", .support), .denied)
        XCTAssertEqual(reason("We couldn't use the Technocrane in the alley.", "Technocrane", .support), .denied)
        XCTAssertEqual(reason("The Technocrane wasn't available for the night shoot.", "Technocrane", .support), .denied)
        XCTAssertEqual(reason("Doe planned a Technocrane move for the finale, but the weather closed in.", "Technocrane", .support), .abandonedPlan)
        XCTAssertEqual(reason("Doe usually shoots with Cooke S4s.", "Cooke S4s", .lens), .otherPractice)
        XCTAssertEqual(reason("The character keeps an old Bolex in the attic.", "Bolex", .camera), .environment)
        XCTAssertEqual(reason("The Alexa 35 offers 17 stops of dynamic range and ARRIRAW recording.", "ARRIRAW", .format), .productCapability)
    }

    func testNamedAsAnotherProductionIsNotEveryFilmNoun() {
        let regex = TechSpecs.namedAsAnotherProduction
        func matches(_ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
        for text in ["Her latest film was shot on the Alexa 35.", "On the location shoot they used SkyPanels.",
                     "In the finished film, the grain is visible.", "It was the first film Doe shot on 65mm.",
                     "For the short film sequence they used a Bolex."] {
            XCTAssertFalse(matches(text), text)
        }
        for text in ["Her graduation film was shot on 16mm.", "In 2007 Doe and Example collaborated on Glass Rivers.",
                     "On the bakery film, she used tungsten."] {
            XCTAssertTrue(matches(text), text)
        }
    }

    // MARK: V7 — a question's subject is bounded, and gear isn't a turn

    func testAQuestionsSubjectStopsWhereTheAnswerTurnsAway() {
        let paragraphs = ["Q: How did you light The Quiet Harbour?",
                          "We used SkyPanels through the high windows.",
                          "On Glass Rivers, she had used tungsten units instead.",
                          "The SkyPanels were dimmed to a tenth."]
        let anchors = PageContext.anchors(paragraphs, title: "The Quiet Harbour", otherTitles: [], people: ["Jane Doe"], acrossParagraphs: true)
        XCTAssertEqual(anchors[1].first, true, "the answer to a question about the film")
        XCTAssertEqual(anchors[2].first, false, "an answer turning to another production")
        XCTAssertEqual(anchors[3].first, false, "and nothing after it, until the film is named again")
        XCTAssertFalse(PageContext.turnsAway("On Alexa, we pushed the sensor to 1600 ISO."))
        XCTAssertFalse(PageContext.turnsAway("With Cooke lenses, she softened the faces."))
        XCTAssertFalse(PageContext.isQuestion("We shot everything on film. It was a long shoot and the harbour was cold every night. "
                                              + "Would we do it again? Who knows? Maybe we would, if someone asked us nicely enough?"))
        XCTAssertTrue(PageContext.isQuestion("Q: Why film?"))
    }

    // MARK: V8 — VFX grounds are read sentence by sentence

    func testNoEffectsIsNotReadAsEffects() {
        func relevance(_ sentences: [String]) -> ResearchContext.VFXRelevance {
            let texts = [TechSpecs.Text(source: "American Cinematographer", paragraphs: sentences, isInterview: false)]
            let specs = TechSpecs.read(texts: texts, cinematographers: [], directors: [], year: 2013, title: "The Long Quarantine", crew: [])
            return ResearchContext(crew: [], specs: specs, texts: texts).vfxRelevance
        }
        XCTAssertEqual(relevance(["No CGI shots were created for the film; every effect was done on set."]), .notApplicable)
        XCTAssertEqual(relevance(["The lighting was all practical."]), .unknown, "practical lighting says nothing of effects")
        XCTAssertEqual(relevance(["The stunts were all practical effects."]), .notApplicable)
        XCTAssertEqual(relevance(["The stunts were all practical, but a Glasgow studio composited 300 visual effects shots."]), .established)
    }

    // MARK: V13 — titles

    func testTitlesDontRunAcrossASentenceEnd() {
        XCTAssertFalse(TechSpecs.namesTitle("We left the harbour. Story meetings followed.", title: "Harbour Story"))
        XCTAssertTrue(TechSpecs.namesTitle("We shot Harbour Story in March.", title: "Harbour Story"))
        XCTAssertTrue(TechSpecs.namesTitle("Doe shot Salt And Pepper on film.", title: "Salt and Pepper"))
        XCTAssertTrue(TechSpecs.namesTitle("Doe shot Salt & Pepper on film.", title: "Salt and Pepper"))
        XCTAssertTrue(TechSpecs.namesTitle("Once Upon a Time... in Hollywood was shot on film.", title: "Once Upon a Time in Hollywood"))
        XCTAssertTrue(TechSpecs.namesTitle("Dr. Strangelove was shot in black and white.", title: "Dr. Strangelove"))
    }
}

/// Source reconciliation review findings (V2, V3, V4, V14, V15, order).
final class ReconciliationReviewTests: XCTestCase {
    let then = Date(timeIntervalSince1970: 1_790_000_000)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let lens = "Doe shot The Quiet Harbour on 35 mm film, and the Steadicam was avoided for the stairwells."
    let grip = "The Quiet Harbour was photographed on 35 mm negative throughout the winter shoot."

    func capture(_ evidence: String, _ source: String) -> TechSpecs.Spec {
        var spec = TechSpecs.Spec(kind: .format, name: "35 mm", evidence: evidence, source: source)
        spec.capture = true
        return spec
    }

    func input(accepted: [TechSpecs.Spec] = [], judged: [TechSpecs.Judgement] = [], mentioned: [TechSpecs.Spec] = [],
               shotOn: [ShotOn: CraftIndex.Evidence] = [:], read: [String: [String]] = [:], fetched: [String: [[String]]] = [:],
               unanswered: Set<String> = [], incomplete: Set<String> = []) -> SourceReconciliation.Input {
        SourceReconciliation.Input(accepted: accepted, judged: judged, mentioned: mentioned, shotOn: shotOn, read: read, fetched: fetched,
                                   unanswered: unanswered, incomplete: incomplete, rules: 18)
    }

    func previous(_ claims: [CraftIndex.Claim]) -> CraftIndex {
        var index = CraftIndex(readAt: then, shotOn: [], names: [])
        index.claims = claims
        return index
    }

    /// V2: a Shot on tag is supported once per source, and only gear that gives the tag speaks to it.
    func testAShotOnTagIsSupportedPerSourceAndOnlyByItsOwnGear() {
        let first = SourceReconciliation.reconcile(
            previous: nil,
            with: input(accepted: [capture(lens, "Lens Weekly"), capture(grip, "Grip Notes")],
                        shotOn: [.film: CraftIndex.Evidence(shotOn: .film, text: lens, source: "Lens Weekly")],
                        read: ["Lens Weekly": [lens], "Grip Notes": [grip]]), now: then)
        let tags = first.filter { $0.kind == "shotOn" && $0.name == ShotOn.film.rawValue }
        XCTAssertEqual(Set(tags.map(\.source)), ["Lens Weekly", "Grip Notes"], "one claim per source")

        // Read again: the Lens Weekly sentence is still there; only its Steadicam is denied. The tag
        // isn't retired by that, and Grip Notes (down) still supports it.
        let second = SourceReconciliation.reconcile(
            previous: previous(first),
            with: input(judged: [TechSpecs.Judgement(kind: .support, name: "Steadicam", evidence: lens, source: "Lens Weekly", reason: .denied)],
                        read: ["Lens Weekly": [lens]], unanswered: ["Grip Notes"]), now: now)
        let byLens = second.first { $0.kind == "shotOn" && $0.source == "Lens Weekly" }
        let byGrip = second.first { $0.kind == "shotOn" && $0.source == "Grip Notes" }
        XCTAssertNotEqual(byLens?.status, .retired, "a denied Steadicam doesn't speak to film")
        XCTAssertEqual(byGrip?.status, .carried)
        XCTAssertTrue(second.contains { $0.kind == "shotOn" && $0.supports })

        // Its own gear ruled out (another production's): retired, with that reason.
        let third = SourceReconciliation.reconcile(
            previous: previous(first),
            with: input(judged: [TechSpecs.Judgement(kind: .format, name: "35 mm", evidence: grip, source: "Grip Notes", reason: .otherProduction)],
                        read: ["Grip Notes": [grip]], unanswered: ["Lens Weekly"]), now: now)
        XCTAssertEqual(third.first { $0.kind == "shotOn" && $0.source == "Grip Notes" }?.status, .retired)
        XCTAssertEqual(third.first { $0.kind == "shotOn" && $0.source == "Lens Weekly" }?.status, .carried)
    }

    /// V3: pending stays pending — not retired while its passage is still there, not shown during an
    /// outage — and an incomplete page uses up no try.
    func testPendingStaysPendingAndIncompletePagesUseNoTry() {
        let pending = CraftIndex.Claim(name: "SkyPanels", kind: "light", text: grip, source: "Grip Notes", status: .pending,
                                       reason: "read again; not settled", since: then, rules: 18, misses: CraftIndex.maxRetries)
        let present = SourceReconciliation.reconcile(previous: previous([pending]),
                                                     with: input(fetched: ["Grip Notes": [["Opening.", grip, "Close."]]]), now: now)
        XCTAssertEqual(present.first?.status, .pending, "a passage still on the page isn't retired for want of a settled reading")
        let outage = SourceReconciliation.reconcile(previous: previous([pending]), with: input(unanswered: ["Grip Notes"]), now: now)
        XCTAssertEqual(outage.first?.status, .pending, "an outage doesn't bring it back")
        XCTAssertFalse(outage.first?.supports ?? true)
        let confirmed = CraftIndex.Claim(name: "SkyPanels", kind: "light", text: grip, source: "Grip Notes", status: .confirmed,
                                         since: then, rules: 18, misses: 1)
        let shell = SourceReconciliation.reconcile(previous: previous([confirmed]),
                                                   with: input(read: ["Grip Notes": ["Menu"]], incomplete: ["Grip Notes"]), now: now)
        XCTAssertEqual(shell.first?.status, .carried)
        XCTAssertEqual(shell.first?.misses, 1, "an incomplete page uses up no try")
    }

    /// The outcome is the same whatever order the reading's statements and the earlier findings come in.
    func testTheOutcomeDoesntDependOnInputOrder() {
        let a = CraftIndex.Claim(name: "SkyPanels", kind: "light", text: lens, source: "Lens Weekly", status: .confirmed, since: then, rules: 18)
        let b = CraftIndex.Claim(name: "SkyPanels", kind: "light", text: grip, source: "Grip Notes", status: .confirmed, since: then, rules: 18)
        let accepted = [TechSpecs.Spec(kind: .light, name: "SkyPanels", evidence: grip, source: "Grip Notes"), capture(lens, "Lens Weekly")]
        let judged = [TechSpecs.Judgement(kind: .light, name: "SkyPanels", evidence: lens, source: "Lens Weekly", reason: .otherProduction),
                      TechSpecs.Judgement(kind: .support, name: "Steadicam", evidence: lens, source: "Lens Weekly", reason: .denied)]
        let read = ["Lens Weekly": [lens], "Grip Notes": [grip]]
        func summary(_ claims: [CraftIndex.Claim]) -> Set<String> { Set(claims.map { "\($0.kind)|\($0.name)|\($0.source)|\($0.status)|\($0.reason ?? "")" }) }
        let one = SourceReconciliation.reconcile(previous: previous([a, b]), with: input(accepted: accepted, judged: judged, read: read), now: now)
        let two = SourceReconciliation.reconcile(previous: previous([b, a]),
                                                 with: input(accepted: accepted.reversed(), judged: judged.reversed(), read: read), now: now)
        XCTAssertEqual(summary(one), summary(two))
        XCTAssertEqual(one.first { $0.source == "Lens Weekly" && $0.kind == "light" }?.status, .retired)
        XCTAssertEqual(one.first { $0.source == "Grip Notes" && $0.kind == "light" }?.status, .confirmed)
    }

    /// V4: a carried tag brings its reading's names back, but not one this reading retired or left pending.
    func testCarryingATagDoesntBringBackAWithdrawnName() {
        let old = CraftIndex(readAt: then, shotOn: [.film], names: ["35 mm", "Technocrane", "SkyPanels"],
                             evidence: [CraftIndex.Evidence(shotOn: .film, text: lens, source: "Lens Weekly")], read: ["Lens Weekly"])
        var new = CraftIndex(readAt: now, shotOn: [], names: [], unanswered: ["Lens Weekly"])
        new.claims = [CraftIndex.Claim(name: "Technocrane", kind: "support", text: grip, source: "Grip Notes", status: .retired,
                                       reason: ClaimReason.otherProduction.label, since: then, rules: 18)]
        let merged = CraftIndex.merging(old: old, new: new, now: now)
        XCTAssertEqual(merged.index.shotOn, [.film], "carried while its site is down")
        XCTAssertTrue(merged.index.names.contains("SkyPanels"))
        XCTAssertFalse(merged.index.names.contains("Technocrane"), "retired by this reading")
    }

    /// V14, V15: an unknown status reads as pending; names match exactly or by a plural.
    func testUnknownStatusesAndNameForms() throws {
        let json = #"{"name":"SkyPanels","kind":"light","source":"Grip Notes","status":"superseded","since":0,"rules":19,"misses":0}"#
        let claim = try JSONDecoder().decode(CraftIndex.Claim.self, from: Data(json.utf8))
        XCTAssertEqual(claim.status, .pending)
        XCTAssertFalse(SourceReconciliation.sameName("Alexa Mini", "Alexa Mini LF"))
        XCTAssertTrue(SourceReconciliation.sameName("SkyPanel", "SkyPanels"))
        XCTAssertTrue(SourceReconciliation.sameName("Cooke S4", "Cooke S4"))
    }
}
