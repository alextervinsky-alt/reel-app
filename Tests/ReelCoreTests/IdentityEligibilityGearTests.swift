import XCTest
@testable import ReelCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reel 1.9.9: one article under two addresses is read once and doesn't hold a reading up; what a
/// sentence is about is settled before it can be a reason or name gear; film-out is the process,
/// not "figure this film out". Shaped like the real pages; apart from the quoted interview lines,
/// the films, people and sites are made up.
final class IdentityEligibilityGearTests: XCTestCase {
    // MARK: A. One article, two addresses

    private let current = URL(string: "https://theasc.com/article/uncanny-valley-blade-runner-2049/")!
    private let legacy = URL(string: "https://ascmag.com/articles/uncanny-valley-blade-runner-2049")!

    func testAnAmericanCinematographerArticleIsOneArticleUnderItsAddresses() {
        let same = [current, legacy, URL(string: "http://www.ascmag.com/articles/uncanny-valley-blade-runner-2049/")!,
                    URL(string: "https://theasc.com/articles/uncanny-valley-blade-runner-2049")!]
        XCTAssertEqual(Set(same.map(CameraSources.identity)), ["theasc.com/article/uncanny-valley-blade-runner-2049"])
        // The addresses themselves are still told apart, for the log.
        XCTAssertNotEqual(CameraSources.addressIdentity(current), CameraSources.addressIdentity(legacy))
    }

    func testOtherArticlesAndOtherSitesStayApart() {
        func id(_ s: String) -> String { CameraSources.identity(URL(string: s)!) }
        XCTAssertNotEqual(id("https://ascmag.com/articles/uncanny-valley-blade-runner-2049"), id("https://ascmag.com/articles/dune-part-two"),
                          "another article of the same site")
        XCTAssertNotEqual(id("https://example.com/articles/uncanny-valley-blade-runner-2049"), id(current.absoluteString),
                          "the same slug on another site")
        XCTAssertNotEqual(id("https://britishcinematographer.co.uk/articles/uncanny-valley-blade-runner-2049"), id(current.absoluteString))
        // Only an article's own address is an alias: not the list page, a tag page or a deeper path.
        XCTAssertEqual(id("https://ascmag.com/articles/"), "ascmag.com/articles")
        XCTAssertEqual(id("https://theasc.com/articles_tag/bob-macdonald-sr/"), "theasc.com/articles_tag/bob-macdonald-sr")
        XCTAssertEqual(id("https://ascmag.com/articles/2017/uncanny-valley"), "ascmag.com/articles/2017/uncanny-valley")
        XCTAssertEqual(id("https://theasc.com/ac_magazine/July2008/TheDarkKnight/page1.php"), "theasc.com/ac_magazine/July2008/TheDarkKnight/page1.php")
    }

    func testTheSecondAddressIsntAskedForAndIsListedWhy() {
        let searched: [CameraSources.Link] = [(url: current, site: "American Cinematographer", title: "Uncanny Valley", cited: nil)]
        let cited: [CameraSources.Link] = [
            (url: legacy, site: "American Cinematographer", title: nil, cited: nil),
            (url: URL(string: "https://theasc.com/article/uncanny-valley-blade-runner-2049")!, site: "American Cinematographer", title: nil,
             cited: URL(string: "http://theasc.com/article/uncanny-valley-blade-runner-2049")!),
            (url: URL(string: "https://www.arri.com/en/news/blade")!, site: "ARRI", title: nil, cited: nil),
        ]
        let merged = CameraSources.merge(searched, adding: cited)
        XCTAssertEqual(merged.links.map(\.url), [current, URL(string: "https://www.arri.com/en/news/blade")!], "asked for once")
        XCTAssertEqual(merged.aliases.map(\.url), [legacy], "the same address written another way isn't an alias")
        XCTAssertEqual(CameraSources.aliasReason(of: current, read: true),
                       "the same article as https://theasc.com/article/uncanny-valley-blade-runner-2049/, which was read")
        XCTAssertEqual(CameraSources.aliasReason(of: current, read: false), "the same article as https://theasc.com/article/uncanny-valley-blade-runner-2049/")
    }

    private func details() -> TMDBMovieDetails {
        var details = TMDBMovieDetails(id: 21, title: "The Quiet Harbour", releaseDate: "2017-01-01")
        details.credits = TMDBCredits(cast: [], crew: [TMDBCrewMember(name: "Jane Doe", job: "Director of Photography")])
        return details
    }

    private var article: CameraReading.Source {
        CameraReading.Source(title: "Uncanny Valley", site: "American Cinematographer", url: current,
                             paragraphs: ["Doe shot The Quiet Harbour on the ARRI Alexa XT with Master Primes.", "More.", "More still."])
    }

