import XCTest
@testable import ReelCore

/// Reel 1.9.5: what the 1.9.4 audit of a real library found, each with the true sentences that look
/// like it kept. The sentences are shaped like the real ones; the films and people are made up.
final class HonestResultsTests: XCTestCase {
    private func craft(_ paragraphs: [String], source: String = "American Cinematographer", dp: [String] = ["Jane Doe"],
                       directors: [String] = ["Carl Example"], title: String = "The Quiet Harbour") -> CraftIndex {
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: source, paragraphs: paragraphs)], cinematographers: dp,
                                   directors: directors, title: title)
        return CraftIndex.make(from: specs, colour: nil, keywords: [])
    }

    /// The film's own Wikipedia article, by section.
    private func article(_ sections: [(String, [String])], title: String = "The Quiet Harbour") -> CraftIndex {
        let parts = sections.enumerated().map { FilmArticle.Section(id: $0.offset, title: $0.element.0, paragraphs: $0.element.1) }
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: nil, sections: parts, isInterview: false)],
                                   cinematographers: ["Jane Doe"], directors: ["Carl Example"], title: title)
        return CraftIndex.make(from: specs, colour: nil, keywords: [])
    }

    // MARK: A plan given up

    func testAPlanGivenUpIsNotWhatItWasShotOn() {
        let given = craft(["Though the original plan had been to shoot on 16mm film, the feature was ultimately captured digitally, with the filmmakers employing an Arri Alexa Mini and XT from a rental house in Paris."])
        XCTAssertEqual(given.shotOn, [.digital], "the 16mm plan was given up")
        XCTAssertEqual(craft(["The initial plan was to shoot on 35mm, but the film was shot on the Sony Venice 2."]).shotOn, [.digital])
        XCTAssertEqual(craft(["Doe had originally planned to shoot on Super 16, and the production went with the Alexa 35."]).shotOn, [.digital])
    }

    func testAPlanThatWasKeptStillCounts() {
        // ("shoot" alone isn't a word about the shooting for a gauge: the stock is.)
        XCTAssertEqual(craft(["The plan was always to shoot on 35mm film stock, and that's what we did."]).shotOn, [.film])
        XCTAssertEqual(craft(["The plan was always to shoot on 35mm film stock."]).shotOn, [], "a plan alone isn't what was done")
        XCTAssertEqual(craft(["The plan was to shoot on 35mm film, and in the end the film was shot on Kodak 5219."]).shotOn, [.film])
        XCTAssertEqual(craft(["Doe shot the film on Kodak Vision3 500T 5219."]).shotOn, [.film])
    }

    // MARK: What footage was transferred onto

    func testWhatFootageWasTransferredOntoIsNotWhatItWasShotOn() {
        let transfer = craft(["There was no digital intermediate either.",
                              "The lab supervised transferring images captured in IMAX format onto 35mm colour negative film."])
        XCTAssertEqual(transfer.shotOn, [.imax], "captured in IMAX; the 35mm negative is the copy")
        XCTAssertEqual(craft(["The negative was scanned to 4K and recorded out to 35mm print film for the premiere."]).shotOn, [])
    }

    func testShootingStatedBesideATransferStillCounts() {
        XCTAssertEqual(craft(["We shot on Kodak 5219 35mm film and transferred the negative to 4K for the grade."]).shotOn, [.film])
        XCTAssertEqual(craft(["The film was shot on Super 16 and later blown up to 35mm for release."]).shotOn, [.film])
    }

    // MARK: An award speech

    func testAnAwardSpeechIsNotHowTheFilmWasShot() {
        let speech = "On accepting her award, Doe said: “To all the aspiring filmmakers out there, please try shooting that incredible new hip thing called celluloid.”"
        XCTAssertEqual(craft([speech], source: "British Cinematographer").shotOn, [])
        XCTAssertEqual(craft(["In her acceptance speech, Doe urged students to shoot on 16mm film."], source: "British Cinematographer").shotOn, [])
        // The same article's account of the shoot still counts, and it's the one shown.
        let both = craft([speech, "Doe shot The Quiet Harbour on Kodak 65mm negative with IMAX MSM 9802 cameras."], source: "British Cinematographer")
        XCTAssertEqual(both.shotOn, [.film, .imax])
        XCTAssertFalse(both.evidence(for: .film)?.text.contains("accepting") ?? true, "\(both.evidence(for: .film)?.text ?? "")")
    }

    // MARK: Who's speaking in an interview

    func testTheInterviewersLineIsNotTheFilmmakers() {
        let interview = craft(["BB: That makes sense, and I did feel the grain more in the night scenes than in the daytime scenes shot on film.",
                               "DE: Exactly, we shot the nights with the Alexa Mini at 1600 ISO."], dp: ["Darius Example"])
        XCTAssertEqual(interview.shotOn, [.digital], "BB is the interviewer; DE is Darius Example")
        XCTAssertEqual(craft(["DE: We shot the days on Kodak 5219 film."], dp: ["Darius Example"]).shotOn, [.film], "the cinematographer's own answer")
        XCTAssertEqual(craft(["JL: We shot the days on Kodak 5219 film."], dp: ["Darius Example"]).shotOn, [], "someone Reel can't tell is the filmmaker")
        XCTAssertEqual(craft(["Darius Example: We shot the days on Kodak 5219 film."], dp: ["Darius Example"]).shotOn, [.film])
        // The magazine's narrative around the interview is read as before.
        XCTAssertEqual(craft(["All the daytime scenes were shot with Arricam ST cameras on Kodak 5219 negative film."], dp: ["Darius Example"]).shotOn, [.film])
    }

    func testSpeakerInitials() {
        XCTAssertFalse(TechSpecs.isQuestion("RD: We used the Alexa Mini for the whole film.", source: "British Cinematographer", people: ["Rhea Dunn"]))
        XCTAssertTrue(TechSpecs.isQuestion("BB: What did you shoot the nights on.", source: "American Cinematographer", people: ["Darius Example"]))
        XCTAssertEqual(TechSpecs.initials(of: ["Henk van Hoven"]), ["HVH", "HH"])
        XCTAssertEqual(TechSpecs.initials(of: ["Joshua James Richards"]), ["JJR", "JR"])
        XCTAssertFalse(TechSpecs.isQuestion("ISO: 800 for the day exteriors.", source: "American Cinematographer", people: []), "a label, not a speaker")
        XCTAssertFalse(TechSpecs.isQuestion("DP: We lit it with one big source.", source: "No Film School", people: []))
    }

    // MARK: IMAX for part of the film

    func testAStatedShareOfIMAXIsInPart() {
        let reading = article([
            ("", ["The Quiet Harbour was the first major motion picture to be filmed with high-resolution IMAX cameras."]),
            ("Filming", ["Much of The Quiet Harbour was filmed using Panaflex Millennium XL cameras but Example wanted to film about 40 minutes with IMAX cameras, a high-resolution technology using 70 mm film; the finished film includes 15–20% IMAX footage, running for about 28 minutes."]),
        ])
        XCTAssertEqual(reading.label(for: .imax), "IMAX (in part)", "the stated share outweighs \"filmed with IMAX cameras\"")
        XCTAssertTrue(reading.shotOn.contains(.film))
        let much = article([("Filming", ["Example used IMAX 70 mm film cameras for much of the filming, including the opening, to optimize the picture."])])
        XCTAssertEqual(much.label(for: .imax), "IMAX (in part)")
        XCTAssertEqual(craft(["Some 30 percent of the footage was shot with IMAX cameras."]).label(for: .imax), "IMAX (in part)")
    }

    func testIMAXForTheWholeFilmStaysWhole() {
        XCTAssertEqual(craft(["The entire film was shot with IMAX cameras."]).label(for: .imax), "IMAX")
        XCTAssertEqual(article([("", ["The Quiet Harbour was the first major motion picture to be filmed with high-resolution IMAX cameras."])]).label(for: .imax),
                       "IMAX", "said plainly, with no share: as before")
        XCTAssertEqual(craft(["It runs 152 minutes and was shot with IMAX cameras."]).label(for: .imax), "IMAX", "a running time isn't a share")
        // Said of the whole film in so many words outweighs a share.
        XCTAssertEqual(craft(["The entire film was shot with IMAX cameras.", "About 40 minutes were shot with IMAX cameras at night."]).label(for: .imax), "IMAX")
    }

    // MARK: What the review of 1.9.5 caught: real capture kept

    /// Reel 1.9.6: the rest of a speech's quote ("Four out of five nominated films were shot on
    /// celluloid…”"), and films counted in general.
    func testTheRestOfASpeechIsntHowItWasShot() {
        let quote = "In her acceptance speech, Doe said: “Celluloid is alive and kicking. Four out of five nominated films were shot on celluloid and it proves that film is resilient.” The Quiet Harbour was shot on Kodak 65mm negative."
        let read = craft([quote], source: "British Cinematographer")
        XCTAssertEqual(read.shotOn, [.film])
        XCTAssertTrue(read.evidence(for: .film)?.text.hasPrefix("The Quiet Harbour was shot") ?? false, "\(read.evidence(for: .film)?.text ?? "")")
        XCTAssertEqual(craft(["Doe won the BAFTA for Best Cinematography.", "Four out of five nominated films were shot on celluloid."],
                             source: "British Cinematographer").shotOn, [], "films in general")
        XCTAssertEqual(craft(["Doe shot the film on 35mm film; it was one of five nominated films shot that way."]).shotOn, [.film])
        XCTAssertTrue(TechSpecs.quoteStaysOpen("He said: “Celluloid is alive.", wasOpen: false))
        XCTAssertTrue(TechSpecs.quoteStaysOpen("It's easier than you think.", wasOpen: true))
        XCTAssertFalse(TechSpecs.quoteStaysOpen("It looks so much better.”", wasOpen: true))
        XCTAssertFalse(TechSpecs.quoteStaysOpen("He said: “It's alive.”", wasOpen: false))
    }

    func testNarrowRulesKeepRealCapture() {
        // Transfers: a shooting verb after "to", or the copy's verb in another clause, isn't a transfer.
        XCTAssertEqual(craft(["After scanning the tests we switched to the Alexa 65 for the whole shoot."]).shotOn, [.digital])
        XCTAssertTrue(craft(["After the tests were scanned, Doe decided to shoot on IMAX 65 cameras."]).shotOn.contains(.imax))
        XCTAssertEqual(craft(["Doe shot on Super 35 film and the negative was blown up to IMAX for release."]).shotOn, [.film],
                       "blown up to IMAX is the release")
        // Speeches: only an award accepted, or an acceptance speech.
        XCTAssertEqual(craft(["After accepting the job, Doe chose to shoot on 35mm film stock."]).shotOn, [.film])
        XCTAssertEqual(craft(["During the speech scene, the camera was a handheld Alexa Mini."]).shotOn, [.digital])
        // Shares: a running time or a magazine's length isn't one.
        XCTAssertEqual(craft(["The film is 169 minutes and was shot with IMAX cameras."]).label(for: .imax), "IMAX")
        XCTAssertEqual(craft(["IMAX cameras hold only 3 minutes of film per magazine, and Doe shot with IMAX cameras throughout."]).label(for: .imax), "IMAX")
        // Plans: an intention that isn't about the shooting.
        XCTAssertEqual(craft(["His intention was to immerse the audience so he shot it with IMAX cameras."]).shotOn, [.imax])
    }

    func testCapitalLabelsAndNamesAreNotTheInterviewer() {
        XCTAssertFalse(TechSpecs.isQuestion("LENS: Cooke S4/i primes throughout.", source: "American Cinematographer", people: ["Roger Example"]))
        XCTAssertFalse(TechSpecs.isQuestion("ROGER: We shot on Kodak 5219.", source: "American Cinematographer", people: ["Roger Example"]))
        XCTAssertEqual(craft(["ROGER: We shot the days on Kodak 5219 film."], dp: ["Roger Example"]).shotOn, [.film])
    }

    // MARK: Reading again, tag by tag

    private let then = Date(timeIntervalSince1970: 1_790_000_000)
    private var now: Date { then.addingTimeInterval(30 * 86_400) }

    /// A reading by 1.9.4's rules: Film from the article, Anamorphic from a magazine.
    private var earlier: CraftIndex {
        CraftIndex(version: 6, readAt: then, shotOn: [.film, .anamorphic], names: ["Panaflex", "C-Series"],
                   evidence: [CraftIndex.Evidence(shotOn: .film, text: "It was shot on 35 mm film.", source: "Wikipedia"),
                              CraftIndex.Evidence(shotOn: .anamorphic, text: "We used C-Series anamorphics.", source: "Lens Weekly")],
                   sources: 3, read: ["Lens Weekly", "Wikipedia"])
    }

    private func reading(_ shotOn: [ShotOn], read: [String], unanswered: [String] = [], at date: Date? = nil) -> CraftIndex {
        CraftIndex(readAt: date ?? now, shotOn: shotOn, names: [],
                   evidence: shotOn.map { CraftIndex.Evidence(shotOn: $0, text: "It was shot on 35 mm film.", source: "Wikipedia") },
                   sources: read.count, read: read, unanswered: unanswered)
    }

    func testAnOlderTagIsDroppedWhenItsSourceWasReadAgain() {
        let merged = CraftIndex.merging(old: earlier, new: reading([.film], read: ["Lens Weekly", "Wikipedia"]), now: now)
        XCTAssertEqual(merged.index.shotOn, [.film])
        XCTAssertEqual(merged.dropped.map(\.shotOn), [.anamorphic])
        XCTAssertNil(merged.index.retryAt)
        XCTAssertFalse(merged.index.isPartial)
        // Fewer texts read changes nothing: the source that said it was read again and doesn't say so.
        let fewer = CraftIndex.merging(old: earlier, new: reading([], read: ["Lens Weekly"]), now: now)
        XCTAssertEqual(fewer.index.shotOn, [], "Lens Weekly was read again; Wikipedia wasn't found, and its Film was found by older rules")
        XCTAssertEqual(Set(fewer.dropped.map(\.shotOn)), [.film, .anamorphic])
        XCTAssertNil(fewer.index.retryAt, "nothing carried, every site answered: complete")
    }

    func testATagIsCarriedWhileItsSiteDoesntAnswer() {
        var merged = CraftIndex.merging(old: earlier, new: reading([.film], read: ["Wikipedia"], unanswered: ["Lens Weekly"]), now: now)
        XCTAssertEqual(merged.index.shotOn, [.film, .anamorphic], "a failed read doesn't erase what that site said")
        let carried = merged.index.evidence(for: .anamorphic)
        XCTAssertEqual(carried?.carriedFrom, then)
        XCTAssertEqual(carried?.carriedRules, 6, "found by older rules, and marked so")
        XCTAssertNil(merged.index.evidence(for: .film)?.carriedFrom, "found again")
        XCTAssertTrue(merged.index.isPartial)
        XCTAssertTrue(merged.index.willReadAgain)
        XCTAssertEqual(merged.index.retryAt, now.addingTimeInterval(6 * 3600))
        XCTAssertEqual(CraftQueue.state(craft: merged.index, attempt: nil, hasFacts: true, inCollection: false, now: now), .partial)
        // The site stays away: read again a day, three days and a week later, then every 30 days.
        for _ in 0..<5 {
            merged = CraftIndex.merging(old: merged.index, new: reading([.film], read: ["Wikipedia"], unanswered: ["Lens Weekly"]), now: now)
        }
        XCTAssertEqual(merged.index.retries, 6)
        XCTAssertEqual(merged.index.retryAt, now.addingTimeInterval(30 * 86_400), "no faster than monthly, never given up")
        XCTAssertEqual(merged.index.evidence(for: .anamorphic)?.carriedFrom, then, "its age is kept")
        // It answers, and no longer says so: dropped, and the reading is complete.
        let answered = CraftIndex.merging(old: merged.index, new: reading([.film], read: ["Wikipedia", "Lens Weekly"]), now: now)
        XCTAssertEqual(answered.index.shotOn, [.film])
        XCTAssertNil(answered.index.retryAt)
        XCTAssertEqual(answered.index.retries, 0)
        XCTAssertEqual(CraftQueue.state(craft: answered.index, attempt: nil, hasFacts: true, inCollection: false, now: now), .complete)
    }

    func testByTheSameRulesATagWhosePageWasntFoundIsCarriedForAWhile() {
        let current = CraftIndex(readAt: then, shotOn: [.anamorphic], names: ["C-Series"],
                                 evidence: [CraftIndex.Evidence(shotOn: .anamorphic, text: "We used C-Series anamorphics.", source: "Lens Weekly")],
                                 sources: 2, read: ["Lens Weekly", "Wikipedia"])
        var merged = CraftIndex.merging(old: current, new: reading([], read: ["Wikipedia"]), now: now)
        XCTAssertEqual(merged.index.shotOn, [.anamorphic], "its page wasn't found this time")
        XCTAssertEqual(merged.index.retryAt, now.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(merged.index.names, ["C-Series"], "its names are kept for search too")
        for _ in 0..<3 { merged = CraftIndex.merging(old: merged.index, new: reading([], read: ["Wikipedia"]), now: now) }
        XCTAssertEqual(merged.index.shotOn, [.anamorphic], "four readings in all")
        merged = CraftIndex.merging(old: merged.index, new: reading([], read: ["Wikipedia"]), now: now)
        XCTAssertEqual(merged.index.shotOn, [])
        XCTAssertEqual(merged.dropped.first?.reason, "Lens Weekly wasn't found again in 4 readings")
        XCTAssertNil(merged.index.retryAt)
    }

    func testAPageNotFoundIsCountedApartFromASiteDown() {
        // Six readings with Lens Weekly down, then it answers but the page isn't found: carried, by
        // its own count (not dropped on the first miss because of the site's).
        var merged = CraftIndex.merging(old: earlier, new: reading([.film], read: ["Wikipedia"], unanswered: ["Lens Weekly"]), now: now)
        for _ in 0..<5 { merged = CraftIndex.merging(old: merged.index, new: reading([.film], read: ["Wikipedia"], unanswered: ["Lens Weekly"]), now: now) }
        let older = CraftIndex.merging(old: merged.index, new: reading([.film], read: ["Wikipedia"]), now: now)
        XCTAssertEqual(older.index.shotOn, [.film], "found by rules 6: not kept once its site answers without it")
        var same = CraftIndex(readAt: then, shotOn: [.anamorphic], names: [],
                              evidence: [CraftIndex.Evidence(shotOn: .anamorphic, text: "We used C-Series anamorphics.", source: "Lens Weekly")],
                              sources: 2, read: ["Lens Weekly"])
        for _ in 0..<5 { same = CraftIndex.merging(old: same, new: reading([], read: ["Wikipedia"], unanswered: ["Lens Weekly"]), now: now).index }
        let missed = CraftIndex.merging(old: same, new: reading([], read: ["Wikipedia"]), now: now)
        XCTAssertEqual(missed.index.shotOn, [.anamorphic], "its first miss")
        XCTAssertEqual(missed.index.evidence(for: .anamorphic)?.misses, 1)
    }

    func testTheCinematographersArticleReadAgainIsntTakenForWikipediaDown() {
        let old = CraftIndex(readAt: then, shotOn: [.film], names: [],
                             evidence: [CraftIndex.Evidence(shotOn: .film, text: "Doe shot it on 35 mm film.", source: "Wikipedia: Jane Doe")],
                             sources: 2, read: ["Wikipedia", "Wikipedia: Jane Doe"])
        let merged = CraftIndex.merging(old: old, new: reading([], read: ["Wikipedia: Jane Doe"], unanswered: ["Wikipedia"]), now: now)
        XCTAssertEqual(merged.index.shotOn, [], "her article was read again and no longer says so")
    }

    func testAReadingFoundABetterWayReplacesTheOld() {
        // Found before the last change to what's found (`findingChanged`): replaced whole.
        var old = earlier
        old.discovery = CraftIndex.findingChanged - 1
        let new = CraftIndex(shotOn: [.film], names: [], sources: 1, read: ["Wikipedia"], unanswered: ["Lens Weekly"])
        XCTAssertEqual(CraftIndex.merging(old: old, new: new, now: now).index.shotOn, [.film])
    }

    func testWhatWikidataSaidIsWorkedOutAgain() {
        let old = CraftIndex(readAt: then, shotOn: [.blackAndWhite], names: [],
                             evidence: [CraftIndex.Evidence(shotOn: .blackAndWhite, text: "Colour: black-and-white", source: "Wikidata")],
                             sources: 1, read: ["Wikipedia"])
        XCTAssertEqual(CraftIndex.merging(old: old, new: reading([], read: [], unanswered: ["Wikipedia"]), now: now).index.shotOn, [])
    }

    func testACompleteReadingWithNoTagsIsComplete() {
        let empty = CraftIndex.merging(old: nil, new: reading([], read: ["Wikipedia", "Lens Weekly"]), now: now).index
        XCTAssertFalse(empty.isPartial)
        XCTAssertNil(empty.retryAt)
        XCTAssertEqual(CraftQueue.state(craft: empty, attempt: nil, hasFacts: true, inCollection: false, now: now), .complete)
        // A site that didn't answer makes an empty reading partial, not done.
        let failed = CraftIndex.merging(old: nil, new: reading([], read: ["Wikipedia"], unanswered: ["Lens Weekly"]), now: now).index
        XCTAssertTrue(failed.isPartial)
        XCTAssertEqual(CraftQueue.state(craft: failed, attempt: nil, hasFacts: true, inCollection: false, now: now), .partial)
        XCTAssertTrue(CraftQueue.state(craft: failed, attempt: nil, hasFacts: true, inCollection: false, now: now).isOutstanding)
    }

    // MARK: The log says what's stored

    func testTheLogSaysWhatsStored() {
        let merged = CraftIndex.merging(old: earlier, new: reading([.film], read: ["Wikipedia"], unanswered: ["Lens Weekly"]), now: now)
        let log = CraftLog.stored(merged)
        XCTAssertTrue(log.contains("STORED IN REEL"))
        XCTAssertTrue(log.contains("• Film — found in this reading: Wikipedia"), log)
        XCTAssertTrue(log.contains("• Anamorphic — carried from the reading of 2026-09-21 (rules 6), Lens Weekly didn't answer this time"), log)
        XCTAssertTrue(log.contains("Incomplete: Lens Weekly didn't answer. Read again automatically after"), log)
        XCTAssertEqual(storedTags(log), merged.index.shotOn.map { merged.index.label(for: $0) })
        let dropped = CraftLog.stored(CraftIndex.merging(old: earlier, new: reading([.film], read: ["Lens Weekly", "Wikipedia"]), now: now))
        XCTAssertTrue(dropped.contains("• dropped: Anamorphic — Lens Weekly was read again and, by rules \(CraftIndex.currentVersion), doesn't say so"), dropped)
        XCTAssertTrue(dropped.contains("Complete: no page found failed"), dropped)
        XCTAssertEqual(storedTags(dropped), ["Film"])
        XCTAssertEqual(CraftLog.stored(CraftIndex.merging(old: nil, new: reading([], read: ["Wikipedia"]), now: now)),
                       "\nSTORED IN REEL\n• no Shot on\nComplete: no page found failed to load or was too thin to read; pages left out on purpose (another film's, another craft's, more than the six read, another address of an article) are under NOT READ (rules \(CraftIndex.currentVersion)).\n")
    }

    /// The tags the log's STORED IN REEL section lists, as shown.
    private func storedTags(_ log: String) -> [String] {
        guard let section = log.components(separatedBy: "STORED IN REEL\n").last else { return [] }
        return section.split(separator: "\n").filter { $0.hasPrefix("• ") && !$0.hasPrefix("• dropped:") && $0 != "• no Shot on" }
            .map { String($0.dropFirst(2).components(separatedBy: " — ").first ?? "") }
    }

    /// The tab's reading and the background's: the same summary and the same log for the same texts.
    func testTheTabAndTheBackgroundLogTheSameWay() {
        var details = TMDBMovieDetails(id: 7, title: "The Quiet Harbour", releaseDate: "2020-01-01")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Jane Doe", job: "Director of Photography")])
        let article = FilmArticle(title: "The Quiet Harbour", extract: "== Production ==\nThe film was shot on 35 mm film by Jane Doe, on the coast of Galicia.")
        let sources = CameraReading(sources: [CameraReading.Source(title: "Harbour light", site: "Lens Weekly",
                                                                   url: URL(string: "https://example.com/a")!, paragraphs: ["We used C-Series anamorphic lenses throughout."])],
                                    more: [], cinematographer: nil)
        let tab = CraftReader.reading(of: details, articleTitle: "The Quiet Harbour", article: article, reading: sources, colour: nil, now: now)
        let again = CraftReader.reading(of: details, articleTitle: "The Quiet Harbour", article: article, reading: sources, colour: nil, now: now)
        XCTAssertEqual(tab.log, again.log)
        XCTAssertEqual(tab.index, CraftReader.index(of: details, article: article, reading: sources, colour: nil, now: now))
        XCTAssertEqual(tab.index.read, ["Lens Weekly", "Wikipedia"])
        XCTAssertTrue(tab.log.contains("SHOT ON, IN THIS READING"))
    }

    // MARK: The queue

    private func film(_ id: Int, drive: String = "Main", craft: CraftIndex? = nil, attempt: CraftAttempt? = nil, facts: Bool = true) -> FilmEntry {
        var entry = FilmEntry(driveID: drive, relativePath: "Film \(id).mkv", fileName: "Film \(id).mkv", size: 1, modified: nil, addedAt: then)
        entry.tmdb = TMDBMovieDetails(id: id, title: "Film \(id)")
        entry.craft = craft
        entry.craftAttempt = attempt
        if facts { entry.funFacts = FunFacts(facts: [], articleTitle: "Film \(id)", fetchedAt: then) }
        return entry
    }

    private func done(at date: Date) -> CraftIndex { CraftIndex(readAt: date, shotOn: [], names: [], sources: 2, read: ["Wikipedia"]) }

    func testOneJobForEachFilmHoweverManyCopies() {
        let films = [film(1), film(1, drive: "Backup"), film(2), film(2, drive: "Backup"), film(3)]
        XCTAssertEqual(CraftQueue.due(films, now: now).map { $0.tmdb?.id }, [1, 2, 3])
        XCTAssertEqual(CraftQueue.due(films, attempted: [2], now: now).map { $0.tmdb?.id }, [1, 3], "tried already this run")
    }

    func testWhatsMissingOrStaleIsDueAndTheLongestWaitingFirst() {
        let films = [film(1, craft: done(at: now)),                                         // read: not due
                     film(2, craft: CraftIndex(version: 6, readAt: now, shotOn: [], names: [])),  // older rules
                     film(3),                                                                // never read
                     film(4, craft: done(at: now.addingTimeInterval(-200 * 86_400))),        // half a year ago
                     film(5, facts: false)]                                                  // facts not in yet
        XCTAssertEqual(CraftQueue.due(films, now: now).map { $0.tmdb?.id }, [3, 4, 2])
        XCTAssertEqual(CraftQueue.state(of: films[4], now: now), .waitingForFacts)
    }

    func testNewerRulesComeBeforeAPlannedRetry() {
        var older = CraftIndex(version: 6, readAt: now, shotOn: [.film], names: [], unanswered: ["Lens Weekly"])
        older.retryAt = now.addingTimeInterval(7 * 86_400)
        XCTAssertTrue(CraftQueue.isDue(craft: older, attempt: nil, hasFacts: true, inCollection: false, now: now))
        var current = older
        current.version = CraftIndex.currentVersion
        XCTAssertFalse(CraftQueue.isDue(craft: current, attempt: nil, hasFacts: true, inCollection: false, now: now), "by these rules, it waits")
        XCTAssertTrue(CraftQueue.isDue(craft: current, attempt: nil, hasFacts: true, inCollection: false, now: now.addingTimeInterval(8 * 86_400)))
    }

    func testAFilmThatCantBeReachedWaitsItsTurn() {
        let first = CraftAttempt.failed(after: nil, now: now)
        XCTAssertEqual(first.retryAt, now.addingTimeInterval(6 * 3600))
        var attempt = first
        for _ in 0..<5 { attempt = CraftAttempt.failed(after: attempt, now: now) }
        XCTAssertEqual(attempt.retryAt, now.addingTimeInterval(30 * 86_400), "monthly at most, never given up")
        XCTAssertEqual(CraftAttempt.failed(after: CraftAttempt(at: then, failures: 5, retryAt: then, version: 6), now: now).failures, 1,
                       "newer rules start again")
        XCTAssertEqual(CraftQueue.state(craft: nil, attempt: first, hasFacts: true, inCollection: false, now: now), .failed)
        XCTAssertTrue(CraftQueue.isDue(craft: nil, attempt: first, hasFacts: true, inCollection: false, now: now.addingTimeInterval(7 * 3600)))
        // A failed try since a stored reading by older rules waits too (and isn't read every pass).
        let older = CraftIndex(version: 6, readAt: then, shotOn: [], names: [])
        XCTAssertFalse(CraftQueue.isDue(craft: older, attempt: first, hasFacts: true, inCollection: false, now: now))
    }

    func testFailingFilmsDontHoldUpTheRest() {
        // Six films nothing can be read for, ahead of the rest in the library.
        var films = (1...6).map { film($0) } + (7...9).map { film($0) }
        let firstRun = Array(CraftQueue.due(films, now: now).prefix(6))
        XCTAssertEqual(firstRun.map { $0.tmdb?.id }, [1, 2, 3, 4, 5, 6])
        for i in 0..<6 { films[i].craftAttempt = CraftAttempt.failed(after: nil, now: now) }
        XCTAssertEqual(CraftQueue.due(films, now: now.addingTimeInterval(3600)).map { $0.tmdb?.id }, [7, 8, 9], "the next run reads the others")
        // When their time comes, the films never read come first, then the longest since tried.
        films[6].craft = done(at: now.addingTimeInterval(3600))
        XCTAssertEqual(CraftQueue.due(films, now: now.addingTimeInterval(7 * 3600)).map { $0.tmdb?.id }, [8, 9, 1, 2, 3, 4, 5, 6])
    }

    func testACopyAddedLaterIsReadAsTheFilmsNewestReading() {
        let read = film(1, craft: done(at: now))
        let added = film(1, drive: "Backup")
        XCTAssertEqual(CraftQueue.due([read, added], now: now).count, 0, "the film is read: its new copy waits for nothing")
        XCTAssertEqual(CraftQueue.representatives(of: [added, read]).first?.craft, read.craft)
        XCTAssertEqual(CraftQueue.coverage(of: [added, read], now: now).read, 1)
    }

    func testOfflineDoesntUncountWhatsRead() {
        let readNow = CraftIndex.merging(old: nil, new: reading([.film], read: ["Wikipedia"], unanswered: ["Lens Weekly"]), now: now).index
        let offline = film(1, craft: readNow, attempt: CraftAttempt.failed(after: nil, now: now.addingTimeInterval(7 * 3600)))
        let coverage = CraftQueue.coverage(of: [offline], now: now.addingTimeInterval(8 * 3600))
        XCTAssertEqual(coverage.read, 1)
        XCTAssertEqual(coverage.partial, 1)
        XCTAssertEqual(coverage.toRead, 0)
    }

    func testTheQueueIsTheSameAfterARelaunch() throws {
        let films = [film(1, craft: done(at: now)), film(2, attempt: CraftAttempt.failed(after: nil, now: now)), film(3),
                     film(4, craft: CraftIndex.merging(old: nil, new: reading([], read: ["Wikipedia"], unanswered: ["Lens Weekly"]), now: now).index)]
        let saved = try JSONEncoder().encode(films)
        let reopened = try JSONDecoder().decode([FilmEntry].self, from: saved)
        XCTAssertEqual(reopened.map(\.craftAttempt), films.map(\.craftAttempt))
        for when in [now, now.addingTimeInterval(7 * 3600), now.addingTimeInterval(40 * 86_400)] {
            XCTAssertEqual(CraftQueue.due(reopened, now: when).map { $0.tmdb?.id }, CraftQueue.due(films, now: when).map { $0.tmdb?.id })
        }
    }

    func testOlderLibrariesOpenWithoutTheNewFields() throws {
        let saved = #"{"version":6,"readAt":"2026-10-23T08:00:00Z","shotOn":["film"],"names":[],"sources":2,"discovery":2,"evidence":[{"shotOn":"film","text":"Shot on film.","source":"Wikipedia"}]}"#
        let old = try JSONStore.decode(CraftIndex.self, from: Data(saved.utf8))
        XCTAssertEqual(old.read, [])
        XCTAssertNil(old.evidence.first?.carriedFrom)
        XCTAssertEqual(CraftQueue.state(craft: old, attempt: nil, hasFacts: true, inCollection: false), .olderRules)
    }

    func testOutstandingWorkIsCountedByTheCurrentRules() {
        var older = CraftIndex(version: 6, readAt: now, shotOn: [.film], names: [], sources: 2)
        older.retryAt = now.addingTimeInterval(7 * 86_400)   // planned by 1.9.4: still to read now
        let partial = CraftIndex.merging(old: nil, new: reading([.film], read: ["Wikipedia"], unanswered: ["Lens Weekly"]), now: now).index
        let films = [film(1, craft: done(at: now)), film(1, drive: "Backup", craft: done(at: now)),
                     film(2, craft: older), film(3), film(4, attempt: CraftAttempt.failed(after: nil, now: now)),
                     film(5, craft: partial), film(6, facts: false)]
        let coverage = CraftQueue.coverage(of: films, now: now)
        XCTAssertEqual(coverage.read, 2, "complete or partial by these rules, each film once")
        XCTAssertEqual(coverage.partial, 1)
        XCTAssertEqual(coverage.toRead, 4, "older rules, never read, nothing reached, facts not in")
        XCTAssertEqual(coverage.tagged, 1)
        XCTAssertEqual(CraftQueue.coverage(of: films, removed: [5: [.film]], now: now).tagged, 0)
    }
}
