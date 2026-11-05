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

    /// Round 2: vendor credits, negations with exceptions, a negated object that isn't the gear.
    func testVendorCreditsAndNegationExceptionsAreNotSetAside() {
        let cases: [(String, String, TechSpecs.Kind)] = [
            ("Panavision provided the C-series anamorphic lenses and two Millennium XL2 bodies.", "Millennium XL2", .camera),
            ("Panavision Woodland Hills provided the Primo 70 lenses.", "Primo 70", .lens),
            ("Keslow Camera provided the Alexa Mini LF.", "Alexa Mini LF", .camera),
            ("ARRI Rental supplied the Alexa 65 and delivered the Prime 65 lenses.", "Prime 65", .lens),
            ("The camera department delivers the Alexa Mini LF to set every morning.", "Alexa Mini LF", .camera),
            ("The lens package offered a choice of Cooke S4s and Panavision Primos.", "Cooke S4s", .lens),
            ("It allowed Doe to use SkyPanels everywhere.", "SkyPanels", .light),
            ("We didn't use any lights except a single SkyPanel.", "SkyPanel", .light),
            ("Doe didn't bring anything other than the Alexa Mini and two Cooke primes.", "Alexa Mini", .camera),
            ("We didn't need more than two SkyPanels for the kitchen.", "SkyPanels", .light),
            ("Doe wouldn't shoot on anything other than 35mm film.", "35mm", .format),
            ("We didn't have a big crew on the Technocrane days.", "Technocrane", .support),
            ("We didn't want anything fancy, so a single Steadicam did most of the work.", "Steadicam", .support),
            ("We shot the night scenes without a permit on the Alexa Mini.", "Alexa Mini", .camera),
        ]
        for (sentence, gear, kind) in cases {
            XCTAssertNil(reason(sentence, gear, kind), sentence)
        }
        // Another production's habit or a period's practice is still set aside.
        let practice: [(String, String, TechSpecs.Kind)] = [
            ("His usual lenses are Cooke S4s, but for this film he chose Panavision Primos.", "Cooke S4s", .lens),
            ("Her go-to camera is the Alexa Mini, but this time she chose the Sony Venice.", "Alexa Mini", .camera),
            ("Doe normally shoots on the Alexa Mini, but here she chose the Venice.", "Alexa Mini", .camera),
            ("Everyone shot on film back then; Doe shot this one digitally.", "film", .format),
            ("In the seventies everyone shot anamorphic.", "anamorphic", .lens),
        ]
        for (sentence, gear, kind) in practice {
            XCTAssertEqual(reason(sentence, gear, kind), .otherPractice, sentence)
        }
        // …and the film's own choice in the same sentence stands.
        XCTAssertNil(reason("His usual lenses are Cooke S4s, but for this film he chose Panavision Primos.", "Panavision Primos", .lens))
    }

    /// Round 3: lists stay lists, a missing budget is still a reason, scenery stays scenery, "we
    /// generally use" is this production, and a product the production used isn't a capability.
    func testRoundThreeContaminationPaths() {
        XCTAssertEqual(reason("Doe avoided zooms, Steadicam, and drones.", "drones", .support), .denied)
        XCTAssertEqual(reason("We didn't use cranes, dollies, and Steadicam.", "Steadicam", .support), .denied)
        XCTAssertNil(reason("We didn't use the crane, and the crew relied on a Technocrane instead.", "Technocrane", .support))
        XCTAssertEqual(reason("We didn't have the budget for the Technocrane.", "Technocrane", .support), .denied)
        XCTAssertEqual(reason("We didn't have the time or the space for a Technocrane.", "Technocrane", .support), .denied)
        XCTAssertEqual(reason("We didn't have the crew for the Technocrane.", "Technocrane", .support), .denied)
        XCTAssertEqual(reason("We didn't have the clearance for the drone.", "drone", .support), .denied)
        // "didn't need X for the gear" says the gear was used.
        XCTAssertNil(reason("We didn't need any special rigging for the Technocrane.", "Technocrane", .support))
        XCTAssertNil(reason("We didn't need extra insurance for the Alexa 65.", "Alexa 65", .camera))
        XCTAssertNil(reason("We didn't need much time for the Technocrane setups.", "Technocrane", .support))
        // Indifference is not a statement of use (1.10.8's intended removal on a period-film page).
        XCTAssertEqual(reason("Whether we shoot with a crane or dolly or whatever is less of a concern than achieving what he has on his list.", "crane", .support), .hypothetical)
        XCTAssertEqual(reason("Whether we shoot with a crane or dolly or whatever is less of a concern than achieving what he has on his list.", "dolly", .support), .hypothetical)
        XCTAssertNil(reason("Whether shooting day or night, we used SkyPanels above the dock.", "SkyPanels", .light))
        XCTAssertEqual(reason("The art department dressed the diner with Astera tubes as set dressing.", "Astera", .light), .environment)
        XCTAssertEqual(reason("The house has neon signs and Astera tubes strung along the porch.", "Astera", .light), .environment)
        XCTAssertNil(reason("On set we generally use two SkyPanels as a key.", "SkyPanels", .light))
        XCTAssertNil(reason("We always shoot with two cameras on this show, both Alexa Minis.", "Alexa Minis", .camera))
        XCTAssertEqual(reason("Doe tends to use Cooke S4s.", "Cooke S4s", .lens), .otherPractice)
        XCTAssertNil(reason("The Alexa Mini can record ProRes, and Doe used that for the dailies.", "ProRes", .format))
        // A time spent on another production: "When I was in France working on <Other>…".
        let other = TechSpecs.read(texts: [TechSpecs.Text(source: "Lens Weekly", paragraphs: [
            "When I was in France working on Glass Rivers with Carl Example, I was very into desaturation with a bleach-bypass process."])],
                                   cinematographers: ["Jane Doe"], directors: ["Carl Example"], year: 2022, title: "The Quiet Harbour")
        XCTAssertFalse(other.specs.contains { $0.name.lowercased().contains("bleach") }, "\(other.specs.map(\.name))")
        // A real trailing comparison after an opening one is still set aside.
        let both = ComparisonFrame("Just as he had on Glass Rivers, Doe shot The Quiet Harbour on 500T, as he did on Salt Marsh with Kodak 5207.",
                                   title: "The Quiet Harbour", otherTitles: ["Glass Rivers", "Salt Marsh"])
        XCTAssertEqual(both.spans.count, 2)
        XCTAssertFalse(both.main.contains("5207"))
        XCTAssertTrue(both.main.contains("500T"))
        for text in ["For the underwater shoot, they used a Hydroflex housing on the Alexa Mini.", "For the aerial shoot, they used a Shotover F1.",
                     "For the opening film sequence, they used a Bolex.", "On the debut film, she used SkyPanels.",
                     "For the biographical film, Doe chose the Alexa 35."] {
            XCTAssertFalse(TechSpecs.describesAnotherFilm(text, title: "Fieldnote"), text)
        }
    }

    /// The same statements read whole: the gear isn't judged away.
    func testVendorCreditsSurviveTheWholeReading() {
        let sentences = ["Panavision provided the C-series anamorphic lenses and two Millennium XL2 bodies for The Quiet Harbour.",
                         "Keslow Camera provided the Alexa Mini LF that Jane Doe used for The Quiet Harbour."]
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: "Lens Weekly", paragraphs: sentences)], cinematographers: ["Jane Doe"],
                                   directors: ["Carl Example"], year: 2022, title: "The Quiet Harbour")
        XCTAssertFalse(specs.judged.contains { $0.reason == .productCapability }, "\(specs.judged.map { "\($0.name): \($0.reason)" })")
        let practice = TechSpecs.read(texts: [TechSpecs.Text(source: "Lens Weekly", paragraphs: [
            "Jane Doe's usual lenses are Cooke S4s, but for The Quiet Harbour she chose Panavision Primos."])],
                                      cinematographers: ["Jane Doe"], directors: ["Carl Example"], year: 2022, title: "The Quiet Harbour")
        XCTAssertFalse(practice.specs.contains { $0.name.lowercased().contains("cooke") }, "\(practice.specs.map(\.name))")
    }

    func testNamedAsAnotherProductionIsNotEveryFilmNoun() {
        let regex = TechSpecs.namedAsAnotherProduction
        func matches(_ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
        for text in ["Her latest film was shot on the Alexa 35.", "On the location shoot they used SkyPanels.",
                     "In the finished film, the grain is visible.", "It was the first film Doe shot on 65mm.",
                     "For the short film sequence they used a Bolex.", "For the war film, Doe chose the Alexa Mini LF.",
                     "On the musical feature, she used SkyPanels.", "They shot on the reversal film Ektachrome 100D.",
                     "Kodak was selected for the motion picture."] {
            XCTAssertFalse(matches(text), text)
        }
        for text in ["Her graduation film was shot on 16mm.", "In 2007 Doe and Example collaborated on Glass Rivers.",
                     "Her previous feature, Glass Rivers, was shot on 16mm."] {
            XCTAssertTrue(matches(text), text)
        }
        // A production called by what it's about: another one, unless that's this film's title.
        XCTAssertTrue(TechSpecs.describesAnotherFilm("On the bakery film we used a single Kino Flo unit.", title: "Fieldnote"))
        XCTAssertFalse(TechSpecs.describesAnotherFilm("On the bakery film we used a single Kino Flo unit.", title: "Crosswind Bakery"))
        XCTAssertFalse(TechSpecs.describesAnotherFilm("For the war film, Doe chose the Alexa Mini LF.", title: "Fieldnote"))
        XCTAssertFalse(TechSpecs.describesAnotherFilm("Kodak was selected for the motion picture.", title: "Fieldnote"))
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
        XCTAssertEqual(relevance(["There was no CGI in the dogfights, though a Glasgow studio created 2,400 VFX shots for the film."]), .established)
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
        XCTAssertEqual(byLens?.status, .pending, "a denied Steadicam doesn't speak to film: not retired, not settled")
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
        XCTAssertEqual(shell.first?.misses, 2, "an incomplete page uses up a try, as for tags: a page that's always a shell doesn't keep it for good")
        let still = CraftIndex.Claim(name: "SkyPanels", kind: "light", text: grip, source: "Grip Notes", status: .carried,
                                     since: then, rules: 18, misses: CraftIndex.maxRetries)
        let given = SourceReconciliation.reconcile(previous: previous([still]),
                                                   with: input(read: ["Grip Notes": ["Menu"]], incomplete: ["Grip Notes"]), now: now)
        XCTAssertEqual(given.first?.status, .retired)
        let down = SourceReconciliation.reconcile(previous: previous([still]), with: input(unanswered: ["Grip Notes"]), now: now)
        XCTAssertEqual(down.first?.status, .carried, "a site that's down uses up no try")
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

    /// N4: a tag whose stored source is retired stands on another source still carried.
    func testATagStandsOnAnotherSourceStillCarried() {
        let old = CraftIndex(readAt: then, shotOn: [.film], names: ["35 mm"],
                             evidence: [CraftIndex.Evidence(shotOn: .film, text: lens, source: "Lens Weekly")], read: ["Lens Weekly", "Grip Notes"])
        var new = CraftIndex(readAt: now, shotOn: [], names: [], read: ["Lens Weekly"], unanswered: ["Grip Notes"])
        new.claims = [
            CraftIndex.Claim(name: ShotOn.film.rawValue, kind: "shotOn", text: lens, source: "Lens Weekly", status: .retired,
                             reason: ClaimReason.otherProduction.label, since: then, rules: 18),
            CraftIndex.Claim(name: ShotOn.film.rawValue, kind: "shotOn", text: grip, source: "Grip Notes", status: .carried,
                             reason: "Grip Notes didn't answer", since: then, rules: 18),
        ]
        let merged = CraftIndex.merging(old: old, new: new, now: now)
        XCTAssertEqual(merged.index.shotOn, [.film])
        XCTAssertEqual(merged.index.evidence.first?.source, "Grip Notes")
        // Without the other source, the retired one drops it.
        new.claims = [new.claims![0]]
        XCTAssertEqual(CraftIndex.merging(old: old, new: new, now: now).index.shotOn, [])
    }

    /// N12: a tag whose passage is still accepted but which this reading didn't settle on is pending,
    /// not silently dropped.
    func testATagNotSettledOnIsPending() {
        let first = CraftIndex.Claim(name: ShotOn.film.rawValue, kind: "shotOn", text: lens, source: "Lens Weekly", status: .confirmed,
                                     since: then, rules: 18)
        let result = SourceReconciliation.reconcile(previous: previous([first]),
                                                    with: input(accepted: [capture(lens, "Lens Weekly")], read: ["Lens Weekly": [lens]]), now: now)
        XCTAssertEqual(result.first { $0.kind == "shotOn" }?.status, .pending)
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
