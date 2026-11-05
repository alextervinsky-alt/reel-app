import XCTest
@testable import ReelCore

/// A diagnostic, not a check (1.10.9): runs only with `REEL_DIAGNOSE=1`. Fetches the pages behind
/// the 1.10.8 audit's regressions and prints, sentence by sentence, every decision the reader made
/// about the named terms, so a cause is read from the code's own behaviour rather than guessed.
final class LiveDiagnosisTests: XCTestCase {
    struct Case {
        let title: String, year: Int, dps: [String], directors: [String], others: [String]
        let url: String?, site: String, wikipedia: String?
        let terms: [String]
    }

    static let cases: [Case] = [
        Case(title: "Boys State", year: 2020, dps: ["Thorsten Thielow"], directors: ["Jesse Moss", "Amanda McBaine"], others: [],
             url: "https://theasc.com/article/spotlight-on-boys-state/", site: "American Cinematographer", wikipedia: nil, terms: ["C300", "Canon", "digital"]),
        Case(title: "Challengers", year: 2024, dps: ["Sayombhu Mukdeeprom"], directors: ["Luca Guadagnino"], others: [],
             url: "https://www.kodak.com/en/motion/blog-post/challengers/", site: "Kodak", wikipedia: nil,
             terms: ["500T", "Technocrane", "push", "handheld", "Steadicam"]),
        Case(title: "Once Upon a Time... in Hollywood", year: 2019, dps: ["Robert Richardson"], directors: ["Quentin Tarantino"], others: [],
             url: "https://theasc.com/article/back-in-time-making-once-upon-a-time-in-hollywood/", site: "American Cinematographer", wikipedia: nil,
             terms: ["FotoKem", "Millennium XL2", "HMI", "Maxi-Brute", "Ektachrome"]),
        Case(title: "Once Upon a Time... in Hollywood", year: 2019, dps: ["Robert Richardson"], directors: ["Quentin Tarantino"], others: [],
             url: "https://britishcinematographer.co.uk/robert-richardson-asc-once-upon-a-time-in-hollywood/", site: "British Cinematographer",
             wikipedia: "Once Upon a Time in Hollywood", terms: ["Ektachrome", "black and white", "Super 8"]),
        Case(title: "F1", year: 2025, dps: ["Claudio Miranda"], directors: ["Joseph Kosinski"], others: [],
             url: "https://britishcinematographer.co.uk/claudio-miranda-asc-acc-f1-the-movie/", site: "British Cinematographer", wikipedia: nil,
             terms: ["Company 3", "LED panels"]),
        Case(title: "Barbie", year: 2023, dps: ["Rodrigo Prieto"], directors: ["Greta Gerwig"], others: [],
             url: "https://britishcinematographer.co.uk/rodrigo-prieto-asc-amc-barbie/", site: "British Cinematographer", wikipedia: nil,
             terms: ["Company 3"]),
        Case(title: "The Banshees of Inisherin", year: 2022, dps: ["Ben Davis"], directors: ["Martin McDonagh"], others: [],
             url: "https://britishcinematographer.co.uk/ben-davis-bsc-the-banshees-of-inisherin/", site: "British Cinematographer", wikipedia: nil,
             terms: ["Natural light"]),
        Case(title: "The Batman", year: 2022, dps: ["Greig Fraser"], directors: ["Matt Reeves"], others: ["Batman Begins"],
             url: nil, site: "Wikipedia", wikipedia: "The Batman (film)", terms: ["golden hour", "magic hour"]),
        Case(title: "Apocalypse Now", year: 1979, dps: ["Vittorio Storaro"], directors: ["Francis Ford Coppola"], others: [],
             url: nil, site: "Wikipedia", wikipedia: "Apocalypse Now", terms: ["16 mm", "2.00:1"]),
        Case(title: "Uncut Gems", year: 2019, dps: ["Darius Khondji"], directors: ["Josh Safdie", "Benny Safdie"], others: [],
             url: "https://theasc.com/article/grain-ghost-frames2-uncut-gems-with-darius-khondji-asc-afc/", site: "American Cinematographer", wikipedia: nil,
             terms: ["Super 16"]),
        Case(title: "Alien: Romulus", year: 2024, dps: ["Galo Olivares"], directors: ["Fede Álvarez"], others: [],
             url: "https://variety.com/2024/artisans/news/alien-romulus-cinematographer-galo-olivares-chestbursting-scene-1236117157/amp/",
             site: "Variety", wikipedia: nil, terms: []),
    ]


