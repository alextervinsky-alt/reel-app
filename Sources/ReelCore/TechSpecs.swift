import Foundation

/// How a film was shot, from what's written about it: the film's Wikipedia article, the
/// interviews and craft articles it cites (American Cinematographer, British Cinematographer…)
/// and the cinematographer's own article. It picks out the cameras, lenses, lights, grip, filters,
/// film stock, format and finish they name, and sorts what they say the way a cinematography
/// piece tells it: the filmmakers' own words, the visual idea, what it drew on, the frame, the
/// light, the colour, particular scenes, what was hard or new, and the cinematographer's history
/// with the director — each with where it was read, the most telling first. Only names of real
/// gear are picked out (an "Alexa" is a camera when it's an ARRI Alexa, not an actor), formats
/// only where the sentence is about the shooting, not the release ("released in IMAX" is not
/// "shot in IMAX"), and never from what critics or awards said, or from sections about the
/// music, release or reception. A sentence that only says who shot it says nothing.
public struct TechSpecs: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case camera, lens, format, light, support, filter, finish
    }

    public struct Spec: Equatable, Sendable, Identifiable {
        public let kind: Kind
        public let name: String
        /// A word Reel chose ("Digital", "Natural light"), not the article's own (so not looked for in it).
        public var isFixedName = false
        /// The first sentence that names it, and where it was read (nil: the film's Wikipedia article).
        public var evidence: String? = nil
        public var source: String? = nil
        /// Said of part of the film only ("for the flashbacks", "the battle scenes", "the rest").
        public var partial = false
        /// Part of the film by a stated share ("about 28 minutes", "15–20% IMAX footage", "much of the
        /// filming"): outweighs a sentence that only says it was filmed that way.
        public var share = false
        /// Said of the whole film in so many words ("the entire film", "shot entirely in IMAX").
        public var wholeFilm = false
        /// Its sentence says this film was shot with it ("shot on", "chose", "his main camera", a
        /// spec list), not an opinion, a comparison, other work or a look: only these are Shot on tags.
        public var capture = false
        /// About this film: not other work, another film or gear in general ("I shoot a lot of
        /// commercials with the Red", "Chazelle's La La Land… in CinemaScope").
        public var aboutThisFilm = true
        public var id: String { kind.rawValue + "|" + name.lowercased() }
        /// How firmly it's said of how much of the film: the whole in so many words (3), a stated share
        /// (2), plainly (1), part of it (0).
        public var scopeRank: Int { wholeFilm ? 3 : share ? 2 : partial ? 0 : 1 }
    }

    /// A sentence (or two that belong together) and where it was read.
    public struct Note: Equatable, Sendable, Identifiable {
        public let text: String
        /// "American Cinematographer"; nil for the film's own Wikipedia article.
        public let source: String?
        /// How much it says: gear named, precise detail, a reason, the filmmakers' own account.
        /// The most telling notes come first.
        public var weight = 0
        /// The whole paragraph it's from, to read more (nil when the note is most of it).
        public var context: String?
        /// The gear and techniques it names ("ARRI Alexa 65", "Steadicam"), as the sheet lists them.
        public var names: [String] = []
        public var id: String { text }
    }

    /// Something written about the film to read: the film's article (no source), an interview or
    /// craft article, or the cinematographer's article.
    public struct Text: Equatable, Sendable {
        public let source: String?
        public let sections: [FilmArticle.Section]
        /// An interview or craft article: its first-person sentences and quotes are the
        /// filmmakers' own words, and only what's about the look is read from it.
        public let isInterview: Bool
        /// A page about many films ("The best films of 2024", a festival round-up): read only where it
        /// names this film.
        public var isList = false

        public init(source: String?, sections: [FilmArticle.Section], isInterview: Bool, isList: Bool = false) {
            self.source = source
            self.sections = sections
            self.isInterview = isInterview
            self.isList = isList
        }

        public init(source: String, paragraphs: [String], isInterview: Bool = true, isList: Bool = false) {
            self.init(source: source, sections: [FilmArticle.Section(id: 0, title: "", paragraphs: paragraphs)], isInterview: isInterview,
                      isList: isList)
        }
    }

    /// This film's gear and techniques (see `isThisFilms`).
    public let specs: [Spec]
    /// Named, but not said of this film (another film's camera, gear in general): for diagnosis only.
    public var mentioned: [Spec] = []
    /// The texts read as round-ups of many films (only where they name this film), by source.
    public var roundups: [String] = []
    /// Sentences naming gear that aren't in the parts below (at most six).
    public var sentences: [Note]
    /// The filmmakers' own words: interviews, and the cinematographer quoted in the article.
    public var approach: [Note] = []
    /// The visual idea: what the images were meant to do, and the choices made for it.
    public var intent: [Note] = []
    /// What it drew on: paintings, photographers, other films.
    public var references: [Note] = []
    /// How the film was lit: light sources, shadows, contrast.
    public var lighting: [Note] = []
    /// How the camera tells the story: framing, lenses chosen for a look, movement, takes.
    public var cameraLanguage: [Note] = []
    /// The palette, the grade and the texture (stock, grain, finish).
    public var colour: [Note] = []
    /// How one particular scene or shot was done.
    public var scenes: [Note] = []
    /// What was hard, tested, built or done for the first time.
    public var challenges: [Note] = []
    /// The cinematographer and the director: how they came to work together, and before.
    public var collaboration: [Note] = []

    public var isEmpty: Bool { specs.isEmpty }

    public func names(_ kind: Kind) -> [String] {
        specs.filter { $0.kind == kind }.map(\.name)
    }

    /// Reads paragraphs with no headings (tests, plain text).
    public static func read(_ paragraphs: [String], cinematographers: [String] = []) -> TechSpecs {
        read(sections: [FilmArticle.Section(id: 0, title: "", paragraphs: paragraphs)], cinematographers: cinematographers)
    }

    /// Reads the film's article alone.
    public static func read(sections: [FilmArticle.Section], cinematographers: [String], directors: [String] = []) -> TechSpecs {
        read(texts: [Text(source: nil, sections: sections, isInterview: false)], cinematographers: cinematographers, directors: directors)
    }

    /// Reads everything written about the film, in the order given. `cinematographers` are the
    /// film's directors of photography (what they say in interviews is their own words), and
    /// `directors` the film's directors (for how they came to work together).
    /// `year`: the film's, so a sentence about a film years apart isn't read as this one's.
    /// `title`: the film's, so "his work on Carol" isn't read as this one's (but "his work on" this film is).
    /// `otherTitles`: the other films of its collection ("Alien" for Alien: Romulus), so what's said
    /// of them isn't a Shot on tag for this one.
    public static func read(texts: [Text], cinematographers: [String], directors: [String] = [], year: Int? = nil,
                            title: String? = nil, otherTitles: [String] = []) -> TechSpecs {
        var found: [Spec] = []
        var gear: [Note] = []
        var approach: [Note] = []
        var intent: [Note] = []
        var references: [Note] = []
        var lighting: [Note] = []
        var cameraLanguage: [Note] = []
        var colour: [Note] = []
        var scenes: [Note] = []
        var challenges: [Note] = []
        var collaboration: [Note] = []
        // The full name, and the first and last names alone ("Hong" for Hong Kyung-pyo, "Deakins"
        // for Roger Deakins), as articles write them.
        let particles: Set<String> = ["van", "von", "der", "den", "del", "della", "les", "dos", "das"]
        func spellings(_ people: [String]) -> [String] {
            people.flatMap { name -> [String] in
                let parts = name.split(separator: " ").map(String.init)
                let single = [parts.first, parts.last].compactMap { $0 }
                    .filter { $0.count >= 3 && !particles.contains($0.lowercased()) && $0 != name }
                return [name] + Set(single)
            }
        }
        let names = spellings(cinematographers)
        let directorNames = spellings(directors)
        // A cinematographer who directed it too has no director to come together with.
        let withDirector = !directors.isEmpty && Set(directors).isDisjoint(with: cinematographers)
        // A round-up of many films ("the cameras behind this year's festival films") is read only
        // where it names this film or its cinematographer.
        let shortTitle = (title ?? "").split(separator: ":").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        var roundups: [String] = []
        for text in texts {
            let roundup = text.isInterview && !shortTitle.isEmpty && (text.isList || isRoundup(text, title: title ?? ""))
            if roundup { roundups.append(text.source ?? "Wikipedia") }
            // In a round-up, a spec sheet ("Camera: … Lenses: …") is this film's only when it names the
            // film, or follows the paragraph that does closely (one paragraph between at most, no other sheet
            // between; a sheet in several paragraphs counts as one).
            var sinceNamed: Int?, sheetSinceNamed = false, inOwnSheet = false
            for section in text.sections {
                let heading = section.title.lowercased()
                // Never the story, its themes or analysis, even once watched.
                let commentary = !offTopic.contains { heading.contains($0) } && !Spoilers.isAfterSection([section.title])
                let visual = visualHeadings.contains { heading.contains($0) } && !heading.contains("effect")
                for paragraph in section.paragraphs {
                    if roundup {
                        let namesIt = paragraph.range(of: shortTitle, options: .caseInsensitive) != nil
                            || mentions(names, in: paragraph, generic: false)
                        if isSpecList(paragraph) {
                            let own = namesIt || inOwnSheet || ((sinceNamed.map { $0 <= 1 } ?? false) && !sheetSinceNamed)
                            sheetSinceNamed = true
                            inOwnSheet = own
                            if !own { continue }
                        } else {
                            inOwnSheet = false
                            if namesIt {
                                sinceNamed = 0
                                sheetSinceNamed = false
                            } else {
                                sinceNamed = sinceNamed.map { $0 + 1 }
                                continue
                            }
                        }
                    }
                    // "He wanted…" right after a sentence about the cinematographer is theirs too.
                    var aboutThem = false
                    let sentences = Digest.sentences(in: paragraph)
                    var skipNext = false
                    // Inside the quote of an award speech ("…said: “Celluloid is alive and kicking. Four
                    // out of five nominated films were shot on celluloid…”"): not how this film was shot.
                    var speaking = false
                    for (index, sentence) in sentences.enumerated() {
                        let speech = speaking || matches(acceptanceSpeech, sentence)
                        speaking = speech && quoteStaysOpen(sentence, wasOpen: speaking)
                        if skipNext {
                            skipNext = false
                            continue
                        }
                        // The interviewer's questions ("NFS: How does…?") are not the filmmakers' words.
                        if text.isInterview, isQuestion(sentence, source: text.source, people: cinematographers + directors) {
                            aboutThem = false
                            continue
                        }
                        let lowered = sentence.lowercased()
                        var gearNamed = 0
                        var namedHere: [String] = []
                        // About another film ("his Super 16mm work on Carol", "Christopher Nolan's
                        // Oppenheimer", "in 1993, employing a Sony F900"): no gear is read from it,
                        // and it's kept only as how the cinematographer and the director met.
                        let otherFilm = aboutOtherFilm(sentence, year: year, people: names + directorNames, title: title)
                        // "I performed some simple tests. I shot 35mm Double-X, 35mm color film and with the
                        // Arri Alexa.": what was tried, not what it was shot on (unless it says what was chosen).
                        let tried = index > 0 && matches(testsDone, sentences[index - 1]) && !matches(chosenAfter, sentences[index - 1])
                            && !matches(chosenAfter, sentence)
                        if !otherFilm, triggers.contains(where: { lowered.contains($0) }) {
                            let aboutShooting = shooting.contains { lowered.contains($0) }
                            let aboutRelease = release.contains { lowered.contains($0) }
                            for rule in rules {
                                if rule.needsShooting, !aboutShooting || (aboutRelease && !strongShooting(lowered)) { continue }
                                for (name, at) in rule.found(in: sentence) {
                                    // "shot digitally rather than on film": not film.
                                    if denied(sentence, at: at) || workOnAnother(sentence, at: at, title: title) { continue }
                                    // "hybrid photochemical finishing", "70 mm prints": how it was
                                    // finished or shown, not what it was shot on.
                                    if rule.kind != .finish, aboutFinishing(sentence, at: at) { continue }
                                    // "transferring images captured in IMAX onto 35mm negative": what
                                    // it was copied onto, not what it was shot on.
                                    if rule.kind != .finish, transferTarget(sentence, at: at) { continue }
                                    // "a 28mm and a 35mm", "Super 35 sensors": a lens or a sensor, not film.
                                    if rule.isGauge, !filmGauge(sentence, at: at) { continue }
                                    gearNamed += 1
                                    if !namedHere.contains(name) { namedHere.append(name) }
                                    let said = reading(sentence, at: at, title: title, otherTitles: otherTitles, people: names + directorNames)
                                    let share = saidOfShare(sentence, at: at)
                                    let part = share || saidOfPart(sentence, at: at)
                                    found.append(Spec(kind: rule.kind, name: name, isFixedName: rule.fixedName != nil,
                                                      evidence: String(sentence.prefix(400)), source: text.source,
                                                      partial: part, share: share, wholeFilm: !part && saidOfWholeFilm(sentence, at: at),
                                                      capture: said.captured && !tried && !speech, aboutThisFilm: said.aboutThisFilm))
                                }
                            }
                        }
                        let named = gearNamed > 0
                        // An interview talks about much else: only what's about the look is read.
                        let onTopic = !text.isInterview || named || matches(lookWords, sentence)
                        let fits = commentary && onTopic && (25...450).contains(sentence.count) && !matches(reception, sentence)
                        let theirs = mentions(names, in: sentence) || (aboutThem && matches(pronoun, sentence))
                            || (text.isInterview && (quoted(sentence) || matches(firstPerson, sentence)))
                        aboutThem = fits && theirs
                        let light = matches(lightTerms, sentence)
                        // In a section about the look, any sentence about the image (not one that
                        // only names the cinematographer) is about the frame.
                        let image = aboutTheImage(sentence)
                        let camera = matches(cameraTerms, sentence) || (visual && image)
                        let colourful = matches(colourTerms, sentence)
                        // In an interview the sentence after often finishes the thought ("…on film.
                        // It gave us…"): read together.
                        var shown = sentence
                        if text.isInterview, index + 1 < sentences.count, matches(continuation, sentences[index + 1]),
                           sentence.count + sentences[index + 1].count < 520 {
                            shown += " " + sentences[index + 1]
                        }
                        let craft = light || camera || colourful || named
                        let aboutLook = craft || image
                        let because = matches(reason, sentence)
                        var note = Note(text: shown, source: text.source)
                        if paragraph.count > shown.count + 60 { note.context = paragraph }
                        note.names = namedHere
                        note.weight = 2 * min(gearNamed, 3) + (matches(detail, shown) ? 2 : 0) + (because ? 1 : 0)
                            + (text.isInterview ? 1 : 0) - (shown.count < 70 ? 1 : 0)
                        var placed = true
                        if otherFilm {
                            // Only how they came together (often naming a film they shot before).
                            if fits, withDirector, !text.isInterview, mentions(names, in: sentence, generic: false),
                               mentions(directorNames, in: sentence, generic: false), matches(collabTerms, sentence) {
                                add(note, to: &collaboration)
                            }
                            continue
                        }
                        // Where it belongs, in the order a cinematography piece tells it: the
                        // filmmakers' own words, what it drew on, a particular scene, what was hard
                        // or new, the visual idea, then the light, the colour and the frame, gear
                        // alone. How the cinematographer and the director came together goes before
                        // the craft (it often names a film they shot). A sentence that only says who
                        // shot it (no craft, no reason) says nothing.
                        if fits, theirs, text.isInterview || quoted(sentence) {
                            add(note, to: &approach)
                        } else if fits, withDirector, !text.isInterview, !named, !matches(detail, sentence),
                                  mentions(names, in: sentence, generic: false), mentions(directorNames, in: sentence, generic: false),
                                  matches(collabTerms, sentence) {
                            add(note, to: &collaboration)
                        } else if fits, aboutLook, matches(referenceTerms, sentence) {
                            add(note, to: &references)
                        } else if fits, craft, matches(sceneTerms, sentence) {
                            add(note, to: &scenes)
                        } else if fits, aboutLook, matches(challengeTerms, sentence) {
                            add(note, to: &challenges)
                        } else if fits, aboutLook, because || matches(intentTerms, sentence) {
                            add(note, to: &intent)
                        } else if fits, light {
                            add(note, to: &lighting)
                        } else if fits, colourful {
                            add(note, to: &colour)
                        } else if fits, camera {
                            add(note, to: &cameraLanguage)
                        } else if named, !text.isInterview || fits {
                            add(note, to: &gear)
                        } else {
                            placed = false
                        }
                        if placed, shown != sentence { skipNext = true }
                    }
                }
            }
        }
        // The sheet, search and Shot on hold only this film's gear: a camera, a lens or what it was shot
        // on needs a sentence saying so; the rest (light, grip, ratios) only needs to be about this
        // film. Everything else named is kept as mentioned.
        let all = tidy(found)
        let shown = all.filter(isThisFilms)
        var specs = TechSpecs(specs: shown, sentences: ranked(gear, 6))
        specs.mentioned = all.filter { !isThisFilms($0) }
        specs.roundups = roundups
        specs.approach = ranked(approach, 10)
        specs.intent = ranked(intent, 8)
        specs.references = ranked(references, 6)
        specs.lighting = ranked(lighting, 6)
        specs.cameraLanguage = ranked(cameraLanguage, 6)
        specs.colour = ranked(colour, 5)
        specs.scenes = ranked(scenes, 6)
        specs.challenges = ranked(challenges, 6)
        specs.collaboration = ranked(collaboration, 3)
        return specs
    }

    /// Whether a name is this film's: a camera, a lens or what it was shot on needs a sentence saying
    /// this film was shot with it; anything else (light, grip, a frame rate) a sentence about this film.
    static func isThisFilms(_ spec: Spec) -> Bool {
        spec.kind == .camera || spec.kind == .lens || !CraftIndex.shotOn(spec).isEmpty ? spec.capture : spec.aboutThisFilm
    }

    /// A text about many films: eight or more cameras and three or more other films' titles in
    /// quotes (“Twinless”, “Jurassic World Rebirth”), as round-ups write them. A long article about
    /// one film can name many cameras, but not other titles.
    static func isRoundup(_ text: Text, title: String) -> Bool {
        var cameras = Set<String>(), titles = Set<String>()
        let own = title.lowercased()
        let paragraphs = text.sections.flatMap(\.paragraphs)
        // Spec sheets for several films: "Camera:" and "Lenses:" each in two or more paragraphs (one
        // film's own article prints its sheet once, "A Camera: … B Camera: …" included).
        var cameraSheets = 0, lensSheets = 0
        for paragraph in paragraphs {
            var labels = Set<String>()
            for match in specLabel.matches(in: paragraph, range: NSRange(paragraph.startIndex..., in: paragraph)) {
                if let word = Range(match.range(at: 1), in: paragraph) { labels.insert(String(paragraph[word].lowercased().prefix(4))) }
            }
            if labels.contains("came") { cameraSheets += 1 }
            if labels.contains("lens") { lensSheets += 1 }
        }
        if cameraSheets >= 2, lensSheets >= 2 { return true }
        for paragraph in paragraphs {
            for rule in rules where rule.kind == .camera {
                for (name, _) in rule.found(in: paragraph) { cameras.insert(name.lowercased()) }
            }
            for match in quotedTitle.matches(in: paragraph, range: NSRange(paragraph.startIndex..., in: paragraph)) {
                guard let inner = Range(match.range(at: 1), in: paragraph) else { continue }
                let named = paragraph[inner].trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
                let words = named.split(separator: " ")
                guard let first = words.first?.first, first.isUppercase,
                      words.allSatisfy({ $0.count < 4 || ($0.first?.isUppercase ?? false) || ($0.first?.isNumber ?? false) }),
                      named.lowercased() != own else { continue }
                titles.insert(named.lowercased())
            }
            if cameras.count >= 8, titles.count >= 3 { return true }
        }
        return false
    }

    /// Tests spoken of: the sentence after says what was tried.
    static let testsDone = try! NSRegularExpression(
        pattern: #"\b(?:camera|lens|lenses|stock|film|format|digital|look|image|photographic)\s+tests?\b|\b(?:i|we|he|she|they)\s+(?:also\s+)?(?:did|performed|ran|shot|conducted|made|tested)\b[^.]{0,40}\btests?\b|\b(?:i|we|he|she|they)\s+tested\b"#,
        options: [.caseInsensitive])
    /// What was chosen after the tests.
    static let chosenAfter = try! NSRegularExpression(
        pattern: #"\b(?:in the end|ultimately|finally|eventually|chose|chosen|decided|settled on|went with|opted|so we (?:shot|used)|for the (?:film|shoot|production|movie|rest)|principal photography|main camera|(?:the film|the movie|it|the production|the picture) was (?:shot|filmed|photographed|captured))\b"#,
        options: [.caseInsensitive])

    /// A spec sheet's label: "Camera:", "Lenses:", "Format:", "Film stock:".
    static let specLabel = try! NSRegularExpression(pattern: #"(?:^|[\s.;])(Cameras?|Lens(?:es)?|Format|Film stocks?|Stocks?)\s*:"#)

    /// The most telling first (reading order among equals), at most `limit`.
    static func ranked(_ notes: [Note], _ limit: Int) -> [Note] {
        Array(notes.enumerated()
            .sorted { ($0.element.weight, -$0.offset) > ($1.element.weight, -$1.offset) }
            .prefix(limit)
            .map(\.element))
    }

    /// The look in a few plain sentences, from what was found: who shot it, on what, with which
    /// lenses, on film or digitally, the frame and the light (the grip, filters and finish are in
    /// the table). `ratio` and `blackAndWhite` come from Wikidata when the texts don't say them.
    public func brief(by cinematographers: [String], ratio: String? = nil, blackAndWhite: Bool = false) -> String? {
        func list(_ names: [String]) -> String {
            let shown = Array(names.prefix(3))
            switch shown.count {
            case 0: return ""
            case 1: return shown[0]
            default: return shown.dropLast().joined(separator: ", ") + " and " + shown[shown.count - 1]
            }
        }
        /// "Natural light" reads "natural light" mid-sentence; "HMI" and "ARRI SkyPanels" stay.
        func inline(_ names: [String]) -> [String] {
            names.map { name in
                let chars = Array(name)
                guard chars.count > 1, chars[0].isUppercase, chars[1].isLowercase,
                      specs.contains(where: { $0.name == name && $0.isFixedName }) else { return name }
                return name.prefix(1).lowercased() + name.dropFirst()
            }
        }
        var sentences: [String] = []
        let cameras = names(.camera), lenses = names(.lens)
        if !cameras.isEmpty || !lenses.isEmpty {
            var first = "Shot"
            if !cinematographers.isEmpty { first += " by " + list(cinematographers) }
            if !cameras.isEmpty { first += " on " + list(cameras) }
            if !lenses.isEmpty { first += " with " + list(inline(lenses)) + (lenses.count == 1 && !lenses[0].lowercased().contains("lens") ? " lenses" : "") }
            sentences.append(first + ".")
        }
        let formats = names(.format)
        let ratios = formats.filter { $0.contains(":1") }
        let media = formats.filter { !$0.contains(":1") && $0 != "Digital" && $0 != "Film" && $0 != "Black and white" }
        var second: [String] = []
        if !media.isEmpty {
            second.append("photographed on " + list(media))
        } else if formats.contains("Film") {
            second.append("photographed on film")
        } else if formats.contains("Digital") {
            second.append("captured digitally")
        }
        if blackAndWhite || formats.contains("Black and white") { second.append("in black and white") }
        if let frame = ratios.first ?? ratio { second.append("framed at " + frame) }
        if !second.isEmpty {
            let joined = second.joined(separator: ", ")
            sentences.append(joined.prefix(1).uppercased() + joined.dropFirst() + ".")
        }
        // Light sources read as a sentence; times of day and techniques stay in the table.
        let sources = names(.light).filter { !["Magic hour", "Blue hour", "Day for night", "Negative fill"].contains($0) }
        if !sources.isEmpty { sentences.append("Lit with " + list(inline(sources)) + ".") }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    private static func add(_ note: Note, to list: inout [Note]) {
        let words = wordSet(note.text)
        // The same thing said twice (a quote and its paraphrase): once.
        if !list.contains(where: { $0.text == note.text || overlap(wordSet($0.text), words) >= 0.7 }) { list.append(note) }
    }

    static func wordSet(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
    }

    /// How much of the shorter of two sentences the longer one says too (0–1).
    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        let smaller = min(a.count, b.count)
        return smaller == 0 ? 0 : Double(a.intersection(b).count) / Double(smaller)
    }

    /// A question, or a line the interviewer speaks: "Q:", or the publication's initials ("NFS:" in
    /// No Film School, "AC:" in American Cinematographer). The filmmaker's own tag ("DP:") is theirs.
    /// Initials are the filmmakers' only when they're a credited cinematographer's or director's
    /// ("RD:" for Roger Deakins); anyone else's ("BB:", the interviewer) aren't taken for theirs.
    /// `people`: the film's cinematographers and directors, as credited.
    static func isQuestion(_ sentence: String, source: String?, people: [String] = []) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: CharacterSet(charactersIn: " \"”’'"))
        if trimmed.hasSuffix("?") { return true }
        // "Tell us about the small bits you shot digitally.": asked, not said.
        if trimmed.range(of: #"^(?:Tell us|Talk (?:us )?(?:about|through)|Walk us through|Describe|Explain)\b"#, options: .regularExpression) != nil {
            return true
        }
        guard let colon = sentence.firstIndex(of: ":") else { return false }
        let tag = String(sentence[..<colon])
        // "Filmmaker: Scott Derrickson first started…": the magazine speaking, not the filmmakers.
        if let source, !source.isEmpty, tag.caseInsensitiveCompare(source) == .orderedSame { return true }
        guard (1...5).contains(tag.count), tag.allSatisfy({ $0.isUppercase }) else { return false }
        let publication = String((source ?? "").split(separator: " ").compactMap(\.first).filter(\.isUppercase))
        if tag == "Q" || tag == "INT" || (publication.count >= 2 && tag == publication) { return true }
        // The answer, the cinematographer by their job, or a label that isn't a person ("ISO:").
        if notSpeakers.contains(tag) || tag.count < 2 { return false }
        // Their initials, or one of their names in capitals ("ROGER:", "HOYTE:").
        let names = Set(people.flatMap { $0.split(whereSeparator: { $0 == " " || $0 == "-" }).map { $0.uppercased() } })
        return !initials(of: people).contains(tag) && !names.contains(tag)
    }

    /// Capitals before a colon that aren't someone speaking.
    static let notSpeakers: Set<String> = ["A", "DP", "DOP", "ISO", "ASA", "EI", "FPS", "LUT", "HDR", "SDR", "DCP", "DI", "VFX", "SFX",
                                           "FX", "CGI", "LED", "HMI", "RGB", "NB", "PS", "EXT", "TV", "UK", "US", "USA", "NY", "LA",
                                           // A spec sheet's labels in capitals ("LENS:", "STOCK:").
                                           "LENS", "STOCK", "FILM", "RATIO", "IMAX", "ARRI", "RED", "SONY", "KODAK", "CAM", "CAMS",
                                           "GRIP", "LIGHT", "LUTS", "FRAME", "SPECS", "GEAR", "LAB"]

    /// "RD" for Roger Deakins, "HVH" and "HH" for Hoyte van Hoytema, "JJR" and "JR" for Joshua James Richards.
    static func initials(of people: [String]) -> Set<String> {
        var found = Set<String>()
        for person in people {
            let parts = person.split(whereSeparator: { $0 == " " || $0 == "-" }).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let main = parts.filter { !($0.first?.isLowercase ?? true) }
            found.insert(String(parts.compactMap(\.first)).uppercased())
            found.insert(String(main.compactMap(\.first)).uppercased())
            if let first = main.first?.first, let last = main.last?.first { found.insert(String([first, last]).uppercased()) }
        }
        return found
    }

    /// About the picture itself: the look words, leaving out the job's name ("the film's
    /// cinematographer was…" alone says nothing about the image).
    static func aboutTheImage(_ sentence: String) -> Bool {
        let rest = sentence.replacingOccurrences(
            of: #"(?i)\bcinematograph\w*|\bdirector of photography\b|\b(?:was|were|been|be|is|are|had|has|have|previously|also|who|and)\s+shot\b|\bshot\s+(?:by|on|in|for|with)\b"#,
            with: "", options: .regularExpression)
        return matches(lookWords, rest)
    }

    static func quoted(_ sentence: String) -> Bool {
        sentence.contains(where: { "\"“”".contains($0) })
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Whether the sentence names one of them (whole words, as written), or, with `generic`, the
    /// cinematographer by their job.
    static func mentions(_ names: [String], in sentence: String, generic: Bool = true) -> Bool {
        if generic {
            let jobs = ["cinematographer", "director of photography", "cinematographers"]
            let lowered = sentence.lowercased()
            if jobs.contains(where: { lowered.contains($0) }) { return true }
            if sentence.range(of: #"\b(?:DP|DoP|D\.P\.)(?=\W|$)"#, options: .regularExpression) != nil { return true }
        }
        // A first or last name alone, not as part of someone else's name ("Robert De Niro").
        return names.contains { name in
            let alone = name.contains(" ") ? "" : #"(?!\s+\p{Lu})"#
            return sentence.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\b"# + alone,
                                  options: .regularExpression) != nil
        }
    }

    /// Sections whose sentences are never about the approach.
    static let offTopic = ["music", "soundtrack", "score", "release", "reception", "box office", "accolade", "award",
                           "marketing", "home media", "legacy", "critical", "controvers", "lawsuit", "plot", "cast"]
    /// Sections all about the look.
    static let visualHeadings = ["cinematograph", "visual", "look", "lighting", "camera", "style"]

    static let reception = try! NSRegularExpression(
        pattern: #"\b(?:praised|praising|praise|nominated|nominations?|won|wins|awards?|acclaim\w*|critics?|critical|reviewers?|reviews?|box office|grossed|ranked|Oscars?|BAFTAs?|Academy Awards?|premiere[sd]?|debut\w*|screened|re-screened|screenings?|limited release|festivals?|distribut\w*|audiences?|international community)\b"#,
        options: [.caseInsensitive])
    /// What the images were meant to do ("to feel claustrophobic", "a naturalistic look").
    static let intentTerms = try! NSRegularExpression(
        pattern: #"\b(?:visual (?:style|language|approach|concept|idea|grammar|scheme|strategy|motifs?)|aesthetic\w*|the look (?:of|was|is|they|he|she)|look and feel|atmosphere|to feel|feel (?:like|more|less|as)|to make (?:the|it|them|audiences?|viewers?|us|everything)|to convey|to reflect|to evoke|to emphasi[sz]e|to underline|to suggest|to mirror|to express|realis(?:m|t|tic|tically)|naturalis(?:m|t|tic|tically)|claustrophob\w*|intima(?:te|cy)|subjectiv\w*|documentary(?:[- ]like| style| feel| look| aesthetic| approach)|dreamlike|dream-like|painterly|immersive|voyeur\w*|restrain(?:ed|t)|minimalis(?:m|t)|styli[sz](?:ed|ation))\b"#,
        options: [.caseInsensitive])
    /// What the look drew on.
    static let referenceTerms = try! NSRegularExpression(
        pattern: #"\b(?:inspired by|inspiration|influenced by|influences?|referenc\w*|homage|nod to|modell?ed (?:on|after)|in the style of|reminiscent of|paintings?|painters?|photographs? by|photographers? (?:such as|like|(?-i:\p{Lu}))|comic books?|graphic novels?|artworks?)\b"#,
        options: [.caseInsensitive])
    /// One particular scene or shot ("the heist sequence", "one scene was lit…"), not scenes in
    /// general, and not "the night scenes were shot…" (shot the verb).
    static let sceneTerms = try! NSRegularExpression(
        pattern: #"\b(?:the|a|one|its|this|that)\s+(?:(?!(?:were|was|is|are|been|be|being|had|has|have|scenes|sequences|shots)\b)[\w'’-]+\s+){0,3}(?:scene|sequence|set piece|set-piece|montage)\b(?!s)|\b(?:opening|final|closing|last|first|tracking|single|long|wide|aerial|overhead|establishing|crane|Steadicam|dolly) (?:shot|scene|sequence|image)\b(?!s)"#,
        options: [.caseInsensitive])
    /// What was hard, tested, built or done for the first time.
    static let challengeTerms = try! NSRegularExpression(
        pattern: #"\b(?:challeng\w*|difficult(?:y|ies)?|problems?|obstacles?|(?:had|have|has) to (?:build|devise|invent|rig|modify|adapt|find a way|work around|overcome|solve|figure out)|forced to|for the first time|first (?:time|film|feature|production|movie) (?:to|that|in|ever)|pioneer(?:ed|ing)|invent(?:ed|ion|ing)|custom[- ](?:built|made|designed)|specially (?:built|made|designed|adapted)|purpose-built|built (?:a|an|their own|its own|his own|her own)|developed (?:a|an|new|special)|innovat(?:ed|ion|ions|ing)|unprecedented|ground-?breaking|breakthrough|experiment(?:ed|s|ing|ation)|(?:camera|lens|film|screen|light(?:ing)?) tests?|tested|testing)\b"#,
        options: [.caseInsensitive])
    /// How the cinematographer and the director came to work together.
    static let collabTerms = try! NSRegularExpression(
        pattern: #"\b(?:worked (?:with|together)|collaborat\w*|reunit\w*|again with|previously|long-?time|frequent|regular|partnership|recommended|hired|brought (?:in|on)|first (?:time|film|feature) (?:with|together))\b"#,
        options: [.caseInsensitive])
    /// Precise detail: focal lengths, stops, resolutions, ratios, colour temperatures.
    static let detail = try! NSRegularExpression(
        pattern: #"\b\d{1,3}\s?mm\b|\bT\s?\d(?:\.\d)?\b|\bf/\d|\b\d{1,2}K\b|\bISO\s?\d+|\b[1-2]\.\d{2}\s?:\s?1\b|\bstops?\b|\bfoot-?candles?\b|\b\d{4}\s?K(?:elvin)?\b|\bframes per second\b|\bfps\b"#,
        options: [.caseInsensitive])
    /// A sentence that starts by referring back to someone ("He wanted…", "Her approach…").
    static let pronoun = try! NSRegularExpression(pattern: #"^(?:He|She|They|His|Her|Their)\b"#)
    static let lightTerms = try! NSRegularExpression(
        pattern: #"\b(?:lighting|lit|relit|light sources?|natural light|available light|sunlight|daylight|moonlight|candlelight|candles|lamps?|practicals|practical (?:lights?|lighting|lamps?|sources?)|shadows?|chiaroscuro|silhouettes?|magic hour|golden hour|blue hour|overcast|high[- ]contrast|low[- ]contrast|low-key|high-key|tungsten|HMIs?|(?-i:LEDs?)|fluorescent|neon (?:lights?|signs?|lighting|glow)|sodium|gaffer|SkyPanels?|Kino Flos?|backlit|backlight\w*|top ?light\w*|rim light|soft light|hard light|exposure|exposed|underexpos\w*|overexpos\w*|contrast ratio|key light|fill light|bounce|bounced|diffused light|unlit|darkness)\b"#,
        options: [.caseInsensitive])
    /// The palette, the grade and the finish.
    static let colourTerms = try! NSRegularExpression(
        pattern: #"\b(?:colou?r (?:palette|grad\w*|timing|timed|science|scheme|temperature|correction|separation|contrast)|palettes?|colou?r ?grad\w*|graded|grading|colou?rists?|LUTs?|hues?|desaturat\w*|saturat\w*|tint\w*|teal|sepia|monochrom\w*|pastels?|warm(?:er)? (?:tones?|colou?rs?)|cool(?:er)? (?:tones?|colou?rs?)|skin tones?|film emulation|bleach[- ]bypass|skip[- ]bleach|digital intermediate|print film|film grain|grain)\b"#,
        options: [.caseInsensitive])
    /// A choice with its reason or reference ("because…", "the idea was…", "inspired by…").
    static let reason = try! NSRegularExpression(
        pattern: #"\b(?:because|so that|in order to|so as to|the (?:idea|goal|aim|intention|reason|thinking|concept|key) (?:was|is|being|behind)|wanted (?:the|it|to|a|an|us|every|each|this)|felt (?:that|it|the|like)|we felt|inspired by|influenced by|modell?ed (?:on|after)|references?|referenced|referencing|homage|meant to|intended to|in the style of|the way (?:\w+ ){0,3}(?:painted|lit|shot))\b"#,
        options: [.caseInsensitive])
    /// What an interview sentence must be about to be read: the look of the film.
    static let lookWords = try! NSRegularExpression(
        pattern: #"\b(?:the look|cinematograph\w*|camera|cameras|lens|lenses|lensing|lighting|lit|light|lights|frames?|framing|framed|shots?|composition|compositions|exposure|grain|texture|palette|colou?rs?|storyboard\w*|coverage|blocking|close-ups?|wide shots?|visual\w*|images?|imagery|aspect ratio|anamorphic|film stock|stock|LUT|grade|graded|grading|handheld|Steadicam|dolly|crane|focal|depth of field|contrast|shadows?|silhouettes?|daylight|moonlight|sunlight|darkness)\b"#,
        options: [.caseInsensitive])
    /// Said in the first person (an interview's answers).
    static let firstPerson = try! NSRegularExpression(pattern: #"^(?:I|We|I'd|I've|I'm|We'd|We've|We're|My|Our|For me|For us)\b|\b(?:we|I) (?:wanted|decided|chose|used|shot|lit|tested|felt|tried|knew|thought|went|had|did|were|was)\b"#)
    /// A sentence that carries on from the one before ("It gave us…", "That meant…").
    static let continuation = try! NSRegularExpression(pattern: #"^(?:It|That|This|These|Those|So|Which|And|But|Then|The result|The effect|The idea)\b"#)
    static let cameraTerms = try! NSRegularExpression(
        pattern: #"\b(?:handheld|hand-held|Steadicam|long takes?|single takes?|one take|oners?|one-shot|continuous (?:shots?|takes?)|tracking shots?|dolly|dollies|crane shots?|drones?|static (?:shots?|camera)|locked-off|wide shots?|wide-angle|close-ups?|point[- ]of[- ]view|POV|shot compositions?|symmetr\w*|depth of field|shallow focus|deep focus|split diopter|split-screen|zoom(?:s|ed|ing)? (?:in|out|lens\w*|shots?)|crash zooms?|whip pans?|panning|slow[- ]motion|camera movements?|camera moves?|the camera (?:moves?|follows?|stays?|tracks?|pushes|pulls|glides|lingers|never|always|rarely|is)|camerawork|camera work|visual style|visual language|visual approach|lensing|focal lengths?|storyboard\w*|shot lists?|traditional coverage|blocking|aspect ratio|anamorphic|negative space|low[- ]angle|high[- ]angle|Dutch angle|overhead shots?|aerial shots?|360-degree|Snorricam|underwater (?:camera|photography))\b"#,
        options: [.caseInsensitive])

    /// Each name once, in the order first read, and a name left out when a longer one of the same
    /// kind contains it ("ARRI Alexa" when there's "ARRI Alexa 65"). Each keeps its best reading
    /// (its spelling and sentence): one that says this film was shot with it, about the whole film,
    /// before any other.
    static func tidy(_ specs: [Spec]) -> [Spec] {
        func rank(_ spec: Spec) -> Int { (spec.capture ? 8 : 0) + (spec.aboutThisFilm ? 4 : 0) + spec.scopeRank }
        var best: [String: Spec] = [:]
        var order: [String] = []
        for spec in specs {
            guard let known = best[spec.id] else {
                best[spec.id] = spec
                order.append(spec.id)
                continue
            }
            if rank(spec) > rank(known) { best[spec.id] = spec }
        }
        let unique = order.compactMap { best[$0] }
        func covers(_ other: Spec, _ spec: Spec) -> Bool {
            other.kind == spec.kind && other.name.count > spec.name.count && other.name.lowercased().contains(spec.name.lowercased())
        }
        // A shorter name stays when it's the one said of this film's shooting.
        return unique.filter { spec in !unique.contains { covers($0, spec) && ($0.capture || !spec.capture) } }.map { kept in
            // "IMAX 70 mm" for the battle scenes and "IMAX" for the whole film: the whole film (a
            // stated share stands against a sentence that only says it was filmed that way).
            var spec = kept
            if spec.partial, unique.contains(where: { covers(spec, $0) && $0.scopeRank > spec.scopeRank && (!spec.capture || $0.capture) }) {
                spec.partial = false
                spec.share = false
            }
            return spec
        }
    }

    // MARK: Rules

    struct Rule: @unchecked Sendable {
        let kind: Kind
        let regex: NSRegularExpression
        /// Shown instead of the words matched ("Digital" for "shot digitally").
        let fixedName: String?
        /// Only counts in a sentence about the shooting.
        let needsShooting: Bool
        /// A gauge ("35mm", "Super 16"), which is film only where the words around it say film.
        let isGauge: Bool

        init(_ kind: Kind, _ pattern: String, name: String? = nil, caseSensitive: Bool = false, needsShooting: Bool = false,
             isGauge: Bool = false) {
            self.kind = kind
            self.isGauge = isGauge
            // The patterns are fixed and tested; a bad one would fail every test.
            regex = try! NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
            fixedName = name
            self.needsShooting = needsShooting
        }

        /// Each name and where it is in the sentence.
        func found(in sentence: String) -> [(name: String, at: Range<String.Index>)] {
            let range = NSRange(sentence.startIndex..., in: sentence)
            return regex.matches(in: sentence, range: range).compactMap { match in
                guard let found = Range(match.range, in: sentence) else { return nil }
                return (fixedName ?? TechSpecs.display(String(sentence[found])), found)
            }
        }
    }

    // MARK: Said not to have been used

    /// Whether the words at `range` are said not to have been used for this film, in their own
    /// clause: "shot digitally rather than on film" (film), "they considered IMAX, but…", "unlike
    /// his IMAX films", "the Alexa was not used". A clause of its own is not affected: "after testing
    /// several lenses, they chose C-series anamorphics" names anamorphics as used.
    public static func denied(_ sentence: String, at range: Range<String.Index>) -> Bool {
        // Magazines write "didn’t": read as "didn't". Same length, so positions carry over.
        let lowered = sentence.lowercased().replacingOccurrences(of: "’", with: "'")
        let end = sentence.distance(from: sentence.startIndex, to: range.upperBound)
        let chars = Array(lowered)
        guard chars.count == sentence.count, end <= chars.count else { return false }
        // Up to the end of what was matched: a rule's words can come before the name ("shot
        // digitally rather than in IMAX" is one match for IMAX).
        let before = String(chars[..<end])
        let after = String(chars[end...])
        // The clause before it: from the last break.
        var clauseStart = before.startIndex
        for mark in clauseBreaks {
            if let found = before.range(of: mark, options: .backwards), found.upperBound > clauseStart { clauseStart = found.upperBound }
        }
        let clause = String(before[clauseStart...]).replacingOccurrences(of: "not only", with: "")
        if clause.range(of: deniedBefore, options: .regularExpression) != nil { return true }
        if clause.range(of: planBefore, options: .regularExpression) != nil, after.range(of: planKept, options: .regularExpression) == nil {
            return true
        }
        // Said of cameras in general, right before the name: "every digital camera is trying to
        // emulate 35mm film", "anything shot digitally" isn't this film's.
        let start = sentence.distance(from: sentence.startIndex, to: range.lowerBound)
        let lead = String(chars[..<min(start, chars.count)]).suffix(40)
        if lead.range(of: #"\b(?:every|any|all|most|many|other)(?:\s+[a-z\-]+)?\s*$|\b(?:anything|everything|something|nothing|whatever)\s*$"#,
                      options: .regularExpression) != nil { return true }
        // The clause after it: "…cameras were not used".
        var clauseEnd = after.endIndex
        for mark in clauseBreaks {
            if let found = after.range(of: mark), found.lowerBound < clauseEnd { clauseEnd = found.lowerBound }
        }
        return String(after[..<clauseEnd]).range(of: deniedAfter, options: .regularExpression) != nil
    }

    static let clauseBreaks = [",", ";", ":", " — ", " – ", "(", ")", ". ", " but ", " while ", " whereas ", " although ", " though "]
    static let deniedBefore = #"\b(?:not|never|without|instead of|rather than|unlike|as opposed to|considered|contemplated|planned to|plans to|hoped to|would have|could have|had wanted to|originally intended|if|previous(?:ly)?|earlier films?|last film|next film|(?:decided|decision|chose|choosing|opted|argued|ruled) against|(?:initially|originally|at first) (?:wanted|planned|intended|hoped)|tests? of|testing|tested|versus|vs|compared (?:to|with)|lack(?:ed)? of|shortage of|short of|too (?:many|few) [a-z ]{0,40}enough|unable to (?:get|find|source)|couldn't (?:get|find|source)|prefer(?:s|red)?\s+(?!to\b)[^,;]{1,60}?\s+to|(?:better |best )?suited to|inspired by|influenced by|reminiscent of|evocative of|akin to|similar to)\b|n't\b"#

    /// What the film was finished or shown on, said in the clause: not what it was shot on.
    static let finishing = #"\b(?:finish(?:ing|ed)?|film[- ]?out|filmed out|dcp|deliverables?|final outputs?|prints?|printed|restor(?:ation|ed|e)|remaster(?:ed|ing)?|digital intermediate|projected|projection|exhibition|screenings?)\b"#

    /// Part of the film only: "for the flashbacks", "the battle scenes", "some sequences", "the
    /// first IMAX 70 mm film camera shot" (one shot).
    static let partOfFilm = try! NSRegularExpression(
        pattern: #"\b(?:flashbacks?|inserts?|simulated|segments?|portions?|parts? of the (?:film|movie)|(?:small )?bits of the (?:film|movie)|half of the|some of the|a handful of|storylines?|(?:some|certain|several|a few|select(?:ed)?|key|battle|night|underwater|action|aerial|opening|closing|dream|archival|flashback)\s+(?:\w+\s+)?(?:scenes|sequences|shots)|for (?:the |some )?(?:[\w-]+\s+){0,2}(?:scenes|sequences|shots)|(?:camera|effects?|vfx|single|lone|test) shots?|for some (?:[\w-]+\s+){0,2}(?:work|material|footage)|high[- ]speed (?:work|shots?|sequences?|photography|material|footage))\b"#,
        options: [.caseInsensitive])

    /// "…his Super 16mm work on Carol": gear named for someone's work on another film (not this one).
    static func workOnAnother(_ sentence: String, at range: Range<String.Index>, title: String?) -> Bool {
        guard let clause = clause(of: sentence, around: range),
              let work = clause.range(of: #"\bwork (?:on|for)\b"#, options: .regularExpression) else { return false }
        let after = clause[work.upperBound...].trimmingCharacters(in: .whitespaces)
        // "The camera work for the film", "his work on this picture".
        if after.range(of: #"^(?:the|this) (?:film|picture|movie|production|project)\b"#, options: .regularExpression) != nil { return false }
        guard let title, !title.isEmpty else { return true }
        // A title with a colon is often written without its subtitle ("Dune" for "Dune: Part One").
        let short = title.split(separator: ":").first.map(String.init) ?? title
        return !after.hasPrefix(title.lowercased()) && !after.hasPrefix(short.lowercased())
    }

    /// The words are what something was transferred, scanned, printed or blown up onto ("…transferring
    /// images captured in IMAX format onto 35mm colour negative film"): a copy, not how it was shot.
    /// What was transferred ("images captured in IMAX format") still says how it was shot.
    static func transferTarget(_ sentence: String, at range: Range<String.Index>) -> Bool {
        let lead = String(sentence[segmentRange(of: sentence, around: range).lowerBound..<range.lowerBound])
        return lead.range(of: transferredOnto, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The copy's verb, then (in the same clause, no verb of shooting after "to") what it went onto.
    static let transferredOnto = #"\b(?:transferr?(?:ed|ing|s)?|scann?(?:ed|ing)|print(?:ed|ing)|output(?:ted|ting)?|record(?:ed|ing)?\s+(?:out|back)|film(?:ed)?[- ]out|blown\s+up|blow(?:ing)?[- ]up)\b(?:(?!\b(?:we|they|he|she|i|switch\w*|decid\w*|went|go|chose|opted|moved|turned)\b)[^.;,]){0,80}?\b(?:onto|on to|to|into)\s+(?!(?:shoot|shooting|film|filming|use|using|capture|capturing|photograph|go|switch|turn|work|rely)\b)(?:[\w-]+\s+){0,3}$"#

    /// Said of a stated share of the film, in the words' clause: "film about 40 minutes with IMAX
    /// cameras", "15–20% IMAX footage", "for much of the filming". A running time ("the film runs 152
    /// minutes") isn't a share.
    static func saidOfShare(_ sentence: String, at range: Range<String.Index>) -> Bool {
        guard let clause = clause(of: sentence, around: range) else { return false }
        let whole = NSRange(clause.startIndex..., in: clause)
        for match in shareOfFilm.matches(in: clause, range: whole) {
            guard let found = Range(match.range, in: clause) else { continue }
            let before = clause[..<found.lowerBound].suffix(30)
            if before.range(of: #"\b(?:runs?|running(?: time)?(?: of)?|lasts?|length(?: of)?|clocks? in at|duration(?: of)?)\s*$"#,
                            options: .regularExpression) != nil { continue }
            return true
        }
        return false
    }

    static let shareOfFilm = try! NSRegularExpression(
        pattern: #"\b\d{1,3}(?:\s*[–-]\s*\d{1,3})?\s+minutes\s+(?:with\b|(?:were|was)\s+(?:shot|filmed|captured|photographed|produced)\b|(?:were|was)?\s*(?:shot|filmed|captured|photographed)\b|of\s+(?:the\s+(?:final\s+cut|film|movie|picture|running\s+time)|(?:[\w-]+\s+)?footage)\b|in\s+IMAX\b)|\b(?:shoot|shot|film|filmed|capture|captured|photograph|photographed)\s+(?:only\s+|about\s+|approximately\s+|roughly\s+|around\s+|some\s+|nearly\s+|almost\s+|over\s+)?\d{1,3}\s+minutes\b|\b[1-9]\d?(?:\s*[–-]\s*[1-9]\d?)?\s*(?:%|per ?cent)(?=\W)\s*(?:of\s+the\s+(?:film|movie|footage|picture|running time|runtime|shots|scenes)\b|of\s+(?:[\w-]+\s+)?footage\b|(?:[\w-]+\s+)?footage\b)|\b(?:much|most|half|a third|a quarter|two[- ]thirds|three[- ]quarters|a portion|part) of the (?:film(?:ing)?|movie|footage|shoot(?:ing)?|picture|running time|production)\b"#,
        options: [.caseInsensitive])

    /// Said of the whole film in so many words, in the words' clause: "the entire film was shot with
    /// IMAX cameras", "shot entirely on 35mm".
    static func saidOfWholeFilm(_ sentence: String, at range: Range<String.Index>) -> Bool {
        guard let clause = clause(of: sentence, around: range) else { return false }
        return matches(wholeOfFilm, clause)
    }

    static let wholeOfFilm = try! NSRegularExpression(
        pattern: #"\b(?:entirely|completely|wholly|exclusively|in (?:its|their) entirety|from (?:start|beginning) to (?:finish|end)|(?:the )?(?:whole|entire) (?:film|movie|picture|feature|production|shoot)|all of the (?:film|movie|footage|picture)|every (?:frame|shot|scene))\b|\b100\s*(?:%|per ?cent)"#,
        options: [.caseInsensitive])

    /// Whether a quote is still open after `sentence`: “ and ” counted, a lone " turning it.
    static func quoteStaysOpen(_ sentence: String, wasOpen: Bool) -> Bool {
        let opens = sentence.filter { $0 == "“" }.count, closes = sentence.filter { $0 == "”" }.count
        var open = wasOpen
        if opens != closes { open = opens > closes }
        if sentence.filter({ $0 == "\"" }).count % 2 == 1 { open.toggle() }
        return open
    }

    /// Words said while accepting an award ("On accepting his award, he said: 'try shooting…
    /// celluloid'"): advice to others, not how this film was shot.
    static let acceptanceSpeech = try! NSRegularExpression(
        pattern: #"\baccept(?:ed|ing|s)?\s+(?:the|his|her|their|an?|this|that)\s+(?:[\w'’-]+\s+){0,4}?(?:awards?|prizes?|oscars?|baftas?|honou?rs?|trophy|trophies|statuettes?|emmys?|golden globes?)\b|\bacceptance speech\b"#,
        options: [.caseInsensitive])

    /// A plan or intention given up ("Though the original plan had been to shoot on 16mm film, the
    /// feature was ultimately captured digitally"), unless the sentence says it was kept ("and we
    /// did", "as planned").
    static let planBefore = #"\b(?:the |our |my |his |her |their |an? )?(?:original |initial |first |early |earlier )?(?:plan|intention) (?:had been|was|were|is) (?:always |originally |initially |first )?to (?:shoot|film|use|capture|photograph|go with|lens)\b|\bhad (?:originally |initially |first )?(?:planned|intended) (?:on|to) (?:shoot|shooting|film|filming|use|using|capture|capturing|photograph)\b"#
    static let planKept = #"\b(?:and|which|as)\s+(?:that'?s\s+what\s+|so\s+|is\s+what\s+)?(?:we|they|he|she|i|it)\s+did\b|\bas (?:planned|intended)\b|\b(?:stuck|stayed) (?:to|with) (?:it|that|the plan)\b"#

    /// Whether the clause around `range` is about finishing, printing or showing the film.
    /// "Shot on 35mm and finished photochemically" still says what it was shot on.
    static func aboutFinishing(_ sentence: String, at range: Range<String.Index>) -> Bool {
        guard let clause = clause(of: sentence, around: range), clause.range(of: finishing, options: .regularExpression) != nil else { return false }
        return clause.range(of: #"\b(?:shot|shoot|shooting|filmed|filming|captured|photographed|photography|lensed)\b"#,
                            options: .regularExpression) == nil
    }

    // MARK: Said to have been shot with it

    /// Whether the words at `range` are said of part of the film: in their clause (brackets that
    /// don't hold them left out: "black-and-white film (5222) for the flashbacks", but not "anamorphic
    /// lenses (IMAX for the action)"), or in an opening that frames the sentence ("For sequences
    /// meant for 2.39:1, he chose…", "To tell the storylines apart, he also shot…").
    static func saidOfPart(_ sentence: String, at range: Range<String.Index>) -> Bool {
        // Brackets not around the words: blanked (the same length, so positions carry over).
        var chars = Array(sentence)
        for match in brackets.matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) {
            guard let found = Range(match.range, in: sentence), !found.overlaps(range) else { continue }
            let lower = sentence.distance(from: sentence.startIndex, to: found.lowerBound)
            let upper = sentence.distance(from: sentence.startIndex, to: found.upperBound)
            for i in lower..<upper { chars[i] = " " }
        }
        let text = String(chars)
        let lower = text.index(text.startIndex, offsetBy: sentence.distance(from: sentence.startIndex, to: range.lowerBound))
        let at = lower..<text.index(lower, offsetBy: sentence.distance(from: range.lowerBound, to: range.upperBound))
        if let clause = clause(of: text, around: at, breaks: clauseBreaks.filter { $0 != "(" && $0 != ")" }) {
            if matches(partOfFilm, clause) { return true }
            // "…shot the dream sequences in Super 8 format, …, using Bolex cameras": the gear of a
            // clause that only says what with is said of what the clause before it shot.
            if clause.range(of: #"^\W*(?:using|with|employing|via)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
               matches(partOfFilm, String(text[segmentRange(of: text, around: at).lowerBound..<at.lowerBound])) {
                return true
            }
        }
        guard let opening = sentence.range(of: #"^\W*(?:For|In|During|On|With|To)\b[^,]{0,100},"#, options: .regularExpression),
              opening.upperBound <= range.lowerBound else { return false }
        return sentence[opening].range(of: #"\b(?:scenes|sequences|shots|storylines?|flashbacks?|segments?)\b"#,
                                       options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Whether the sentence says this film was shot with what's at `range`: a statement of how it
    /// was captured or what was chosen ("shot on", "photographed with", "chose", "Panavision
    /// supplied", "his main camera") or a spec list ("Cameras | Alexa Mini LF"). Not an opinion
    /// ("for me, that's photochemical film"), a remark on gear in general, a comparison ("better
    /// suited to CinemaScope"), other work ("I shoot a lot of commercials", "In Part One, we shot",
    /// "Chazelle's La La Land, which he shot…") or a look made in the grade ("the Ektachrome LUT").
    /// Only these are Shot on tags; the names are still read for the craft notes and search.
    static func saysCaptured(_ sentence: String, at range: Range<String.Index>, title: String?, otherTitles: [String],
                             people: [String]) -> Bool {
        reading(sentence, at: range, title: title, otherTitles: otherTitles, people: people).captured
    }

    /// Whether the words at `range` are about this film (not other work, another film or gear in
    /// general), and whether they're said to have been shot with (see `saysCaptured`).
    static func reading(_ sentence: String, at range: Range<String.Index>, title: String?, otherTitles: [String],
                        people: [String]) -> (aboutThisFilm: Bool, captured: Bool) {
        if isSpecList(sentence) { return (true, true) }
        let whole = segmentRange(of: sentence, around: range)
        let part = String(sentence[whole])
        // Other work and remarks in general: before the words in their part of the sentence, or in
        // their own clause ("Although I shoot a lot of commercials using digital cameras", "he
        // shot several of his films with IMAX cameras"), not a clause after them ("We shot on
        // 5219, which tends to hold the highlights").
        let lead = String(sentence[whole.lowerBound..<range.lowerBound]) + " " + (clause(of: sentence, around: range) ?? "")
        // A look made in the grade, right by the words: "the Ektachrome LUT", "the three-strip Technicolor look".
        let near = String(sentence[sentence.index(range.lowerBound, offsetBy: -min(12, sentence.distance(from: sentence.startIndex, to: range.lowerBound)))
                                   ..< sentence.index(range.upperBound, offsetBy: min(12, sentence.distance(from: range.upperBound, to: sentence.endIndex)))])
        let about = !matches(otherWork, lead) && !namesAnotherFilm(part, title: title, otherTitles: otherTitles, people: people)
            && !namesAnotherPart(scope(of: sentence, around: range), title: title, otherTitles: otherTitles)
            && !saidOfAnotherTitle(String(sentence[whole.lowerBound..<range.upperBound]), title: title)
        // Said while accepting an award: advice to others, not how this film was shot.
        let speech = matches(acceptanceSpeech, sentence)
        return (about, about && !speech && matches(captureCue, part) && !matches(lookMade, near))
    }

    /// The part of the sentence the words at `range` are in, split only where the sentence turns
    /// ("; ", " but ", " while ", " although "…, and after an opening "Although…,"): commas and dashes
    /// inside one statement don't split it ("We shot the film with Mitchell cameras, which were
    /// modified to accept anamorphic lenses").
    static func segment(of sentence: String, around range: Range<String.Index>) -> String {
        String(sentence[segmentRange(of: sentence, around: range)])
    }

    static func segmentRange(of sentence: String, around range: Range<String.Index>) -> Range<String.Index> {
        var lower = sentence.startIndex, upper = sentence.endIndex
        for mark in turns {
            if let found = sentence.range(of: mark, options: [.caseInsensitive, .backwards], range: sentence.startIndex..<range.lowerBound),
               found.upperBound > lower { lower = found.upperBound }
            if let found = sentence.range(of: mark, options: .caseInsensitive, range: range.upperBound..<sentence.endIndex),
               found.lowerBound < upper { upper = found.lowerBound }
        }
        if let opening = sentence.range(of: #"^\W*(?:although|though|even though|while|whereas)\b[^,]*,"#,
                                        options: [.regularExpression, .caseInsensitive]) {
            if opening.upperBound <= range.lowerBound {
                if opening.upperBound > lower { lower = opening.upperBound }
            } else if opening.upperBound < upper {
                upper = opening.upperBound
            }
        }
        return lower..<upper
    }

    static let brackets = try! NSRegularExpression(pattern: #"\([^()]*\)"#)
    static let turns = ["; ", " but ", " while ", " whereas ", " although ", " though ", ". "]

    /// The clause the words are in, with an opening that frames the sentence ("In Part One, we shot…").
    static func scope(of sentence: String, around range: Range<String.Index>) -> String {
        var text = ""
        if let opening = sentence.range(of: #"^\W*(?:In|On|For|With|During|Unlike|Like|After|Before|Since|As)\b[^,]{0,60},"#,
                                        options: .regularExpression), opening.upperBound <= range.lowerBound {
            text = String(sentence[opening]) + " "
        }
        let lowered = clause(of: sentence, around: range) ?? ""
        // The clause in its own case (the same positions as the lowercased one).
        if let found = sentence.range(of: lowered, options: .caseInsensitive) { return text + String(sentence[found]) }
        return text + lowered
    }

    /// A spec list, as magazines print them under an article: "Cameras | Arri Alexa Mini LF",
    /// "Lenses: Cooke Anamorphic/i", "2.39:1 Anamorphic and Spherical 35mm Kodak Vision3 5219…".
    static func isSpecList(_ sentence: String) -> Bool {
        // "Cameras | Arri Alexa Mini LF Lenses | …": a label and its value, twice or more.
        if sentence.components(separatedBy: " | ").count > 2 { return true }
        if sentence.range(of: #"^(?:Cameras?|Lenses|Lens|Format|Film stocks?|Stocks?|Capture|Aspect ratio)\s*:"#, options: .regularExpression) != nil {
            return true
        }
        guard sentence.range(of: #"^[1-2]\.\d{2}\s?:\s?1\b"#, options: .regularExpression) != nil else { return false }
        let words = sentence.split(separator: " ")
        let named = words.filter { $0.first.map { $0.isUppercase || $0.isNumber } ?? false }
        return !words.isEmpty && Double(named.count) / Double(words.count) >= 0.6
    }

    /// Whether a gauge ("35mm", "Super 16") is film here: said as film ("35mm film", "shot on 35mm",
    /// "3-perf 35mm", "Kodak Vision3 35 mm", "Super 35"), not a lens ("a 28mm and a 35mm", "16mm T2")
    /// or a sensor ("Super 35 sensors", "cropped to Super 16mm").
    static func filmGauge(_ sentence: String, at range: Range<String.Index>) -> Bool {
        let before = String(sentence[..<range.lowerBound].suffix(50)).lowercased()
        let after = String(sentence[range.upperBound...].prefix(50)).lowercased()
        if after.range(of: #"^\W*(?:[\w-]+\s+)?(?:sensors?|mode|crop|equivalent)\b"#, options: .regularExpression) != nil
            || before.range(of: #"\b(?:sensor|sensors|crop(?:ped|ping)?(?:\s+(?:to|at|in))?)\W*$"#, options: .regularExpression) != nil {
            return false
        }
        // A lens made to cover a gauge: "a Canon 8-64mm Super 16 zoom lens".
        if after.range(of: #"^\s+(?:zoom\s+)?(?:zooms?|lens|lenses|primes?|glass|optics)\b"#, options: .regularExpression) != nil {
            return false
        }
        if sentence[range].lowercased().hasPrefix("super") { return true }
        if after.range(of: #"^\W*(?:[\w-]+\s+){0,2}?(?:film|films|filmmaking|stocks?|negative|celluloid|format|cameras?|footage)\b"#,
                       options: .regularExpression) != nil { return true }
        return before.range(of: #"\b(?:shot|shoot|shooting|filmed|filming|photographed|captured|capturing|recorded|recording|lensed)\s+(?:[\w’'-]+\s+){0,3}?(?:on|in)\s+$|\b(?:\d{1,2}-perf(?:oration)?|spherical|anamorphic|imax|kodak|eastman|vision\s?3|fuji\w*|panavision|system|standard)\s+$"#,
                            options: .regularExpression) != nil
    }

    /// Another film named where the words are: a film of its collection ("Alien" for Alien:
    /// Romulus), a title in quotes (“Jurassic World Rebirth”), or someone else's film by their name
    /// ("Chazelle’s La La Land").
    static func namesAnotherFilm(_ part: String, title: String?, otherTitles: [String], people: [String]) -> Bool {
        let own = (title ?? "").lowercased()
        let short = own.split(separator: ":").first.map(String.init) ?? own
        func isOwn(_ text: String) -> Bool {
            let named = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            // "Dune: Part One" for Dune, unless that's another film of the collection.
            let subtitled = named.hasPrefix(own + ":") && !otherTitles.contains { $0.lowercased() == named }
            return !own.isEmpty && (named == own || named == short || subtitled)
        }
        let range = NSRange(part.startIndex..., in: part)
        // “Alien”, “Jurassic World Rebirth,”: a title (most words capitalised), not a quote, and not a
        // nickname between names (Emmanuel “Chivo” Lubezki).
        for match in quotedTitle.matches(in: part, range: range) {
            guard let inner = Range(match.range(at: 1), in: part), let whole = Range(match.range, in: part) else { continue }
            let named = part[inner].trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
            let words = named.split(separator: " ")
            guard let first = words.first?.first, first.isUppercase,
                  words.allSatisfy({ $0.count < 4 || ($0.first?.isUppercase ?? false) || ($0.first?.isNumber ?? false) }) else { continue }
            let previous = part[..<whole.lowerBound].trimmingCharacters(in: .whitespaces).split(separator: " ").last
            let next = part[whole.upperBound...].trimmingCharacters(in: .whitespaces).split(separator: " ").first
            let nickname = (previous?.first?.isUppercase ?? false) && (next?.first?.isUppercase ?? false)
            // "Alien" in quotes while reading Alien: Romulus is the first film, when it's one of the collection.
            let collection = otherTitles.contains { $0.lowercased() == named.lowercased() }
            if !nickname, !isOwn(named) || collection { return true }
        }
        // The collection's other films, where this film's own title isn't what's written.
        let owns = own.isEmpty ? [] : occurrences(of: title ?? "", in: part, options: .caseInsensitive)
        for other in otherTitles where other.count >= 4 && other.lowercased() != own {
            for found in occurrences(of: other, in: part) where !owns.contains(where: { $0.overlaps(found) }) {
                let edgeBefore = found.lowerBound == part.startIndex || !(part[part.index(before: found.lowerBound)].isLetter)
                let edgeAfter = found.upperBound == part.endIndex || !(part[found.upperBound].isLetter || part[found.upperBound].isNumber)
                if edgeBefore && edgeAfter { return true }
            }
        }
        // "Chazelle’s La La Land": someone's film who isn't this film's director or cinematographer
        // (not a maker's gear, "Arri’s Alexa", nor the author of what this film is).
        let tokens = Set(people.flatMap { $0.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init) })
        for match in possessiveName.matches(in: part, range: range) {
            guard let who = Range(match.range(at: 1), in: part), let what = Range(match.range(at: 2), in: part) else { continue }
            let name = part[who].lowercased(), named = String(part[what])
            if tokens.contains(name) || companies.contains(name) || companies.contains(named.lowercased().split(separator: " ").first.map(String.init) ?? "") {
                continue
            }
            if gearWords.contains(where: { named.lowercased().hasPrefix($0) }) { continue }
            // "London's Shepperton Studios", "Budapest's Origo Studios": a place.
            if let last = named.split(separator: " ").last?.lowercased(), placeWords.contains(last) { continue }
            if !own.isEmpty, own.hasPrefix(named.lowercased()) || isOwn(named) { continue }
            return true
        }
        return false
    }

    /// The words are in what's said of another film, compared with this one: "a visual balance between
    /// Alien, which was shot using [anamorphic lenses]…", "unlike Prometheus, which was filmed in [3D]".
    /// `before`: the sentence up to the end of the words (a rule's words can hold the verb: "shot on film").
    static func saidOfAnotherTitle(_ before: String, title: String?) -> Bool {
        let range = NSRange(before.startIndex..., in: before)
        guard let match = whichWasShot.firstMatch(in: before, range: range),
              let name = Range(match.range(at: 1), in: before) else { return false }
        // Its own title is this film; anything else (the first film, "Alien" while reading Alien: Romulus) isn't.
        return before[name].lowercased() != (title ?? "").lowercased()
    }

    /// "between Alien, which was shot using": a title after a comparison, and its own "which was shot"
    /// clause running up to the words (no comma between).
    static let whichWasShot = try! NSRegularExpression(
        pattern: #"\b(?i:between|like|unlike|than|versus|vs\.?|both)\s+([A-Z][\w'’:.-]*(?:\s+(?:[A-Z0-9][\w'’:.-]*|of|the|and|a|in))*?),\s+which\s+(?:was|were|had been|is|are)\s+(?:\w+\s+){0,2}?(?:shot|filmed|photographed|lensed)\b[^,;]*$"#)

    /// Where `text` is written in `part`.
    static func occurrences(of text: String, in part: String, options: String.CompareOptions = []) -> [Range<String.Index>] {
        guard !text.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var from = part.startIndex
        while from < part.endIndex, let next = part.range(of: text, options: options, range: from..<part.endIndex) {
            found.append(next)
            from = next.upperBound
        }
        return found
    }

    /// "In Part One, we shot…" while reading Part Two: another part of the series.
    /// Another part counts when this film is a part with another number, or that part is a film of
    /// its collection ("Part Two" while reading Dune): "Part One" for Dune is Dune itself.
    static func namesAnotherPart(_ scope: String, title: String?, otherTitles: [String] = []) -> Bool {
        let own = (title ?? "").lowercased()
        let ownPart = own.range(of: #"\bpart (?:one|two|three|four|i{1,3}|iv|[1-4])\b"#, options: .regularExpression) != nil
        let range = NSRange(scope.startIndex..., in: scope)
        for match in partName.matches(in: scope, range: range) {
            guard let found = Range(match.range, in: scope) else { continue }
            let part = scope[found].lowercased()
            if own.contains(part) { continue }
            if ownPart || otherTitles.contains(where: { $0.lowercased().contains(part) }) { return true }
        }
        return false
    }

    /// Saying it was shot, chosen or used: the verbs, a camera's role, a camera package, "the lens
    /// was usually a…".
    static let captureCue = try! NSRegularExpression(
        pattern: #"\b(?:shot|shoot|shoots|shooting|filmed|filming|film (?:in|on|with)|photographed|photographing|photography (?:was|used|on|with|in|began|took place)|(?:was|were) made (?:on|with)|captured|capturing|capture|lensed|recorded|recording|rolled|rolling|used|using|uses|employed|features|employing|chose|chosen|choose|chooses|choosing|selected|opted for|opt for|opting for|went (?:with|for)|go with|settled on|relied on|turned to|turn (?:again )?to|carried|paired|pairing|fitted|outfitted|equipped|supplied|provided|secured|rented|deployed|operating|operated|handholding|pushed|rated at|exposed|made us|built us|(?:main|primary|production|principal|(?-i:[AB])) cameras?|camera package|workhorse|camera of choice|(?:the|our|his|her|their) (?:lens|lenses|camera|cameras|stock|stocks|format) (?:was|were))\b"#,
        options: [.caseInsensitive])
    /// Other work, gear in general or praise: commercials, a TV series, "his films", "I had
    /// shot…", "in general", "you have to", "especially when", "a beautifully shot film on film".
    static let otherWork = try! NSRegularExpression(
        pattern: #"\b(?:nominated films|(?:\w+\s+)?out of (?:the )?(?:\w+\s+){0,2}(?:films|movies|features|nominees)|commercials?|music videos?|adverts?|(?:TV|television) (?:series|shows?)|(?:his|her|their|my|our) (?:other |earlier |previous |next |later |last )?(?:films|movies|features|projects)|several of (?:his|her|their|my|our)|had (?:previously |already |also |once )?(?:shot|filmed|photographed)|as a (?:kid|child|boy|girl|teen|teenager|student)|when (?:i|he|she|we) (?:was|were) (?:a )?(?:kid|child|young|little|boy|girl|teen|teenager|student)|(?:i|he|she|we) grew up|(?:in|on|for) the (?:first|original|previous|last|earlier) (?:film|movie|one|instal?lment|chapter)|in general|generally speaking|i (?:love|adore|like|prefer)|in my opinion|(?:i|we) (?:think|believe|feel)|you (?:have to|need to|tend to|necessarily|can|could|would|will|get)|you['’]ll|tends? to|especially when|talked about|spoke about|discussed|what kind of|which cameras|whenever|every film|any film|most films|all films|(?:beautifully|gorgeously|stunningly|exquisitely|lovingly|brilliantly|wonderfully|handsomely|lushly|superbly|magnificently|expertly|impeccably) (?:shot|filmed|photographed|lensed))\b"#,
        options: [.caseInsensitive])
    /// A look made in the grade or copied, not how it was shot: "the Ektachrome LUT", "emulate
    /// 35mm film", "the three-strip Technicolor look".
    static let lookMade = try! NSRegularExpression(
        pattern: #"\b(?:LUTs?|emulat\w*|mimic\w*|replicat\w*|(?:film|filmic|celluloid|Technicolor|vintage|analogue|analog|VHS) look|look of (?:film|celluloid|\d{2}\s?mm))\b"#,
        options: [.caseInsensitive])
    /// A title in double quotes: “Alien”, "Gladiator II".
    static let quotedTitle = try! NSRegularExpression(pattern: #"[“"]([^”"]{1,60})[”"]"#)
    /// Someone's film by their name: "Chazelle’s La La Land".
    static let possessiveName = try! NSRegularExpression(pattern: #"\b([A-Z][a-z\-]+)['’]s ([A-Z][a-z][\w\-]*(?: [A-Z][\w\-]*)*)"#)
    /// The last word of a place's name after a possessive ("London's Shepperton Studios").
    static let placeWords: Set<String> = ["studios", "studio", "stages", "stage", "lot", "backlot", "desert", "island", "islands",
                                          "mountains", "forest", "street", "avenue", "park", "coast", "beach", "river", "lake", "house",
                                          "hotel", "palace", "castle", "museum", "airport", "station", "cathedral", "church", "square",
                                          "bridge", "centre", "center", "hall", "theatre", "theater", "valley", "canyon", "harbour", "harbor"]
    /// A part of a series: "Part One", "Part II".
    static let partName = try! NSRegularExpression(pattern: #"\bPart (?:One|Two|Three|Four|I{1,3}|IV|[1-4])\b"#)
    /// Gear and makers named after a possessive ("Panavision’s Dan Sasaki" is a person, but "Kodak’s
    /// Vision3", "Arri’s Alexa XT" are gear).
    static let gearWords = ["alexa", "vision", "panavision", "panaflex", "primo", "imax", "kodak", "eastman", "double-x", "cooke", "zeiss",
                            "master", "ultra", "super", "signature", "venice", "red ", "steadicam", "technocrane", "arri", "sony", "canon",
                            "leica", "hawk", "atlas", "fuji", "ektachrome", "millennium", "dxl", "anamorphic", "spherical"]

    /// The clause the words at `range` are in, lowercased: from the break before them to the one
    /// after ("…200T, along with some Double-X [for simulated television footage…]").
    static func clause(of sentence: String, around range: Range<String.Index>, breaks: [String] = clauseBreaks) -> String? {
        let lowered = sentence.lowercased()
        let end = sentence.distance(from: sentence.startIndex, to: range.upperBound)
        let start = sentence.distance(from: sentence.startIndex, to: range.lowerBound)
        let chars = Array(lowered)
        guard chars.count == sentence.count, end <= chars.count else { return nil }
        let before = String(chars[..<start]), after = String(chars[end...])
        var clauseStart = before.startIndex
        for mark in breaks {
            if let found = before.range(of: mark, options: .backwards), found.upperBound > clauseStart { clauseStart = found.upperBound }
        }
        var clauseEnd = after.endIndex
        for mark in breaks {
            if let found = after.range(of: mark), found.lowerBound < clauseEnd { clauseEnd = found.lowerBound }
        }
        return String(before[clauseStart...]) + String(chars[start..<end]) + String(after[..<clauseEnd])
    }

    /// Whether a sentence is about another film: one years apart from this one ("in 1993"), or one
    /// made by someone who didn't make this ("Christopher Nolan's Oppenheimer"). `people` are this
    /// film's cinematographers and directors, as written.
    public static func aboutOtherFilm(_ sentence: String, year: Int?, people: [String], title: String? = nil) -> Bool {
        let range = NSRange(sentence.startIndex..., in: sentence)
        if let year {
            for match in yearPattern.matches(in: sentence, range: range) {
                guard let found = Range(match.range(at: 1), in: sentence), let said = Int(sentence[found]), said < year - 3 else { continue }
                // An earlier year is the cinematographer's or director's earlier work, unless it
                // dates something about this film: "the first 65 mm feature since Far and Away
                // (1992)", "filming began in 2002", "lenses from 1965". (A later year is often an
                // interview looking back, or a restoration, which the finishing rule handles.)
                let before = sentence[..<found.lowerBound].suffix(45).lowercased()
                if before.range(of: #"\b(?:since|from|began|begun|started|starting|beginning|filming|shooting|production|photography|vintage|dating|built|made in|manufactured)\b"#,
                                options: .regularExpression) != nil { continue }
                return true
            }
        }
        // "Christopher Nolan's Oppenheimer": a person's film, by its title (not "Frank Herbert's
        // Dune" when reading Dune: the author of what this film is).
        let own = (title ?? "").lowercased()
        for match in possessiveTitle.matches(in: sentence, range: range) {
            guard let found = Range(match.range(at: 1), in: sentence), let named = Range(match.range(at: 2), in: sentence) else { continue }
            let surname = sentence[found].lowercased()
            if companies.contains(surname) { continue }
            if !own.isEmpty, own.hasPrefix(sentence[named].lowercased()) { continue }
            let known = people.contains { person in
                person.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).contains { $0 == surname }
            }
            if !known { return true }
        }
        return false
    }

    /// A year, not a resolution or a measurement ("2048 x 858", "1920p").
    static let yearPattern = try! NSRegularExpression(pattern: #"(?<![x×\d.:])\b(1[89]\d{2}|20\d{2})\b(?!\s*[x×]|p\b|\s*(?:mm|fps|k\b|lines|pixels))"#)
    /// Makers whose possessive names their gear, not a film ("Eastman Kodak's Vision3").
    static let companies: Set<String> = ["kodak", "panavision", "zeiss", "cooke", "sony", "canon", "fujifilm", "fuji", "technicolor",
                                         "angenieux", "angénieux", "leica", "arri", "netflix", "warner", "universal", "paramount",
                                         "disney", "pictures", "studios", "films", "entertainment", "imax", "dolby", "blackmagic"]
    /// A first and last name, possessive, then a capitalised word: "Christopher Nolan's Oppenheimer".
    static let possessiveTitle = try! NSRegularExpression(pattern: #"\b[A-Z][a-z]+(?: [A-Z][a-z]+)? ([A-Z][a-z\-]+)['’]s ([A-Z][\w\-]+)"#)
    /// "…was not used", "…so Nolan could test whether…" (a test, not the film).
    static let deniedAfter = #"\b(?:was|were|is|are|be)\s*(?:not|n't|never)\b|\bwasn't\b|\bweren't\b|\b(?:to|could|would|so as to) test\b|\bas a test\b"#

    /// The words matched, tidied: single spaces, "35mm" and "35-millimetre" as "35 mm", no
    /// trailing "lenses" or "cameras" (the heading says what they are).
    static func display(_ text: String) -> String {
        var name = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        name = name.replacingOccurrences(of: #"(\d)\s?-?\s?(?:mm|millimetre|millimeter)\b"#, with: "$1 mm",
                                         options: [.regularExpression, .caseInsensitive])
        name = name.replacingOccurrences(of: #"\s+(?:lenses|lens|cameras|camera|film stock|stock)$"#, with: "",
                                         options: [.regularExpression, .caseInsensitive])
        if let first = name.first, first.isLowercase { name = first.uppercased() + name.dropFirst() }
        return name
    }

    /// Words one of the rules needs, to skip most sentences without trying them all.
    static let triggers = ["camera", "lens", "mm", "millimet", "film", "shot", "alexa", "arri", "panavision", "panaflex",
                           "kodak", "eastman", "fuji", "imax", "red ", "sony", "zeiss", "cooke", "stock", "digital",
                           ":1", "anamorphic", "aaton", "bolex", "canon", "black-and-white", "black and white",
                           "vistavision", "technicolor", "techniscope", "cinemascope", "super", "leica", "hawk",
                           "angénieux", "angenieux", "blackmagic", "iphone", "phantom", "varicam", "viper", "kowa",
                           "lomo", "baltar", "todd-ao", "moviecam", "mitchell", "frames per second", "fps", "celluloid", "photochemical",
                           "academy ratio", "perf", "open gate", "15/70", "summilux", "atlas", "ironglass", "lensbaby",
                           "diopter", "vantage", "gopro", "dji", "millennium", "venice", "cinealta", "light", "hmi", "kino", "skypanel",
                           "astera", "creamsource", "aputure", "litepanel", "litemat", "litegear", "quasar", "dino",
                           "brute", "wendy", "mole", "softsun", "tungsten", "sodium", "fluorescent", "led ", "stagecraft",
                           "candle", "practical", "hour", "negative fill", "day for night", "day-for-night", "projection",
                           // Grip and movement
                           "steadicam", "technocrane", "crane", " arm", "ronin", "movi", "mōvi", "gimbal", "doll", "drone",
                           "snorri", "easyrig", "trinity", "cable", "spidercam", "motion control", "motion-control",
                           "tripod", "handheld", "hand-held", "libra", "scorpio", "oculus", "milo", "cinebot", "chapman", "fisher",
                           // Filters and diffusion
                           "mist", "glimmer", "satin", "black magic", "diffusion", " fx", "frost", "fog", " con",
                           "suede", "schneider", "tiffen", "stocking", "net ", "nets ", "filter", "polari", "neutral density",
                           // Lab, recording and finish
                           "intermediate", "bleach", "silver retention", "enr", "push", "process", "emulation", "lut",
                           "film-out", "film out", "printed", "fotokem", "company 3", "efilm", "deluxe", "picture shop",
                           "light iron", "cinelab", "raw", "prores", "x-ocn", "k "]

    static let shooting = ["shot", "film on", "filmed", "photographed", "photography", "cinematograph", "camera", "lens",
                           "stock", "footage", "shooting", "captured", "aspect ratio", "format", "negative", "frame rate",
                           "frames per second"]
    static let release = ["release", "version", "screened", "projected", "re-release", "distributed", "prints", "home media",
                          "blu-ray", "dvd", "theaters", "theatres", "converted", "conversion", "remaster", "restor"]

    static func strongShooting(_ lowered: String) -> Bool {
        ["shot", "filmed", "photographed", "camera", "lens", "cinematograph", "shooting", "stock"].contains { lowered.contains($0) }
    }

    static let rules: [Rule] = [
        // Cameras
        Rule(.camera, #"\bARRI\s+Alexa(?:\s+(?:Mini\s+LF|Mini|LF|65|XT(?:\s+Plus)?|SXT|35|Studio|Plus|M))?\b"#),
        Rule(.camera, #"\b(?<!ARRI )Alexa\s+(?:Mini\s+LF|Mini|LF|65|XT(?:\s+Plus)?|SXT|35|Studio)\b"#),
        Rule(.camera, #"\b(?:ARRI\s+)?Arricam(?:\s+(?:ST|LT|Studio|Lite))?\b"#),
        Rule(.camera, #"\b(?:ARRI\s+)?Arriflex(?:\s+(?:\d{2,3}(?:\s?(?:ES|BL|SR|Xtreme|Xtr))?|SR\s?(?:II|III|3)?|BL(?:\s?[1-4]|\s?IV)?|D-21))?\b"#),
        Rule(.camera, #"\bARRI\s+(?:\d{3}(?:\s?(?:ES|Xtreme))?|D-21|416|235|435|535B?)\b"#),
        Rule(.camera, #"\bPanaflex(?:\s+(?:Millennium(?:\s+XL2?)?|Platinum|Gold(?:\s+II)?|Lightweight(?:\s+II)?|X))?\b"#),
        Rule(.camera, #"\bPanavision\s+(?:Millennium(?:\s+(?:XL2?|DXL2?))?|Genesis|DXL2?|System\s+65|Panastar(?:\s+II)?|XL2?|Platinum|Gold)\b"#),
        Rule(.camera, #"\b(?<!Panavision )Millennium\s+(?:DXL2?|XL2?)\b"#),
        Rule(.camera, #"\bRED\s+(?:One(?:\s+MX)?|Epic(?:\s+(?:Dragon|W|X|MX))?|Dragon|Monstro|Helium|Gemini|Weapon(?:\s+(?:Dragon|Helium|Monstro|8K))?|V-Raptor|Raptor|Komodo|Ranger|Scarlet(?:-X)?)\b"#,
             caseSensitive: true),
        Rule(.camera, #"\bSony\s+(?:Venice(?:\s+2)?|F65|F55|F35|F23|CineAlta(?:\s+\w+)?|HDC-F950|HDW-F900|FX[369]|a7S\s?(?:III|II)?|DSR-PD150|PD-?150|VX1000|Burano)\b"#),
        Rule(.camera, #"\b(?<!Sony )(?:Venice\s+2\b|F65\b|CineAlta)"#, caseSensitive: true),
        // Wikipedia usually writes "Red": the models are unambiguous, or "Red camera(s)".
        Rule(.camera, #"\bRed\s+(?:Epic(?:\s+(?:Dragon|W|X|MX))?|Dragon|Monstro|Helium|Gemini|Weapon(?:\s+(?:Dragon|Helium|Monstro|8K))?|V-Raptor|Raptor|Komodo|Scarlet(?:-X)?|One\s+(?:MX\s+)?cameras?|Digital\s+Cinema\s+cameras?|cameras?)\b"#,
             caseSensitive: true),
        Rule(.camera, #"\bPanavision\s+(?:film\s+|35\s?mm\s+|65\s?mm\s+)?cameras?\b"#),
        Rule(.camera, #"\bIMAX\s+(?:MSM\s+9802|MKIV|Mark\s+(?:IV|II|III)|65\s?mm\s+(?:film\s+)?cameras?|film\s+cameras?|digital\s+cameras?|cameras?)\b"#),
        Rule(.camera, #"\bAaton\s+(?:XTR(?:\s+Prod)?|Penelope|A-Minima|LTR|XTera|Delta)\b"#),
        Rule(.camera, #"\bBolex(?:\s+H16)?\b"#),
        // A Moviecam camera: a model ("Moviecam Compact"), "Moviecam cameras" or "a/the Moviecam".
        // Alone it's the lenses ("Arri Rental Moviecam (Olympus OM)", "Fraser used Moviecam, which was
        // sharp in texture", "the Moviecams… their ability to resolve").
        Rule(.camera, #"(?<!by )(?<!Rental )\bMoviecam(?:\s+(?:Compacts?|SL|Super\s+America)\b|(?=\s+cameras?\b)|(?<=\b(?:a|an|the|our|his|her|their|two|three)\sMoviecam)\b(?!\s+(?:lenses|lens|primes|optics|glass|\()))"#),
        Rule(.camera, #"\bMitchell\s+(?:BNCR?|NC|Mark\s+II|65|camera)\b"#),
        Rule(.camera, #"\bBlackmagic\s+(?:URSA(?:\s+Mini)?(?:\s+Pro)?(?:\s+\d{1,2}(?:\.\d)?K)?|Pocket\s+Cinema\s+Camera(?:\s+\dK)?|Cinema\s+Camera(?:\s+\dK)?)"#),
        Rule(.camera, #"\bCanon\s+(?:EOS\s+)?(?:C\d{2,3}(?:\s+Mark\s+(?:II|III))?|5D(?:\s+Mark\s+(?:II|III|IV))?|7D|XL[12]s?|R5\s?C?)\b"#),
        Rule(.camera, #"\bPhantom\s+(?:Flex(?:\s?4K)?|HD(?:\s+Gold)?|v\d{3,4}|high-speed\s+cameras?)\b"#),
        Rule(.camera, #"\biPhone\s+(?:\d{1,2}|X[SR]?)(?:\s+Pro(?:\s+Max)?|\s+Plus)?\b"#),
        Rule(.camera, #"\bGoPro(?:\s+Hero\s?\d{0,2})?\b"#),
        Rule(.camera, #"\bPanasonic\s+(?:VariCam(?:\s+(?:LT|35|Pure))?|AG-DVX100\w?|AG-HVX200|GH[1-6]|Lumix\s+\w+|AJ-HDC27\w*)\b"#),
        Rule(.camera, #"\b(?<!Panasonic )VariCam(?:\s+(?:LT|35|Pure))?\b"#),
        Rule(.camera, #"\bThomson\s+Viper(?:\s+FilmStream)?\b|\bViper\s+FilmStream\b"#),
        Rule(.camera, #"\bDJI\s+(?:Ronin\s+4D|Inspire\s?\d?)\b"#),
        Rule(.camera, #"\bTechnicolor\s+(?:three-strip\s+)?cameras?\b"#),
        Rule(.camera, #"\bVistaVision\s+cameras?\b"#),

        // Lenses
        Rule(.lens, #"\bPanavision\s+(?:C-Series|E-Series|G-Series|T-Series|B-Series|H-Series|Primo(?:\s+(?:70|V|Artiste))?|Ultra\s+Speeds?|Super\s+Speeds?|Sphero(?:\s+65)?|anamorphic)(?:\s+anamorphic)?(?:\s+(?:lenses|lens|primes))?"#),
        Rule(.lens, #"\bPanavision\s+(?:spherical\s+|anamorphic\s+|prime\s+|zoom\s+)?(?:lenses|lens|primes|optics)\b"#),
        Rule(.lens, #"\b(?<!Panavision )(?:C|E|G|T)-Series\s+(?:anamorphic\s+)?(?:lenses|lens|primes)\b"#),
        Rule(.lens, #"\b(?<!Panavision )Primo(?:\s+(?:70|V|Artiste))?\s+(?:prime\s+)?(?:lenses|lens|primes)\b"#),
        Rule(.lens, #"\bCooke\s+(?:S[2-8](?:/i)?|Panchro(?:/i)?(?:\s+Classic)?|Speed\s+Panchro|Anamorphic(?:/i)?(?:\s+(?:SF|FF))?|Xtal\s+Express|5/i|miniS4/i|Varotal)(?:\s+(?:lenses|lens|primes))?"#),
        Rule(.lens, #"\bCooke\s+(?:lenses|lens|primes)\b"#),
        Rule(.lens, #"\bZeiss\s+(?:Master\s+(?:Primes?|Anamorphics?)|Ultra\s+Primes?|Super\s+Speeds?|Standard\s+Speeds?|Supreme\s+Primes?(?:\s+Radiance)?|Planar(?:\s+50\s?mm)?(?:\s+f/0\.7)?|CP\.?[23]|Distagon|Jena|lenses)"#),
        Rule(.lens, #"\b(?<!Zeiss )(?<!ARRI )(?:Master\s+Primes|Ultra\s+Primes|Master\s+Anamorphics?|Signature\s+Primes|Supreme\s+Primes)\b"#),
        Rule(.lens, #"\bARRI\s+(?:Signature\s+Primes|Master\s+Primes|Ultra\s+Primes|Master\s+Anamorphics?|DNA(?:\s+LF)?\s+lenses|Rental\s+DNA)\b"#),
        Rule(.lens, #"\bLeica\s+(?:Summilux-C|Summicron-C|Thalia|R\b)(?:\s+(?:lenses|primes))?|\b(?<!Leica )Summilux-C\b"#),
        Rule(.lens, #"\bHawk\s+(?:V-Lite|V-Plus|C-Series|65|Vintage\s?'?74|anamorphic)(?:\s+anamorphic)?(?:\s+(?:lenses|lens))?"#),
        Rule(.lens, #"\bKowa\s+(?:Cine\s+)?(?:Prominar\s+)?(?:anamorphic\s+)?(?:lenses|lens)\b"#),
        Rule(.lens, #"\bLomo\s+(?:Roundfront\s+|Squarefront\s+)?(?:anamorphic\s+)?(?:lenses|lens)\b"#),
        Rule(.lens, #"\bCanon\s+K-?35s?\b|\bK-?35\s+(?:lenses|primes)\b"#),
        Rule(.lens, #"\bAtlas\s+Orion\b"#),
        Rule(.lens, #"\bAng[ée]nieux\s+(?:Optimo(?:\s+[\w-]+)?|zoom(?:\s+lens)?|lenses|25-250)"#),
        Rule(.lens, #"\bDNA\s+lenses\b"#),
        Rule(.lens, #"\b(?:Bausch\s*(?:&|and)\s*Lomb\s+)?(?:Super\s+)?Baltar(?:\s+(?:lenses|lens))?"#),
        Rule(.lens, #"\bTodd-AO\s+(?:lenses|lens)\b"#),
        Rule(.lens, #"\bPetzval\s+(?:lenses|lens)\b"#),
        Rule(.lens, #"\bVantage\s+(?:One|Hawk)\b"#),
        Rule(.lens, #"\bIronglass\b"#),
        Rule(.lens, #"\bLensbaby\b"#),
        Rule(.lens, #"\banamorphic\s+(?:lenses|lens|glass|optics)\b"#, name: "Anamorphic"),
        // "shot primarily in the anamorphic format", "anamorphic 35mm", "shot in anamorphic".
        Rule(.lens, #"\banamorphic\s+(?:format|35\s?mm|widescreen|process|photography)\b|\b(?:shot|filmed|photographed|film|shoot|shooting)\s+(?:\w+\s+){0,2}in\s+anamorphic\b(?!\s+(?:lenses|lens|glass|optics|format))"#,
             name: "Anamorphic"),
        Rule(.lens, #"\bspherical\s+(?:lenses|lens)\b"#, name: "Spherical"),
        Rule(.lens, #"\bvintage\s+(?:[\w-]+\s+){0,2}(?:lenses|lens)\b"#),
        Rule(.lens, #"\b(?:wide-angle|fisheye|fish-eye|tilt-shift|macro|probe|periscope|swing-and-tilt|zoom)\s+(?:lenses|lens)\b"#),
        Rule(.lens, #"\bsplit[- ](?:focus\s+)?diopters?\b"#, name: "Split diopter"),

        // Lights
        Rule(.light, #"\bARRI\s+(?:SkyPanels?(?:\s+S\d{2,3}(?:-C)?)?|M\d{1,2}|Orbiter|L\d{1,2}(?:-C)?|T\d{1,2}|Max)\b"#),
        Rule(.light, #"\b(?<!ARRI )SkyPanels?(?:\s+S\d{2,3}(?:-C)?)?\b"#),
        Rule(.light, #"\bKino\s?Flos?(?:\s+(?:Celebs?|Diva-Lites?|Image\s?\d+))?\b"#),
        Rule(.light, #"\bAstera\s+(?:Titan|Helios|Hyperion|AX\d|tubes?)\b"#),
        Rule(.light, #"\bCreamsource(?:\s+(?:Vortex\s?\d{0,2}|Micro|SpaceX))?\b"#),
        Rule(.light, #"\bAputure(?:\s+(?:LS\s?)?\d{3,4}\w?|\s+Nova\s+\w+)?\b"#),
        Rule(.light, #"\bLitepanels?(?:\s+Gemini)?\b|\bLiteMats?\b|\bLiteGear\b"#),
        Rule(.light, #"\bQuasar\s+(?:Science\s+)?(?:tubes?|lights?)\b"#),
        Rule(.light, #"\bDino\s+lights?\b|\bMaxi-?Brutes?\b|\bWendy\s+lights?\b|\bMole\s?[Bb]eams?\b|\bMole-Richardson\b|\bSoftSun\b"#),
        Rule(.light, #"\bballoon\s+lights?\b"#, name: "Balloon lights"),
        Rule(.light, #"\b\d{1,2}K\s+(?:HMIs?|tungsten|Fresnels?|lights?|lamps?)\b"#),
        Rule(.light, #"\bHMIs?\b"#, name: "HMI", caseSensitive: true),
        Rule(.light, #"\btungsten\s+(?:lights?|lamps?|units?|lighting|fixtures?)\b"#, name: "Tungsten"),
        Rule(.light, #"\bsodium[- ]vapou?r\s+(?:lights?|lamps?|lighting)\b"#, name: "Sodium vapour"),
        Rule(.light, #"\bfluorescent\s+(?:tubes?|lights?|lighting|lamps?)\b"#, name: "Fluorescent"),
        Rule(.light, #"\bLED\s+(?:panels?|walls?|screens?|lights?|lighting|tubes?|fixtures?)\b"#, caseSensitive: true),
        Rule(.light, #"\bStageCraft\b|\bLED\s+volume\b"#, name: "LED volume"),
        Rule(.light, #"\bcandlelight\b|\bcandlelit\b|\blit\s+(?:\w+\s+){0,3}(?:by|with)\s+candles?\b"#, name: "Candlelight"),
        Rule(.light, #"\b(?:natural|available)\s+light(?:ing)?\b"#, name: "Natural light"),
        Rule(.light, #"\bpractical\s+(?:lights?|lighting|lamps?|sources?)\b|\bpracticals\b"#, name: "Practicals"),
        Rule(.light, #"\b(?:magic|golden)\s+hour\b"#, name: "Magic hour"),
        Rule(.light, #"\bblue\s+hour\b"#, name: "Blue hour"),
        Rule(.light, #"\bnegative\s+fill\b"#, name: "Negative fill"),
        Rule(.light, #"\bday[- ]for[- ]night\b"#, name: "Day for night"),
        Rule(.light, #"\b(?:rear|front)\s+projection\b"#),

        // Film stock and format
        Rule(.format, #"\bKodak\s+(?:Vision\s?[23]?\b|Ektachrome|Ektar|Tri-X|Double-X|Eastman\s+Double-X|EXR)(?:\s+(?:\d{2,3}[TD]|5\d{3}|7\d{3}|color\s+negative))*"#),
        Rule(.format, #"\bKodak\s+(?:5\d{3}|7\d{3}|\d{2,3}[TD])(?:\s+(?:\d{2,3}[TD]|5\d{3}|7\d{3}))*\b"#),
        Rule(.format, #"\bEastman\s+(?:Double-X|Color\s+Negative|EXR|5\d{3})(?:\s+\d{4})?"#),
        Rule(.format, #"\bFuji(?:film)?\s+(?:Eterna(?:\s+(?:Vivid\s+)?\d{3}[TD]?)?|Reala(?:\s+500D)?|F-\d{2,3}\w*|Vivid\s+\d{3}\w?)"#),
        Rule(.format, #"\b(?<!Eastman )(?<!Kodak )(?:Double-X|Tri-X|Ektachrome)\b"#),
        // A gauge, not a focal length ("a 35mm lens").
        Rule(.format, #"\b(?:Super\s?(?:8|16|35)(?:\s?-?\s?mm)?|(?:8|16|35|65|70)\s?-?\s?(?:mm|millimetre|millimeter))(?=\W|$)(?!\s+(?:lens|lenses|prime|primes|focal|spherical|anamorphic|wide-angle))"#, needsShooting: true,
             isGauge: true),
        Rule(.format, #"\bVistaVision\b"#, name: "VistaVision", needsShooting: true),
        Rule(.format, #"\bTechniscope\b"#, name: "Techniscope", needsShooting: true),
        Rule(.format, #"\bCinemaScope\b"#, name: "CinemaScope", needsShooting: true),
        Rule(.format, #"\b(?:Ultra|Super)\s+Panavision\s+70\b"#, needsShooting: true),
        Rule(.format, #"\bTodd-AO\b(?!\s+lens)"#, name: "Todd-AO", needsShooting: true),
        Rule(.format, #"\bthree-strip\s+Technicolor\b|\bTechnicolor\s+(?:three-strip|Process\s+4)\b"#, name: "Three-strip Technicolor"),
        Rule(.format, #"\b(?:shot|filmed|photographed|captured|recorded)\b(?:(?!releas|screen|project|convert|exhibit|blow|blown|transfer|scann|print)[^.]){0,40}\bIMAX\b|\bIMAX\s+(?:film\s+)?cameras?\b|\bIMAX\s+65\b|\b15/70\b"#, name: "IMAX"),
        Rule(.format, #"\bIMAX\s+(?:70|65)\s?-?\s?mm\b"#, name: "IMAX", needsShooting: true),
        Rule(.format, #"\b(?:shot|filmed|photographed)\s+(?:entirely\s+|largely\s+|mostly\s+)?(?:in|on)\s+black[- ]and[- ]white\b|\bblack[- ]and[- ]white\s+(?:film\s+)?stock\b"#, name: "Black and white"),
        Rule(.format, #"\b(?:shot|filmed|photographed|captured|recorded)\s+(?:\w+\s+){0,2}digitally\b|\bdigital(?:ly)?\s+(?:shot|filmed)\b|\b(?:shot|filmed)\s+(?:\w+\s+){0,2}on\s+digital\b|\bdigital\s+cinematography\b|\bdigital\s+cameras?\b"#, name: "Digital"),
        Rule(.format, #"\b(?:shot|filmed|photographed)\s+(?:\w+\s+){0,2}on\s+(?:\w+\s+)?film\b|\bcelluloid\b|\bphotochemical(?:ly)?\b"#, name: "Film"),
        Rule(.format, #"\b[1-2]\.\d{2}\s?:\s?1\b"#, needsShooting: true),
        Rule(.format, #"\b(?:Academy\s+ratio|4:3\s+aspect\s+ratio|1\.33)\b"#, name: "1.33:1 (Academy)", needsShooting: true),
        Rule(.format, #"\b(?:3|2)-perf(?:oration)?\b"#, needsShooting: true),
        Rule(.format, #"\bopen\s+gate\b"#, name: "Open gate", needsShooting: true),
        Rule(.format, #"\b(?:24|25|48|60|120)\s?(?:fps|frames\s+per\s+second)\b"#, needsShooting: true),
        // How a digital camera recorded
        Rule(.format, #"\bARRI\s?RAW\b"#, name: "ARRIRAW"),
        Rule(.format, #"\bREDCODE(?:\s+RAW)?\b|\bRed\s?Code\s+RAW\b"#, name: "REDCODE RAW"),
        Rule(.format, #"\bProRes(?:\s+(?:4444(?:\s+XQ)?|422(?:\s+HQ)?|RAW))?\b"#),
        Rule(.format, #"\bX-OCN(?:\s+(?:XT|ST|LT))?\b"#),
        Rule(.format, #"\bBlackmagic\s+RAW\b"#),
        Rule(.format, #"\b(?:2\.8|3\.4|4\.5|4\.6|5\.2|6\.5|6|8|12|16)K\b(?!\s+(?:HMI|tungsten|Fresnel|lights?|lamps?|DI|finish|master|release|UHD|Blu))"#,
             caseSensitive: true, needsShooting: true),

        // Grip and movement
        Rule(.support, #"\bSteadicams?\b"#, name: "Steadicam"),
        Rule(.support, #"\b(?:Super\s+)?Technocranes?\b"#),
        Rule(.support, #"\bRussian\s+Arm\b|\bUltimate\s+Arm\b|\bEdge\s+Arm\b"#),
        Rule(.support, #"\b(?:Freefly\s+)?M[oō]VI(?:\s+(?:Pro|XL|M\d{1,2}))?\b"#, caseSensitive: true),
        Rule(.support, #"\bDJI\s+Ronin(?:\s+(?:2|S|RS\s?\d))?\b(?!\s+4D)|\b(?<!DJI )Ronin\s+(?:2|S|RS\s?\d)\b"#),
        Rule(.support, #"\bgimbals?\b"#, name: "Gimbal"),
        Rule(.support, #"\bLibra\s+head\b|\bScorpio\s+head\b|\bOculus\s+head\b"#),
        Rule(.support, #"\bChapman\s+(?:Hybrid|PeeWee|Pee\s?Wee|Titan|Lenny|Super\s+PeeWee)(?:\s+[IVX]+)?\b|\bFisher\s+(?:10|11)\b"#),
        Rule(.support, #"\bdoll(?:y|ies)\b"#, name: "Dolly", caseSensitive: true),
        Rule(.support, #"\bcrane(?:\s+(?:shots?|moves?))?\b(?!\s+(?:operator|fly|bird))|\bcranes\b"#, name: "Crane", caseSensitive: true),
        Rule(.support, #"\bdrones?\s+(?:shots?|footage|cameras?|photography)\b|\b(?:by|with|from)\s+(?:a\s+)?drones?\b|\bdrones?\s+(?:was|were)\s+used\b"#,
             name: "Drone"),
        Rule(.support, #"\bSnorri[Cc]am\b"#, name: "SnorriCam"),
        Rule(.support, #"\bEasyrig\b"#),
        Rule(.support, #"\bARRI\s+Trinity\b"#),
        Rule(.support, #"\bcable\s?cams?\b|\bSpidercam\b"#, name: "Cable cam"),
        Rule(.support, #"\bmotion[- ]control\b|\bMilo\s+(?:rig|arm)\b|\bBolt\s+(?:High-Speed\s+)?Cinebot\b"#, name: "Motion control"),
        Rule(.support, #"\bhand-?held\b"#, name: "Handheld"),
        Rule(.support, #"\btripods?\b|\blocked[- ]off\b"#, name: "Tripod"),

        // Filters and diffusion
        Rule(.filter, #"\b(?:Tiffen\s+)?(?:Black\s+)?Pro-?Mist(?:\s+\d/\d+)?\b"#),
        Rule(.filter, #"\b(?:Tiffen\s+)?(?:Glimmerglass|Black\s+Satin|Black\s+Diffusion\s+FX|Soft\s?FX|Black\s+Frost|White\s+Frost|Antique\s+Suede|Low\s+Con|Ultra\s?Con|Double\s+Fog|Smoque)(?:\s+\d/\d+)?\b"#),
        Rule(.filter, #"\b(?:Schneider\s+)?Hollywood\s+Black\s+Magic(?:\s+\d/\d+)?\b|\bSchneider\s+(?:Classic\s+Soft|Black\s+Frost|Radiant\s+Soft|True-Pol)\b|\bClassic\s+Soft\b"#),
        Rule(.filter, #"\b(?:stockings?|nylons?|nets?|silk)\s+(?:on|behind|over|in front of)\s+the\s+lens\b"#, name: "A net on the lens"),
        Rule(.filter, #"\bdiffusion\s+filters?\b|\bdiffusion\s+(?:on|over)\s+the\s+lens\b"#, name: "Diffusion filters"),
        Rule(.filter, #"\bfog\s+filters?\b"#, name: "Fog filters"),
        Rule(.filter, #"\bND\s+filters?\b|\bneutral[- ]density\s+filters?\b"#, name: "ND filters"),
        Rule(.filter, #"\bpolari[sz](?:ing|ed)\s+filters?\b|\bpolari[sz]ers?\b"#, name: "Polariser"),
        Rule(.filter, #"\b(?:star|streak|coral|sepia|tobacco|graduated|grad|split-field)\s+filters?\b"#),

        // Lab, grade and finish
        Rule(.finish, #"\bdigital\s+intermediate\b"#, name: "Digital intermediate"),
        Rule(.finish, #"\b(?:2|4|8)K\s+(?:DI|digital\s+intermediate|finish|master|scans?)\b"#),
        Rule(.finish, #"\bbleach[- ]bypass\b|\bskip[- ]bleach\b|\bsilver\s+retention\b"#, name: "Bleach bypass"),
        Rule(.finish, #"\bENR\b"#, name: "ENR", caseSensitive: true),
        Rule(.finish, #"\bpush[- ]process(?:ed|ing)?\b|\bpushed\s+(?:one|two|a|1|2)\s+stops?\b"#, name: "Push processing"),
        Rule(.finish, #"\bcross[- ]process(?:ed|ing)?\b"#, name: "Cross processing"),
        Rule(.finish, #"\bfilm\s+(?:grain\s+)?emulation\b"#, name: "Film emulation"),
        Rule(.finish, #"\bLUTs?\b"#, name: "A show LUT", caseSensitive: true),
        Rule(.finish, #"\bfilm[- ]out\b|\b(?:printed|recorded)\s+(?:back\s+)?(?:to|on|onto)\s+film\b"#, name: "Film-out"),
        Rule(.finish, #"\b(?:FotoKem|Company\s+3|EFILM|Picture\s+Shop|Light\s+Iron|Cinelab|Kodak\s+Film\s+Lab|Technicolor\s+(?:lab|laboratory))\b|\bDeluxe\b(?=\s+(?:lab|laboratory|labs))"#,
             caseSensitive: true),
    ]
}