    private func alias(read: Bool) -> CameraReading.Skipped {
        var source = CameraReading.Source(title: "American Cinematographer", site: "American Cinematographer", url: legacy, paragraphs: [])
        source.cited = URL(string: "http://ascmag.com/articles/uncanny-valley-blade-runner-2049")
        return CameraReading.Skipped(source: source, reason: CameraSources.aliasReason(of: current, read: read))
    }

    private let arriGone = CameraReading.Skipped(source: CameraReading.Source(title: "ARRI", site: "ARRI", url: URL(string: "https://www.arri.com/en/news/blade")!,
                                                                              paragraphs: []),
                                                 reason: SourceFailure.gone("not found over HTTPS (404)").reason, limit: .gone)

    func testAnArticleReadUnderOneAddressSatisfiesTheOther() throws {
        let reading = CraftReader.reading(of: details(), articleTitle: nil, article: nil,
                                          reading: CameraReading(sources: [article], more: [], cinematographer: nil, skipped: [alias(read: true)]),
                                          colour: nil)
        XCTAssertEqual(reading.index.shotOn, [.digital], "the article's evidence is kept")
        XCTAssertEqual(reading.index.evidence(for: .digital)?.source, "American Cinematographer")
        XCTAssertTrue(reading.index.unanswered.isEmpty)
        XCTAssertTrue(reading.index.limits.isEmpty, "not a page that couldn't be examined")
        XCTAssertEqual(reading.index.coverage, .full)
        let merged = CraftIndex.merging(old: nil, new: reading.index)
        XCTAssertNil(merged.index.retryAt, "no retry for an article that was read")
        // The log says what happened at each address: one read, the other not asked for, and why.
        XCTAssertTrue(reading.log.contains("• American Cinematographer: Uncanny Valley (3 paragraphs)\n  \(current.absoluteString)"), reading.log)
        XCTAssertTrue(reading.log.contains("— the same article as \(current.absoluteString), which was read\n  \(legacy.absoluteString)  (cited as http://ascmag.com/articles/uncanny-valley-blade-runner-2049)"),
                      reading.log)
        XCTAssertFalse(reading.log.contains("DIDN'T ANSWER"))
        let saved = try JSONStore.decode(CraftIndex.self, from: JSONStore.encode(merged.index))
        XCTAssertEqual(saved.coverage, .full)
        XCTAssertEqual(saved.evidence(for: .digital)?.text, "Doe shot The Quiet Harbour on the ARRI Alexa XT with Master Primes.")
    }

    /// The earlier reading kept the other address's timeout; reading again with the article read
    /// under one address ends it, and keeps a page that's really gone.
    func testAStoredTimeoutOfTheOtherAddressDoesntOutliveTheRead() {
        var old = CraftReader.reading(of: details(), articleTitle: nil, article: nil,
                                      reading: CameraReading(sources: [article], more: [], cinematographer: nil, unanswered: ["American Cinematographer"],
                                                             skipped: [CameraReading.Skipped(source: alias(read: true).source,
                                                                                             reason: SourceFailure.unanswered("timed out").reason, limit: .unanswered),
                                                                       arriGone]), colour: nil).index
        old = CraftIndex.merging(old: nil, new: old).index
        XCTAssertEqual(old.coverage, .partial)
        XCTAssertNotNil(old.retryAt)
        let again = CraftReader.reading(of: details(), articleTitle: nil, article: nil,
                                        reading: CameraReading(sources: [article], more: [], cinematographer: nil, skipped: [alias(read: true), arriGone]),
                                        colour: nil)
        let merged = CraftIndex.merging(old: old, new: again.index)
        XCTAssertEqual(merged.index.coverage, .limited, "complete: the ARRI page is still gone")
        XCTAssertEqual(merged.index.limits.map(\.site), ["ARRI"], "the real limit stays; the other address isn't one")
        XCTAssertNil(merged.index.retryAt)
        XCTAssertTrue(merged.index.unanswered.isEmpty)
        XCTAssertEqual(merged.index.shotOn, [.digital])
        XCTAssertTrue(CraftLog.stored(merged).contains("Complete, with limits: 1 page found couldn't be examined: 1 gone: not found over HTTPS (404)."))
    }