    static let inline: [(title: String, year: Int, dps: [String], directors: [String], text: String)] = [
        ("F1", 2025, ["Claudio Miranda"], ["Joseph Kosinski"], "As with Top Gun: Maverick, Miranda and Kosinski were involved in all stages of the process through to post-production, spending four weeks grading with Company 3’s founder and CEO Stefan Sonnenfeld."),
        ("F1", 2025, ["Claudio Miranda"], ["Joseph Kosinski"], "For nighttime events, the tracks are commonly bathed in LED floodlights from tall towers, and the cars have rear lights and LED panels."),
        ("Barbie", 2023, ["Rodrigo Prieto"], ["Greta Gerwig"], "Prieto’s frequent collaborator, Company 3 colourist Yvan Lucas, joined him in the LUT experimentation, continuing the journey they began on The Irishman (2019) developing grading software PPL with Philippe Panzini from Codex."),
        ("The Banshees of Inisherin", 2022, ["Ben Davis"], ["Martin McDonagh"], "Natural light was also a valuable creative tool, as it was when Davis lensed McDonagh’s Three Billboards Outside Ebbing, Missouri."),
        ("Challengers", 2024, ["Sayombhu Mukdeeprom"], ["Luca Guadagnino"], "He avoided Steadicam for the tennis action, instead deploying a Scorpio 45 crane with a Libra head."),
        ("Challengers", 2024, ["Sayombhu Mukdeeprom"], ["Luca Guadagnino"], "Guadagnino unleashes one impossible shot after another in this finale: first-person-perspective shots of the ball speeding from racquet to racquet, a faux-double split-diopter composite shot of all three players, a moment where the players appear."),
        ("Uncut Gems", 2019, ["Darius Khondji"], ["Josh Safdie"], "Darius Khondji: Without me, the film might have easily been shot in Super 35, or Super 16."),
        ("Nomadland", 2021, ["Joshua James Richards"], ["Chloé Zhao"], "And beyond all these nice things that we learn from Terry, like shooting at magic hour, or with wide angle lenses, the most important thing is what cinema really means to a filmmaker."),
        ("The Holdovers", 2023, ["Eigil Bryld"], ["Alexander Payne"], "And all the DPs of the period that I really admired would push the film stock or they would do handheld or whatever."),
        ("Dallas Buyers Club", 2013, ["Yves Bélanger"], ["Jean-Marc Vallée"], "Like the RED, the Alexa offers a broad spectrum of colors and shadows in even the darkest natural lighting conditions."),
        ("No Country for Old Men", 2007, ["Roger Deakins"], ["Joel Coen"], "It was presented in its theatrical 2.35:1 anamorphic widescreen aspect ratio and in Dolby Digital 5.1 (English, Spanish)."),
        ("The Irishman", 2019, ["Rodrigo Prieto"], ["Martin Scorsese"], "The sort of weaving aspect–or the word you used, “jankiness”–was not totally purposeful, and Scorsese usually complains about Steadicam not being really steady, like a dolly shot, so he’s not a fan, even though he’s used Steadicam classically in some unforgettable shots."),
        ("Interstellar", 2014, ["Hoyte van Hoytema"], ["Christopher Nolan"], "The extended, unbroken nature of the shots was planned in rehearsal and accomplished with Steadicam and hand-held cameras, with blocking and dialog timed perfectly with the sweeping camera movement."),
        ("Shutter Island", 2010, ["Robert Richardson"], ["Martin Scorsese"], "The film needed two looks: a Kodachrome look and an emulation of the ENR silver-retention process."),
    ]

