import XCTest
@testable import ReelCore

/// Reel 1.10.3 (rules 12): whose a sentence's gear is, and what it says was used. The F1 and Barbie
/// sentences are short public excerpts from American Cinematographer's and British Cinematographer's
/// articles, as Reel read them; the rest are made up ("The Quiet Harbour", "Glass Rivers", Jane Doe).
/// Every rule tested here is general: nothing in Reel knows these titles.
final class ReadingRulesTests: XCTestCase {
    // MARK: Fixtures

    /// F1 (2025): Claudio Miranda, Joseph Kosinski.
    private func f1(_ texts: [(String, [String])]) -> (specs: TechSpecs, index: CraftIndex) {
        let read = texts.map { TechSpecs.Text(source: $0.0, paragraphs: $0.1) }
        let specs = TechSpecs.read(texts: read, cinematographers: ["Claudio Miranda"], directors: ["Joseph Kosinski"], year: 2025,
                                   title: "F1", otherTitles: [])
        return (specs, CraftIndex.make(from: specs, colour: nil, keywords: []))
    }

    private func quiet(_ sentences: [String], source: String = "American Cinematographer") -> (specs: TechSpecs, index: CraftIndex) {
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: source, paragraphs: sentences)], cinematographers: ["Jane Doe"],
                                   directors: ["Carl Example"], year: 2024, title: "The Quiet Harbour")
        return (specs, CraftIndex.make(from: specs, colour: nil, keywords: []))
    }

    /// Why the `occurrence`th time `words` are written in `sentence` is set aside (nil: it isn't).
    private func setAside(_ sentence: String, _ words: String, occurrence: Int = 1, title: String = "F1",
                          people: [String] = ["Claudio Miranda", "Claudio", "Miranda", "Joseph Kosinski", "Joseph", "Kosinski"])
        -> TechSpecs.Attribution? {
        var from = sentence.startIndex
        var found: Range<String.Index>?
        for _ in 0..<occurrence {
            guard let next = sentence.range(of: words, range: from..<sentence.endIndex) else { XCTFail("no \(words)"); return nil }
            found = next
            from = next.upperBound
        }
        return TechSpecs.setAside(sentence, at: found!, title: title, people: people)
    }

    private func allNames(_ specs: TechSpecs) -> [String] { specs.specs.map(\.name) }

    static let grandPrix = "Grand Prix is the touchstone — [that film was] shot at real events in a beautiful [Super Panavision 70] widescreen format with great compositions [by director of photography Lionel Lindon, ASC]."
    static let veniceCoverage = "In addition to the 25 network-controlled Carmens, Miranda used Sony Venice 2 bodies for traditional coverage and helicopter work, RED Komodos for plate shots, and DJI’s Ronin 4D — nicknamed “the turkey” by the crew for its unwieldy appearance — for handheld sequences in the pit lanes."
    static let iPhoneSensor = "Working with Apple, custom miniature cameras were developed combining an iPhone 12 sensor with the processing power of an iPhone 15, allowing the filmmakers to capture a signature angle during every F1 race broadcast—from an on-board camera pod on the side of the F1 car."
    static let notHitting = "“We’re not hitting the Imax film 1.43:1 ratio, although Joe thought a lot about it — on Top Gun: Maverick, we opened up to 1.43:1 in the aerial sequences — but this movie has so much racing that he found it hard to go in and out of different formats so often.”"
    static let fpv = "“Joe and I watched some FPV drone footage of races and got so turned off by the slickness of it,” Miranda observes."
    static let ronin = "The need to be nimble at races led the filmmakers to use a DJI Ronin 4D with Sony G Master lenses, with the crew controlling iris and focus remotely."
    static let eightSix = "For certain shots, including some helicopter footage, they shot at 8.6K 17:9 full frame in case the VFX team needed to do any replacement work."
    static let vfx24 = "“We’d ask them to shoot at 50 frames per second and open the shutter as much as possible which would mean the sponsor logos could go a bit blurry, but then we’d take their footage and run it through VFX to smooth it back to 24 frames per second.”"
    static let naturalLight = "Miranda’s lighting approach was just as meticulous, relying on natural light whenever possible."

    // MARK: A. Another film's: a reference, a comparison, another production

    /// F1's false Film tag: what "Grand Prix is the touchstone — [that film was] shot…" says is
    /// Grand Prix's, so Super Panavision 70 is neither a tag nor F1's gear; the Digital tag stays.
    func testWhatTheReferenceFilmWasShotOnIsNotThisFilms() {
        XCTAssertEqual(setAside(Self.grandPrix, "Super Panavision 70"), .reference)
        let alone = f1([("American Cinematographer", [Self.grandPrix])])
        XCTAssertEqual(alone.index.shotOn, [])
        XCTAssertFalse(allNames(alone.specs).contains("Super Panavision 70"), "\(allNames(alone.specs))")
        let both = f1([("British Cinematographer", [Self.veniceCoverage]), ("American Cinematographer", [Self.grandPrix])])
        XCTAssertEqual(both.index.shotOn, [.digital])
        XCTAssertNil(both.index.evidence(for: .film))
    }

    /// The same shapes, made up: the clause about the reference is set aside, this film's isn't.
    func testAReferenceEndsWhereThisFilmComesBack() {
        let q = ["Jane Doe", "Jane", "Doe", "Carl Example", "Carl", "Example"]
        // What follows goes on about the reference.
        XCTAssertEqual(setAside("Glass Rivers was our main reference, which was shot on Kodak 65mm film.", "65mm film",
                                title: "The Quiet Harbour", people: q), .reference)
        // This film comes back: its title, "we", its cinematographer.
        XCTAssertNil(setAside("Glass Rivers is the touchstone, and Doe shot The Quiet Harbour on 35mm film.", "35mm film",
                              title: "The Quiet Harbour", people: q))
        XCTAssertNil(setAside("Glass Rivers was the reference, so we shot on Kodak 35mm film.", "35mm film",
                              title: "The Quiet Harbour", people: q))
        XCTAssertEqual(quiet(["Glass Rivers is the touchstone, and Doe shot The Quiet Harbour on Kodak 35mm film."]).index.shotOn, [.film])
        // Not a title going on about itself: "Daylight was the main reference, so the HMIs…".
        XCTAssertNil(setAside("Daylight was the main reference, so the ARRI SkyPanels were kept low.", "ARRI SkyPanels",
                              title: "The Quiet Harbour", people: q))
        // This film as the reference's subject is this film.
        XCTAssertNil(setAside("The Quiet Harbour was our reference point — it was shot on 35mm film.", "35mm film",
                              title: "The Quiet Harbour", people: q))
    }

    /// "— on Top Gun: Maverick, we opened up to 1.43:1…": that production's; the first 1.43:1 is
    /// said not to be used. Neither is F1's.
    func testAnOpeningNamingAnotherProductionMakesItsClauseThatProductions() {
        XCTAssertEqual(setAside(Self.notHitting, "1.43:1", occurrence: 1), .rejected)
        XCTAssertEqual(setAside(Self.notHitting, "1.43:1", occurrence: 2), .otherProduction)
        let reading = f1([("American Cinematographer", [Self.notHitting])])
        XCTAssertFalse(allNames(reading.specs).contains("1.43:1"), "\(allNames(reading.specs))")
        XCTAssertEqual(reading.index.shotOn, [])
        // This film's own title in the opening is this film.
        let own = quiet(["On The Quiet Harbour, we shot the aerial sequences at 1.43:1."])
        XCTAssertTrue(allNames(own.specs).contains("1.43:1"), "\(allNames(own.specs))")
        // Not a title: a day, a set, a maker's gear.
        XCTAssertNil(setAside("On Monday, we shot on Kodak 35mm film.", "35mm film", title: "The Quiet Harbour"))
        XCTAssertNil(setAside("For the chase, on Sony Venice 2, we shot at 1.43:1.", "1.43:1", title: "The Quiet Harbour"))
        XCTAssertEqual(setAside("On Glass Rivers, I shot on Kodak 35mm film.", "35mm film", title: "The Quiet Harbour"), .otherProduction)
    }

    /// Two films in one sentence: each part is its own film's.
    func testInASentenceAboutTwoFilmsEachPartIsItsOwnFilms() {
        let both = "Glass Rivers was shot on Kodak 65mm film, but The Quiet Harbour was shot on the ARRI Alexa 35."
        XCTAssertEqual(setAside(both, "65mm film", title: "The Quiet Harbour"), .comparison)
        XCTAssertNil(setAside(both, "ARRI Alexa 35", title: "The Quiet Harbour"))
        XCTAssertEqual(quiet([both]).index.shotOn, [.digital])
        // A comparison that says how this film was shot is evidence for it.
        XCTAssertEqual(quiet(["Like Glass Rivers, The Quiet Harbour was shot on Kodak 35mm film."]).index.shotOn, [.film])
        // Without this film named elsewhere, a capitalised subject isn't taken for another film.
        XCTAssertNil(setAside("Everything was shot on Kodak 35mm film.", "35mm film", title: "The Quiet Harbour"))
        // Wording that doesn't say whose: no tag from it.
        XCTAssertEqual(quiet(["Some people still swear by 65mm film for landscapes."]).index.shotOn, [])
    }

    /// "That film was…" only opening a clause: "he argued that film was too slow" is the medium.
    func testThatFilmIsTheOneJustNamedOnlyOpeningAClause() {
        XCTAssertEqual(setAside("We loved Glass Rivers — that film was shot on Kodak 65mm film.", "65mm film", title: "The Quiet Harbour"),
                       .otherProduction)
        XCTAssertEqual(quiet(["Doe argued that film was too slow, so The Quiet Harbour was shot on the ARRI Alexa 35."]).index.shotOn,
                       [.digital])
    }

    /// The other ways a sentence sets words aside, named.
    func testWhySomethingIsSetAsideIsNamed() {
        XCTAssertEqual(setAside("Unlike his IMAX films, The Quiet Harbour was shot on 35mm film.", "IMAX", title: "The Quiet Harbour"), .comparison)
        XCTAssertEqual(setAside("They considered IMAX, but chose 35mm film.", "IMAX", title: "The Quiet Harbour"), .rejected)
        XCTAssertEqual(setAside("The look was inspired by Kodak Ektachrome slides.", "Kodak Ektachrome", title: "The Quiet Harbour"), .reference)
        XCTAssertEqual(setAside("I knew it from his Super 16mm work on Glass Rivers.", "Super 16mm", title: "The Quiet Harbour"), .otherProduction)
        XCTAssertEqual(setAside(Self.fpv, "drone footage"), .reference)
        XCTAssertNil(setAside(Self.ronin, "DJI Ronin 4D"))
        // What's kept says how: shot with, or only named about this film.
        let ronin = f1([("American Cinematographer", [Self.ronin])]).specs.specs.first { $0.name == "DJI Ronin 4D" }
        XCTAssertEqual(ronin?.attribution, .direct)
        let light = f1([("British Cinematographer", [Self.naturalLight])]).specs.specs.first { $0.name == "Natural light" }
        XCTAssertEqual(light?.attribution, .ambiguous)
    }

    // MARK: The review's counter-examples: this film's evidence that must stay

    func testWatchingSomethingThenShootingIsNotAReference() {
        XCTAssertEqual(quiet(["After watching the tests we shot on Kodak 35mm film."]).index.shotOn, [.film])
        XCTAssertEqual(quiet(["We reviewed tests and shot on Kodak 35mm film."]).index.shotOn, [.film])
        XCTAssertEqual(quiet(["We saw tests and chose the ARRI Alexa 65 for the film."]).index.shotOn, [.digital])
    }

    func testAnOpeningAboutAnotherFilmEndsWhereTheSentenceTurns() {
        let q = "The Quiet Harbour"
        let turn = "On Glass Rivers, I shot 35mm film, but this time we chose the ARRI Alexa 65."
        XCTAssertEqual(setAside(turn, "35mm film", title: q), .otherProduction)
        XCTAssertNil(setAside(turn, "ARRI Alexa 65", title: q))
        XCTAssertEqual(quiet([turn]).index.shotOn, [.digital])
        // Its own subtitle is this film.
        XCTAssertNil(setAside("On Fury Road, we shot on the ARRI Alexa Mini.", "ARRI Alexa Mini", title: "Mad Max: Fury Road"))
        // Inside a quote.
        XCTAssertEqual(setAside("“On Glass Rivers, we shot on Kodak 35mm film,” Doe says.", "35mm film", title: q), .otherProduction)
        // Gear and parts of a shoot aren't titles.
        XCTAssertNil(setAside("On Phantom Flex, we shot at 1000 fps with the ARRI Alexa Mini.", "ARRI Alexa Mini", title: q))
        XCTAssertNil(setAside("Interiors were shot on the ARRI Alexa Mini, while exteriors for The Quiet Harbour's finale used 65mm film.",
                              "ARRI Alexa Mini", title: q))
    }

    func testAMovementOrAnInfluenceIsNotAReferenceFilmsShoot() {
        XCTAssertNil(setAside("Neorealism was the touchstone, so they shot handheld on the ARRI Alexa Mini.", "ARRI Alexa Mini",
                              title: "The Quiet Harbour"))
        XCTAssertNil(setAside("Heat was a major influence, so they filmed with Panavision anamorphic lenses.", "anamorphic",
                              title: "The Quiet Harbour"))
    }

    /// Round 2: the reference's own shapes, and titles that start like gear or a part of a shoot.
    func testReferenceShapesAndTitlesThatLookLikeWords() {
        let q = "The Quiet Harbour"
        XCTAssertEqual(setAside("Grand Prix is the touchstone — shot at real events in a beautiful Super Panavision 70 widescreen format.",
                                "Super Panavision 70"), .reference)
        XCTAssertNil(setAside("Heat was an influence, which was why they filmed with Panavision anamorphic lenses.", "anamorphic", title: q))
        XCTAssertEqual(setAside("The Master was the touchstone, which was shot on Kodak 65mm film.", "65mm film", title: q), .reference)
        XCTAssertEqual(setAside("On Days of Heaven, they shot at magic hour on Kodak 35mm film.", "35mm film", title: q), .otherProduction)
        XCTAssertEqual(setAside("On IMAX, we shot on Kodak 65mm film.", "65mm film", title: q), nil)
        // Gear and days of the shoot opening a clause aren't titles.
        XCTAssertNil(setAside("On Ultra Panavision 70, we shot with Hawk anamorphic lenses.", "anamorphic", title: q))
        XCTAssertNil(setAside("On Super 16, we shot handheld on the Aaton XTR.", "Aaton", title: q))
        XCTAssertNil(setAside("On Day One, we shot on Kodak 35mm film.", "35mm film", title: q))
        // This film's cinematographer ends the opening.
        XCTAssertNil(setAside("On Glass Rivers, we shot 35mm and Doe chose the ARRI Alexa 65.", "ARRI Alexa 65", title: q,
                              people: ["Jane Doe", "Jane", "Doe"]))
        // The adjective isn't a conversion.
        let smooth = "Its smooth transition to IMAX comes at the halfway mark."
        XCTAssertFalse(TechSpecs.conversionTarget(smooth, at: smooth.range(of: "IMAX")!))
        let conformed = "The plates were conformed to 24 fps."
        XCTAssertTrue(TechSpecs.conversionTarget(conformed, at: conformed.range(of: "24 fps")!))
    }

    func testAHabitWheneverPossibleIsStillAHabit() {
        XCTAssertEqual(quiet(["Though Doe shoots on 35mm film whenever possible, The Quiet Harbour was shot digitally."]).index.shotOn,
                       [.digital])
    }

    func testFirstDigitalOnlyWhereTheTitleIsWhatItsSaidOf() {
        func read(_ sentence: String, title: String) -> [ShotOn] {
            let specs = TechSpecs.read(texts: [TechSpecs.Text(source: "British Cinematographer", paragraphs: [sentence])],
                                       cinematographers: ["Rodrigo Prieto"], directors: [], title: title)
            return CraftIndex.make(from: specs, colour: nil, keywords: []).shotOn
        }
        XCTAssertEqual(read("Prieto, who had his first digital shoot on The Irishman, shot Killers of the Flower Moon on 35mm film.",
                            title: "Killers of the Flower Moon"), [.film])
        XCTAssertEqual(read("Barbie was Gerwig’s first digital feature.", title: "Barbie"), [.digital])
    }

    func testOnlyAConversionVerbMakesATarget() {
        let smooth = "The picture was shot in 2.39:1 and moves smoothly into IMAX for the battle sequences."
        XCTAssertFalse(TechSpecs.conversionTarget(smooth, at: smooth.range(of: "IMAX")!))
        let smoothed = "We shot at 50 frames per second and smoothed it back to 24 frames per second."
        XCTAssertTrue(TechSpecs.conversionTarget(smoothed, at: smoothed.range(of: "24 frames per second")!))
    }

    // MARK: B. Numbers and negation

    func testResolutionIsReadWhole() {
        let reading = f1([("American Cinematographer", [Self.eightSix])])
        XCTAssertTrue(allNames(reading.specs).contains("8.6K"), "\(allNames(reading.specs))")
        XCTAssertFalse(allNames(reading.specs).contains("6K"), "no 6K from 8.6K")
        XCTAssertFalse(allNames(quiet(["They shot the night scenes at 5.8K on the ARRI Alexa 35."]).specs).contains("8K"))
        XCTAssertTrue(allNames(quiet(["We shot the night scenes at 6K on the ARRI Alexa 35."]).specs).contains("6K"))
        XCTAssertTrue(allNames(quiet(["We shot the night scenes at 4.6K on the ARRI Alexa 35."]).specs).contains("4.6K"))
    }

    func testANegatedRatioIsNotThisFilms() {
        XCTAssertFalse(allNames(quiet(["We didn’t shoot at 1.43:1 in the end."]).specs).contains("1.43:1"))
        XCTAssertTrue(allNames(quiet(["We shot the whole film at 1.43:1."]).specs).contains("1.43:1"))
    }

    // MARK: C. Used, watched, nicknamed

    func testLedToUseSaysItWasUsed() {
        let reading = f1([("American Cinematographer", [Self.ronin])])
        XCTAssertTrue(allNames(reading.specs).contains("DJI Ronin 4D"), "\(allNames(reading.specs)) / \(reading.specs.mentioned.map(\.name))")
        XCTAssertEqual(reading.index.shotOn, [.digital])
        XCTAssertTrue(allNames(quiet(["Tight spaces prompted the crew to use a DJI Ronin 4D in the cars."]).specs).contains("DJI Ronin 4D"))
        // Still not: wanting to, or what would have been used.
        XCTAssertFalse(allNames(quiet(["Doe wanted to use the ARRI Alexa 35."]).specs).contains("ARRI Alexa 35"))
    }

    func testAConsideredCameraIsNotGear() {
        let reading = quiet(["We considered the ARRI Alexa 65, but Doe shot The Quiet Harbour on Kodak 35mm film."])
        XCTAssertFalse(allNames(reading.specs).contains("ARRI Alexa 65"), "\(allNames(reading.specs))")
        XCTAssertEqual(reading.index.shotOn, [.film])
        // Gear used on this film, of every kind, stays.
        let used = quiet(["Doe shot The Quiet Harbour on the ARRI Alexa 35 with Cooke S4 lenses, lighting with natural light and a Steadicam."])
        for name in ["ARRI Alexa 35", "Natural light", "Steadicam"] {
            XCTAssertTrue(allNames(used.specs).contains(name), "\(name) not in \(allNames(used.specs))")
        }
    }

    func testFootageWatchedIsNotGearUsed() {
        let reading = f1([("American Cinematographer", [Self.fpv])])
        XCTAssertFalse(allNames(reading.specs).contains("Drone"), "\(allNames(reading.specs))")
        XCTAssertFalse(allNames(quiet(["We studied some 16mm documentary footage of the strikes."]).specs).contains("16 mm"))
        // Drone work said of this film stays.
        XCTAssertTrue(allNames(quiet(["The opening of The Quiet Harbour was shot from a drone."]).specs).contains("Drone"))
    }

    // MARK: D. Frame rate

    func testAFrameRateConvertedToAfterwardsIsNotHowItWasShot() {
        let reading = f1([("British Cinematographer", [Self.vfx24])])
        XCTAssertFalse(allNames(reading.specs).contains("24 frames per second"), "\(allNames(reading.specs))")
        XCTAssertFalse(allNames(quiet(["The plates were conformed to 24 fps in the grade, and we shot the rest on the ARRI Alexa 35."]).specs)
            .contains("24 fps"))
        XCTAssertTrue(allNames(quiet(["We shot the dream scenes at 48 frames per second."]).specs).contains("48 frames per second"))
    }

    // MARK: Natural light, iPhone

    func testNaturalLightWheneverPossibleIsThisFilms() {
        let reading = f1([("British Cinematographer", [Self.naturalLight])])
        XCTAssertTrue(allNames(reading.specs).contains("Natural light"), "\(allNames(reading.specs))")
        // "Whenever" for other work is still other work.
        XCTAssertFalse(allNames(quiet(["Whenever I shoot commercials, I use natural light."]).specs).contains("Natural light"))
    }

    func testIPhoneIsWrittenAsItsMakerWritesIt() {
        XCTAssertEqual(TechSpecs.display("iPhone 12"), "iPhone 12")
        XCTAssertEqual(TechSpecs.display("natural light"), "Natural light")
        let reading = f1([("British Cinematographer", [Self.iPhoneSensor])])
        XCTAssertTrue(allNames(reading.specs).contains("iPhone 12"), "\(allNames(reading.specs))")
        XCTAssertFalse(allNames(reading.specs).contains("IPhone 12"))
    }

    // MARK: E. The reason

    /// The Venice 2 sentence (the film's traditional coverage) over the on-board iPhone-sensor
    /// camera, whichever is read first; the tag and its scope don't change.
    func testTheMainCoverageIsTheReasonOverAnOnBoardCamera() {
        for order in [[Self.iPhoneSensor, Self.veniceCoverage], [Self.veniceCoverage, Self.iPhoneSensor]] {
            let reading = f1([("British Cinematographer", order)])
            XCTAssertEqual(reading.index.shotOn, [.digital])
            let reason = reading.index.evidence(for: .digital)
            XCTAssertTrue(reason?.text.contains("Sony Venice 2 bodies for traditional coverage") ?? false, reason?.text ?? "")
            XCTAssertEqual(reason?.partial, false)
        }
    }

    /// Part of the film, when that's all there is: the reason, and the tag in part.
    func testAPartialStatementAloneIsTheReasonInPart() {
        let reading = quiet(["The flashbacks were shot on Ektachrome."])
        XCTAssertEqual(reading.index.shotOn, [.film])
        XCTAssertEqual(reading.index.evidence(for: .film)?.text, "The flashbacks were shot on Ektachrome.")
    }

    /// Main coverage never outranks a sentence about the whole film, nor makes part of it the whole.
    func testMainCoverageDoesNotOutrankTheWholeFilm() {
        let reading = quiet(["The ARRI Alexa Mini was the main camera for the car scenes.",
                             "The Quiet Harbour was shot entirely on the ARRI Alexa 35."])
        XCTAssertTrue(reading.index.evidence(for: .digital)?.text.hasPrefix("The Quiet Harbour was shot entirely") ?? false)
        let principal = quiet(["Most of the street scenes were shot on Kodak 35mm film."]).specs.specs.first { $0.name.contains("35") }
        XCTAssertEqual(principal?.principal, true)
        XCTAssertEqual(principal?.wholeFilm, false)
    }

    // MARK: F. Barbie

    /// "Having never shot digitally, at first Gerwig was a little sceptical about making the move…"
    /// says what Gerwig hadn't done: by itself, no tag. The article's plain statement that Barbie was
    /// her first digital shoot is the reason.
    func testBarbieIsDigitalByThePlainStatementNotThePastNever() {
        func barbie(_ sentences: [String]) -> CraftIndex {
            let specs = TechSpecs.read(texts: [TechSpecs.Text(source: "British Cinematographer", paragraphs: sentences)],
                                       cinematographers: ["Rodrigo Prieto"], directors: ["Greta Gerwig"], year: 2023, title: "Barbie")
            return CraftIndex.make(from: specs, colour: nil, keywords: [])
        }
        let never = "Having never shot digitally, at first Gerwig was a little sceptical about making the move, but Prieto felt the look aligned with the concept of authentic artificiality."
        let first = "As well as being Gerwig’s first digital shooting experience, Barbie was her first venture into the 2:1 aspect ratio."
        XCTAssertEqual(barbie([never]).shotOn, [])
        XCTAssertEqual(barbie([never, first]).shotOn, [.digital])
        XCTAssertEqual(barbie([never, first]).evidence(for: .digital)?.text, first)
        // Without the title, someone's first digital shoot is their career, not this film.
        XCTAssertEqual(barbie(["It was Gerwig’s first digital shooting experience."]).shotOn, [])
        XCTAssertEqual(barbie(["Glass Rivers was Gerwig’s first digital feature."]).shotOn, [])
    }

    // MARK: F1 as read

    /// The F1 sentences together: Digital only, its reason the Venice 2 coverage, and the gear
    /// without Super Panavision 70, 6K, 1.43:1, Drone or 24 frames per second, with the Ronin 4D.
    func testF1AsRead() {
        let reading = f1([
            ("British Cinematographer", [Self.iPhoneSensor, Self.veniceCoverage, Self.naturalLight, Self.vfx24]),
            ("American Cinematographer", [Self.grandPrix, Self.notHitting, Self.fpv, Self.ronin, Self.eightSix]),
        ])
        XCTAssertEqual(reading.index.shotOn, [.digital])
        XCTAssertTrue(reading.index.evidence(for: .digital)?.text.contains("traditional coverage") ?? false)
        let names = allNames(reading.specs)
        // Shown in CI's annotations: what the fixtures read as.
        print("::notice title=F1 as read::tags \(reading.index.shotOn.map(\.rawValue)); reason \(reading.index.evidence(for: .digital)?.text.prefix(80) ?? ""); names \(names); named, not this film's \(reading.specs.mentioned.map(\.name))")
        for wrong in ["Super Panavision 70", "6K", "1.43:1", "Drone", "24 frames per second", "IPhone 12"] {
            XCTAssertFalse(names.contains(wrong), "\(wrong) in \(names)")
        }
        for right in ["Sony Venice 2", "DJI Ronin 4D", "iPhone 12", "8.6K", "Natural light"] {
            XCTAssertTrue(names.contains(right), "\(right) not in \(names)")
        }
    }

    // MARK: G. Stored, read again

    private let grandPrixEvidence = CraftIndex.Evidence(shotOn: .film, text: ReadingRulesTests.grandPrix, source: "American Cinematographer")
    private let iPhoneEvidence = CraftIndex.Evidence(shotOn: .digital, text: ReadingRulesTests.iPhoneSensor, source: "British Cinematographer")
    private let veniceEvidence = CraftIndex.Evidence(shotOn: .digital, text: ReadingRulesTests.veniceCoverage, source: "British Cinematographer")

    private func stored() -> CraftIndex {
        CraftIndex(version: 11, shotOn: [.film, .digital], names: [], evidence: [grandPrixEvidence, iPhoneEvidence], sources: 3,
                   read: ["British Cinematographer", "American Cinematographer", "Wikipedia"], discovery: 5)
    }

    /// Rules 12 read every film again; F1's AC article read again drops Film, keeps Digital with its
    /// new reason.
    func testReadAgainTheFalseFilmTagIsDroppedAndDigitalKept() {
        XCTAssertGreaterThanOrEqual(CraftIndex.currentVersion, 12, "rules 12 or later")
        XCTAssertEqual(CraftIndex.currentDiscovery, 5, "finding unchanged")
        XCTAssertEqual(CraftQueue.state(craft: stored(), attempt: nil, hasFacts: true, inCollection: false, now: Date()), .olderRules)
        let new = CraftIndex(version: 12, shotOn: [.digital], names: [], evidence: [veniceEvidence], sources: 3,
                             read: ["British Cinematographer", "American Cinematographer", "Wikipedia"], discovery: 5)
        let merged = CraftIndex.merging(old: stored(), new: new)
        XCTAssertEqual(merged.index.shotOn, [.digital])
        XCTAssertEqual(merged.index.evidence(for: .digital)?.text, Self.veniceCoverage)
        XCTAssertEqual(merged.carried, [])
        XCTAssertEqual(merged.dropped.map(\.reason), ["American Cinematographer was read again and, by rules 12, doesn't say so"])
        XCTAssertNil(merged.index.retryAt)
    }

    /// American Cinematographer not answering: the old Film tag is carried, as any tag whose site is
    /// down (a site that's down never costs a tag), until the site answers; read again soon.
    func testASiteDownCarriesTheOldTagUntilItAnswers() {
        let new = CraftIndex(version: 12, shotOn: [.digital], names: [], evidence: [veniceEvidence], sources: 2,
                             read: ["British Cinematographer", "Wikipedia"], discovery: 5, unanswered: ["American Cinematographer"])
        let merged = CraftIndex.merging(old: stored(), new: new)
        XCTAssertEqual(Set(merged.index.shotOn), [.film, .digital])
        XCTAssertEqual(merged.carried.first?.carriedRules, 11)
        XCTAssertNotNil(merged.index.retryAt)
        // When it answers and is read: dropped.
        let later = CraftIndex(version: 12, shotOn: [.digital], names: [], evidence: [veniceEvidence], sources: 3,
                               read: ["British Cinematographer", "American Cinematographer", "Wikipedia"], discovery: 5)
        XCTAssertEqual(CraftIndex.merging(old: merged.index, new: later).index.shotOn, [.digital])
    }

    /// 1.10.2's L4: merging compares sites, not pages. Under a rules change it doesn't matter which:
    /// a tag found by older rules whose page isn't read again is dropped either way (the site read
    /// for another page: "read again"; the site answering with nothing read: "not found again by
    /// rules 12"). A site that didn't answer still keeps it.
    func testUnderARulesChangeSiteAndPageMergingAgree() {
        let otherPageRead = CraftIndex(version: 12, shotOn: [.digital], names: [], evidence: [veniceEvidence], sources: 3,
                                       read: ["British Cinematographer", "American Cinematographer"], discovery: 5)
        XCTAssertEqual(CraftIndex.merging(old: stored(), new: otherPageRead).index.shotOn, [.digital])
        let nothingRead = CraftIndex(version: 12, shotOn: [.digital], names: [], evidence: [veniceEvidence], sources: 2,
                                     read: ["British Cinematographer", "Wikipedia"], discovery: 5)
        let merged = CraftIndex.merging(old: stored(), new: nothingRead)
        XCTAssertEqual(merged.index.shotOn, [.digital])
        XCTAssertEqual(merged.dropped.map(\.reason),
                       ["found by rules 11; American Cinematographer wasn't found again to read by rules 12"])
    }

    /// A rules-11 reading, as 1.10.2 stored it, still decodes.
    func testAnOlderReadingStillDecodes() throws {
        var old = stored()
        old.limits = [CraftIndex.SourceLimit(site: "American Cinematographer", url: "https://theasc.com/article/x/", kind: .gone, detail: "404")]
        let data = try JSONEncoder().encode(old)
        let back = try JSONDecoder().decode(CraftIndex.self, from: data)
        XCTAssertEqual(back.version, 11)
        XCTAssertEqual(back.evidence, old.evidence)
    }

    // MARK: H. Protected cases

    func testWhatWasShotThisWayStaysTagged() {
        XCTAssertEqual(quiet(["Doe shot The Quiet Harbour on Kodak 35mm film."]).index.shotOn, [.film])
        XCTAssertEqual(quiet(["We shot the film on the ARRI Alexa 65 with Panavision Sphero 65 lenses."]).index.shotOn, [.digital])
        XCTAssertEqual(quiet(["The Quiet Harbour was shot in IMAX with 65mm film cameras."]).index.shotOn.contains(.imax), true)
        XCTAssertEqual(quiet(["On set, we shot on Kodak 35mm film."]).index.shotOn, [.film])
        XCTAssertEqual(quiet(["For the chase, Doe used the ARRI Alexa Mini LF as the A-camera."]).index.shotOn, [.digital])
    }
}