    /// When the article itself didn't answer under the address asked for, the reading is honestly
    /// incomplete and read again, whatever the other address.
    func testAnArticleThatDidntAnswerUnderEitherAddressIsRetried() {
        let timedOut = CameraReading.Skipped(source: CameraReading.Source(title: "Uncanny Valley", site: "American Cinematographer", url: current, paragraphs: []),
                                             reason: SourceFailure.unanswered("timed out").reason, limit: .unanswered)
        let wiki = CameraReading.Source(title: "Wiki", site: "Lens Weekly", url: URL(string: "https://lens.example/a")!,
                                        paragraphs: ["The Quiet Harbour was shot on the ARRI Alexa XT.", "Two.", "Three."])
        let reading = CraftReader.reading(of: details(), articleTitle: nil, article: nil,
                                          reading: CameraReading(sources: [wiki], more: [], cinematographer: nil, unanswered: ["American Cinematographer"],
                                                                 skipped: [timedOut, alias(read: false)]), colour: nil)
        XCTAssertEqual(reading.index.coverage, .partial)
        XCTAssertEqual(reading.index.limits.map(\.url), [current.absoluteString], "the address asked for, not the other")
        XCTAssertNotNil(CraftIndex.merging(old: nil, new: reading.index).index.retryAt)
        XCTAssertTrue(reading.log.contains("— the same article as \(current.absoluteString)\n"), "not said to have been read")
    }

    // MARK: B. Whose production a sentence is about

    private func craft(_ paragraphs: [String], title: String = "The Quiet Harbour", people: [String] = ["Jane Doe"],
                       directors: [String] = ["Carl Example"], year: Int = 2015, interview: Bool = true) -> (TechSpecs, CraftIndex) {
        let specs = TechSpecs.read(texts: [TechSpecs.Text(source: "Lens Weekly", paragraphs: paragraphs, isInterview: interview)],
                                   cinematographers: people, directors: directors, year: year, title: title)
        return (specs, CraftIndex.make(from: specs, colour: nil, keywords: []))
    }

    private func cameras(_ specs: TechSpecs) -> [String] { specs.names(.camera).map { $0.lowercased() } }

    /// The interview's shape: questions as their own paragraphs, the answers after "RH:". The 50-50
    /// line is in the answer to the question about the next film.
    func testTheExMachinaInterview() {
        let (specs, craft) = craft([
            "What intrigued you about Ex Machina?",
            "RH: The script was a chamber piece, and I wanted the house to feel like a character.",
            "The VFX are simple but stunning. How did you shoot Ava?",
            "RH: For example, although the main shoot was with the F65, I sometimes used an F55 for handheld.",
            "What can you tell us about Testament Of Youth?",
            "RH: It’s the same actress, Alicia, same camera, F65, plus and F55, and same Anamorphic lenses, as on Ex Machina, but the similarities stop there.",
            "RH: I knew the F65 from my work on Ex Machina, and shot with that alongside the F55 – probably about 50-50.",
        ], title: "Ex Machina", people: ["Rob Hardy"], directors: ["Alex Garland"])
        XCTAssertEqual(craft.shotOn, [.digital], "still Digital")
        let why = craft.evidence(for: .digital)
        XCTAssertTrue(why?.text.hasSuffix("although the main shoot was with the F65, I sometimes used an F55 for handheld.") ?? false, "\(why?.text ?? "")")
        XCTAssertEqual(why?.source, "Lens Weekly")
        XCTAssertEqual(why?.shotOn, .digital)
        XCTAssertFalse(why?.text.contains("50-50") ?? true)
        XCTAssertFalse(specs.specs.contains { ($0.evidence ?? "").contains("50-50") }, "nothing read from the other film's answer")
        XCTAssertTrue(TechSpecs.namesOnlyAsReference("RH: I knew the F65 from my work on Ex Machina, and shot with that alongside the F55.", title: "Ex Machina"))
    }

    func testAReasonOnlyFromWhatsSaidOfThisFilm() {
        // The only camera named is in the answers about another film: no tag, rather than its camera.
        let (specs, craft) = craft([
            "What intrigued you about The Quiet Harbour?",
            "JD: The script, mostly, and Carl's way with actors.",
            "What can you tell us about Glass Rivers Of Home?",
            "JD: The main shoot was with the Alexa 35, and I used the Alexa Mini for the car work.",
            "JD: Coming off The Quiet Harbour, we wanted something rougher.",
        ])
        XCTAssertEqual(craft.shotOn, [])
        XCTAssertTrue(cameras(specs).isEmpty, "\(specs.names(.camera))")
        // A question back about this film: its answers are this film's again.
        let (_, back) = self.craft([
            "What can you tell us about Glass Rivers Of Home?",
            "JD: The main shoot was with the Alexa 35.",
            "And how did you shoot The Quiet Harbour?",
            "JD: We shot it on the Sony Venice 2, mostly handheld.",
        ])
        XCTAssertEqual(back.shotOn, [.digital])
        XCTAssertTrue(back.evidence(for: .digital)?.text.hasSuffix("We shot it on the Sony Venice 2, mostly handheld.") ?? false)
    }