    func testTraceSentences() throws {
        guard ProcessInfo.processInfo.environment["REEL_DIAGNOSE"] == "1" else { throw XCTSkip("diagnostic only") }
        for c in Self.inline {
            let people = c.dps + c.directors
            say("===== \(c.title): \(c.text.prefix(200))")
            say("   aboutOtherFilm=\(TechSpecs.aboutOtherFilm(c.text, year: c.year, people: people, title: c.title)) namesAnotherFilm=\(TechSpecs.namesAnotherFilm(c.text, title: c.title, otherTitles: [], people: people)) productions=\(PageContext.productions(in: [c.text], title: c.title, people: people))")
            for rule in TechSpecs.rules {
                for (name, at) in rule.found(in: c.text) {
                    let whole = TechSpecs.segmentRange(of: c.text, around: at)
                    let r = TechSpecs.reading(c.text, at: at, title: c.title, otherTitles: [], people: people, kind: rule.kind)
                    say("   \(rule.kind) \(name) setAside=\(String(describing: TechSpecs.setAside(c.text, at: at, title: c.title, people: people))) denied=\(TechSpecs.denied(c.text, at: at)) hedges=\(TechSpecs.hedges(c.text, around: at, within: whole)) about=\(r.aboutThisFilm) captured=\(r.captured) tested=\(TechSpecs.testedOnly(c.text, at: at)) intended=\(TechSpecs.saidAsIntended(c.text, at: at)) finishing=\(TechSpecs.aboutFinishing(c.text, at: at))")
                }
            }
            let one = TechSpecs.read(texts: [TechSpecs.Text(source: "British Cinematographer", paragraphs: [c.text])], cinematographers: c.dps, directors: c.directors, year: c.year, title: c.title)
            say("   → accepted [\(one.specs.map(\.name).joined(separator: ", "))] mentioned [\(one.mentioned.map { "\($0.name)/\($0.attribution)" }.joined(separator: ", "))]")
        }
    }

    func say(_ line: String) { FileHandle.standardOutput.write(Data(("DIAG| " + line + "\n").utf8)) }