    func testThisFilmNamedAsEarlierWorkDoesntLendItTheNextFilmsGear() {
        // Not an interview, and no question: the sentence alone says the title is a point of reference.
        let (specs, craft) = craft([
            "Having learned the Alexa Mini LF from her work on The Quiet Harbour, Doe used it again for the sequel.",
            "As on The Quiet Harbour, the Alexa 65 was the A camera.",
            "Since The Quiet Harbour, Doe has shot everything on Kodak 5219.",
            "The Quiet Harbour was shot on the Sony Venice 2.",
        ], interview: false)
        XCTAssertEqual(craft.shotOn, [.digital], "not Film from the later films' Kodak")
        XCTAssertEqual(craft.evidence(for: .digital)?.text, "The Quiet Harbour was shot on the Sony Venice 2.")
        XCTAssertEqual(cameras(specs).filter { $0.contains("alexa") }, [], "\(specs.names(.camera))")
        for sentence in ["Having learned the Alexa Mini LF from her work on The Quiet Harbour, Doe used it again.",
                         "As on The Quiet Harbour, the Alexa 65 was the A camera.", "Unlike The Quiet Harbour, the sequel was shot on film."] {
            XCTAssertTrue(TechSpecs.namesOnlyAsReference(sentence, title: "The Quiet Harbour"), sentence)
        }
        for sentence in ["On The Quiet Harbour, we shot with the Sony Venice 2.", "The Quiet Harbour was shot on film.",
                         "As The Quiet Harbour was shot at night, Doe chose the Venice 2.",
                         "Since The Quiet Harbour was shot on film, the grain was part of the look.",
                         "It looks like The Quiet Harbour, which was shot on 35mm film.",
                         "Shortly after The Quiet Harbour was shot, Doe moved to London.",
                         "Footage from The Quiet Harbour was scanned at 4K.",
                         "Like on The Quiet Harbour, we shot on film, and The Quiet Harbour itself was all 35mm."] {
            XCTAssertFalse(TechSpecs.namesOnlyAsReference(sentence, title: "The Quiet Harbour"), sentence)
        }
    }

    func testFirstPersonAndRetrospectiveStatementsOfThisFilmStay() {
        let (_, first) = craft(["JD: On The Quiet Harbour, I shot with the Sony Venice 2 throughout."])
        XCTAssertEqual(first.shotOn, [.digital])
        let (_, looking) = craft(["JD: Looking back, we shot The Quiet Harbour on Kodak 5219, and I'd do it again."])
        XCTAssertEqual(looking.shotOn, [.film])
        // Earlier work named in the same sentence as a statement about this film doesn't undo it
        // (the gear in the clause about the earlier work is that work's, as before).
        let (_, both) = craft(["JD: I knew the Venice 2 from my work on Glass Rivers, and I shot The Quiet Harbour on the Sony Venice 2 too."])
        XCTAssertEqual(both.shotOn, [.digital])
    }

    func testTheClearerStatementAndTheFilmsOwnSheetWin() {
        let (_, plain) = craft(["JD: Doe liked the Venice 2 for the night work.", "JD: The Quiet Harbour was shot on the Sony Venice 2."])
        XCTAssertTrue(plain.evidence(for: .digital)?.text.hasSuffix("The Quiet Harbour was shot on the Sony Venice 2.") ?? false)
        let (_, sheet) = craft(["JD: Doe liked the Venice 2's colour.", "Camera: Sony Venice 2 | Lenses: Cooke S7/i | Format: 2.39:1"])
        XCTAssertEqual(sheet.evidence(for: .digital)?.text, "Camera: Sony Venice 2 | Lenses: Cooke S7/i | Format: 2.39:1")
        XCTAssertTrue(TechSpecs.saidDirectly("Although the main shoot was with the F65, we also used an F55.",
                                             at: "Although the main shoot was with the F65, we also used an F55.".range(of: "F65")!, title: "Ex Machina"))
    }

    func testScopeIsntChangedByAReference() {
        let (_, craft) = craft(["Some 30 percent of the footage was shot with IMAX cameras.",
                                "Since The Quiet Harbour, Doe has shot everything with IMAX cameras."], interview: false)
        XCTAssertEqual(craft.label(for: .imax), "IMAX (in part)", "the later films' whole isn't this film's")
        XCTAssertEqual(craft.evidence(for: .imax)?.text, "Some 30 percent of the footage was shot with IMAX cameras.")
    }