    func testTraceRegressions() async throws {
        guard ProcessInfo.processInfo.environment["REEL_DIAGNOSE"] == "1" else { throw XCTSkip("diagnostic only") }
        for c in Self.cases {
            say("===== \(c.title) — \(c.url ?? c.wikipedia ?? "")")
            var texts: [TechSpecs.Text] = []
            let people = c.dps + c.directors
            if let address = c.url, let url = URL(string: address) {
                let got = await CameraSourcesClient().researchPage(url, site: c.site, title: nil, noting: UnansweredSites())
                guard let page = got.source else { say("not fetched: \(String(describing: got.failure))"); continue }
                say("page title: \(page.title) | paragraphs \(page.paragraphs.count) | url \(page.url.absoluteString)")
                let judged = CameraSources.judged(page, filmTitle: c.title, otherTitles: c.others, people: people, year: c.year)
                let context = judged.context!
                say("context: \(context.kind.rawValue) anchored \(context.anchored) productions \(context.productions)")
                say("isDistinctive \(PageContext.isDistinctive(c.title)); namesTitle(pageTitle) \(TechSpecs.namesTitle(page.title, title: c.title)); "
                    + "paragraphs naming title \(page.paragraphs.filter { PageContext.names($0, title: c.title) }.count)/\(page.paragraphs.count)")
                let reading = CameraReading(sources: [judged], more: [], cinematographer: nil)
                texts = CraftReader.texts(article: nil, reading: reading, hiding: false)
                let anchors = context.aboutFilm ? nil : PageContext.anchors(page.paragraphs, title: c.title, otherTitles: c.others + context.productions,
                                                                           people: people, inherit: context.kind == .otherProduction)
                for (p, paragraph) in page.paragraphs.enumerated() {
                    for (s, sentence) in Digest.sentences(in: paragraph).enumerated()
                    where c.terms.contains(where: { sentence.range(of: $0, options: .caseInsensitive) != nil }) {
                        let anchored = anchors.map { $0.indices.contains(p) && $0[p].indices.contains(s) ? "\($0[p][s])" : "?" } ?? "page"
                        trace(sentence, paragraph: paragraph, p: p, anchored: anchored, c: c, others: c.others + context.productions)
                    }
                }
            }
            if let name = c.wikipedia, c.url == nil {
                guard let article = try? await WikipediaClient().article(title: name) else { say("no article"); continue }
                texts = CraftReader.texts(article: article, reading: nil, hiding: false)
                let others = c.others + PageContext.productions(in: texts.flatMap { $0.sections.flatMap(\.paragraphs) }, title: c.title, people: people)
                say("article productions: \(others)")
                for paragraph in texts.flatMap({ $0.sections.flatMap(\.paragraphs) }) {
                    for sentence in Digest.sentences(in: paragraph) where c.terms.contains(where: { sentence.range(of: $0, options: .caseInsensitive) != nil }) {
                        trace(sentence, paragraph: paragraph, p: -1, anchored: "article", c: c, others: others)
                    }
                }
            }
            let specs = TechSpecs.read(texts: texts, cinematographers: c.dps, directors: c.directors, year: c.year, title: c.title, otherTitles: c.others)
            say("ACCEPTED: " + specs.specs.map { "\($0.name)" }.joined(separator: ", "))
            for spec in specs.specs where ["bleach bypass", "crane", "dolly", "65 mm", "vintage", "practicals"].contains(spec.name.lowercased()) {
                say("  EVIDENCE \(spec.name) ← \(spec.evidence ?? "")")
            }
            for spec in specs.mentioned.prefix(25) {
                say("mentioned-only: \(spec.name) attr=\(spec.attribution) about=\(spec.aboutThisFilm) capture=\(spec.capture) ← \((spec.evidence ?? "").prefix(160))")
            }
        }
    }

    func trace(_ sentence: String, paragraph: String, p: Int, anchored: String, c: Case, others: [String]) {
        let people = c.dps + c.directors
        say("-- [p\(p) anchored=\(anchored)] \(sentence.prefix(300))")
        say("   namesTitle=\(TechSpecs.namesTitle(sentence, title: c.title)) namesOnlyAsReference=\(TechSpecs.namesOnlyAsReference(sentence, title: c.title)) "
            + "aboutOtherFilm=\(TechSpecs.aboutOtherFilm(sentence, year: c.year, people: people, title: c.title)) "
            + "namesAnotherFilm=\(TechSpecs.namesAnotherFilm(sentence, title: c.title, otherTitles: others, people: people)) "
            + "pageOthersNamed=\(others.filter { TechSpecs.namesTitle(sentence, title: $0) })")
        let one = TechSpecs.read(texts: [TechSpecs.Text(source: c.site, paragraphs: [sentence])], cinematographers: c.dps, directors: c.directors,
                                 year: c.year, title: c.title, otherTitles: others)
        say("   alone → accepted [\(one.specs.map(\.name).joined(separator: ", "))] mentioned [\(one.mentioned.map { "\($0.name)/\($0.attribution)" }.joined(separator: ", "))]")
        let inParagraph = TechSpecs.read(texts: [TechSpecs.Text(source: c.site, paragraphs: [paragraph])], cinematographers: c.dps, directors: c.directors,
                                         year: c.year, title: c.title, otherTitles: others)
        say("   in paragraph → accepted [\(inParagraph.specs.filter { ($0.evidence ?? "").hasPrefix(sentence.prefix(60)) }.map(\.name).joined(separator: ", "))]")
    }
}