    /// Questions that aren't about another production don't change what the answers are about.
    func testQuestionsAboutPeopleGearOrNothingInParticular() {
        let people = ["Jane Doe", "Jane", "Doe"], directors = ["Carl Example", "Carl", "Example"]
        XCTAssertTrue(TechSpecs.asksAboutAnother("What can you tell us about Testament Of Youth?", title: "Ex Machina", people: people))
        XCTAssertTrue(TechSpecs.asksAboutAnother("And what about your next film?", title: "The Quiet Harbour", people: people))
        XCTAssertFalse(TechSpecs.asksAboutAnother("What intrigued you about The Quiet Harbour?", title: "The Quiet Harbour", people: people))
        XCTAssertFalse(TechSpecs.asksAboutAnother("What can you tell us about Carl Example?", title: "The Quiet Harbour", people: people + directors))
        XCTAssertFalse(TechSpecs.asksAboutAnother("Tell us about Panavision Primo lenses?", title: "The Quiet Harbour", people: people))
        XCTAssertFalse(TechSpecs.asksAboutAnother("How did you decide on the Aspect ratio?", title: "The Quiet Harbour", people: people))
        XCTAssertFalse(TechSpecs.asksAboutAnother("How did you shoot Ava?", title: "The Quiet Harbour", people: people), "one capitalised word: a character, a place")
        let (_, gear) = craft(["Tell us about Panavision Primo lenses?", "JD: We shot The Quiet Harbour with Panavision Primo anamorphic lenses."])
        XCTAssertTrue(gear.shotOn.contains(.anamorphic), "the answer to a question about gear is this film's")
        let (specs, next) = craft(["And what about your next film?", "JD: We're shooting it on the Alexa 35."])
        XCTAssertEqual(next.shotOn, [])
        XCTAssertTrue(cameras(specs).isEmpty)
    }

    // MARK: C. Film-out, the process

    private func finish(_ sentences: [String], interview: Bool = true) -> [String] {
        let (specs, _) = craft(sentences, interview: interview)
        return specs.names(.finish)
    }

    func testFilmOutInOrdinaryProseIsntGear() {
        XCTAssertFalse(finish(["The invitations called the film out as “a gonzo, stylized horror fever-dream” (Variety)."]).contains("Film-out"))
        XCTAssertFalse(finish(["“Carl exhausted every option to crack this code and try to figure this film out,” adds Doe."]).contains("Film-out"))
        for prose in ["The studio put the film out in theaters for a week.", "They rushed to get the film out to audiences before the festival.",
                      "Carl wanted to make a film out of the novel.", "The critics singled the film out of a crowded year."] {
            XCTAssertFalse(finish([prose]).contains("Film-out"), prose)
        }
    }

    func testFilmOutAsTheProcessStays() {
        for technical in ["We did a film-out using an Arrilaser at FotoKem and did a contact print from that.",
                          "You do your DI and grade your movie, then you film out to negative, then you print that negative.",
                          "The team evaluated alternate processes that could be used in the film out process for The Quiet Harbour.",
                          "The Quiet Harbour was finished digitally and recorded back to film for its release prints."] {
            XCTAssertTrue(finish([technical]).contains("Film-out"), "\(technical): \(finish([technical]))")
        }
    }

    func testFilmOutNeitherMakesNorRemovesATagAndIsKept() throws {
        // A false film-out beside how it was shot: the tag stands, the name isn't there.
        let (specs, craft) = craft(["The Quiet Harbour was shot on the ARRI Alexa Mini.",
                                    "The invitations called the film out as a fever-dream."])
        XCTAssertEqual(craft.shotOn, [.digital])
        XCTAssertFalse(craft.names.contains("Film-out"))
        XCTAssertFalse(specs.names(.finish).contains("Film-out"))
        // A real film-out is a finishing note, not Film.
        let (_, finished) = self.craft(["The Quiet Harbour was shot on the ARRI Alexa Mini.",
                                        "We did a film-out using an Arrilaser at FotoKem."])
        XCTAssertEqual(finished.shotOn, [.digital])
        XCTAssertTrue(finished.names.contains("Film-out"))
        let saved = try JSONStore.decode(CraftIndex.self, from: JSONStore.encode(CraftIndex.merging(old: nil, new: finished).index))
        XCTAssertTrue(saved.names.contains("Film-out"))
        // Another film's film-out isn't this film's.
        XCTAssertFalse(finish(["On his 2007 feature Glass Rivers, Doe did a film-out at FotoKem."]).contains("Film-out"))
    }
}
