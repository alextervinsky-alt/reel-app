import Foundation

/// How a film was shot, from what's written about it: the film's Wikipedia article, the
/// interviews and craft articles it cites (American Cinematographer, British Cinematographer…)
/// and the cinematographer's own article. It picks out the cameras, lenses, lights, grip, filters,
/// film stock, format and finish they name, and sorts what they say into the reasons behind the
/// look, the cinematographer's own words, the camera language, the lighting and the colour —
/// each with where it was read. Only names of real gear are picked out (an "Alexa" is a camera
/// when it's an ARRI Alexa, not an actor), formats only where the sentence is about the shooting,
/// not the release ("released in IMAX" is not "shot in IMAX"), and never from what critics or
/// awards said, or from sections about the music, release or reception.
public struct TechSpecs: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case camera, lens, format, light, support, filter, finish
    }

    public struct Spec: Equatable, Sendable, Identifiable {
        public let kind: Kind
        public let name: String
        /// A word Reel chose ("Digital", "Natural light"), not the article's own (so not looked for in it).
        public var isFixedName = false
        public var id: String { kind.rawValue + "|" + name.lowercased() }
    }

    /// A sentence (or two that belong together) and where it was read.
    public struct Note: Equatable, Sendable, Identifiable {
        public let text: String
        /// "American Cinematographer"; nil for the film's own Wikipedia article.
        public let source: String?
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

        public init(source: String?, sections: [FilmArticle.Section], isInterview: Bool) {
            self.source = source
            self.sections = sections
            self.isInterview = isInterview
        }

        public init(source: String, paragraphs: [String], isInterview: Bool = true) {
            self.init(source: source, sections: [FilmArticle.Section(id: 0, title: "", paragraphs: paragraphs)], isInterview: isInterview)
        }
    }

    public let specs: [Spec]
    /// Sentences naming gear that aren't in the parts below, in reading order (at most six).
    public let sentences: [Note]
    /// What the cinematographer said or chose (their words, or sentences about their choices).
    public var approach: [Note] = []
    /// Why it looks the way it does: choices with their reasons and references.
    public var reasons: [Note] = []
    /// How the film was lit: light sources, shadows, contrast.
    public var lighting: [Note] = []
    /// How the camera tells the story: movement, framing, takes, lenses chosen for a look.
    public var cameraLanguage: [Note] = []
    /// The palette, the grade and the finish.
    public var colour: [Note] = []

    public var isEmpty: Bool { specs.isEmpty }

    /// Nothing about the approach either.
    public var saysNothing: Bool {
        specs.isEmpty && approach.isEmpty && reasons.isEmpty && lighting.isEmpty && cameraLanguage.isEmpty && colour.isEmpty
    }

    public func names(_ kind: Kind) -> [String] {
        specs.filter { $0.kind == kind }.map(\.name)
    }

    /// Reads paragraphs with no headings (tests, plain text).
    public static func read(_ paragraphs: [String], cinematographers: [String] = []) -> TechSpecs {
        read(sections: [FilmArticle.Section(id: 0, title: "", paragraphs: paragraphs)], cinematographers: cinematographers)
    }

    /// Reads the film's article alone.
    public static func read(sections: [FilmArticle.Section], cinematographers: [String]) -> TechSpecs {
        read(texts: [Text(source: nil, sections: sections, isInterview: false)], cinematographers: cinematographers)
    }

    /// Reads everything written about the film, in the order given; `cinematographers` are the
    /// film's directors of photography (their sentences are the approach).
    public static func read(texts: [Text], cinematographers: [String]) -> TechSpecs {
        var found: [Spec] = []
        var gear: [Note] = []
        var approach: [Note] = []
        var reasons: [Note] = []
        var lighting: [Note] = []
        var cameraLanguage: [Note] = []
        var colour: [Note] = []
        // The full name, and the first and last names alone ("Hong" for Hong Kyung-pyo, "Deakins"
        // for Roger Deakins), as articles write them.
        let particles: Set<String> = ["van", "von", "der", "den", "del", "della", "les", "dos", "das"]
        let names = cinematographers.flatMap { name -> [String] in
            let parts = name.split(separator: " ").map(String.init)
            let single = [parts.first, parts.last].compactMap { $0 }
                .filter { $0.count >= 3 && !particles.contains($0.lowercased()) && $0 != name }
            return [name] + Set(single)
        }
        for text in texts {
            for section in text.sections {
                let heading = section.title.lowercased()
                // Never the story, its themes or analysis, even once watched.
                let commentary = !offTopic.contains { heading.contains($0) } && !Spoilers.isAfterSection([section.title])
                let visual = visualHeadings.contains { heading.contains($0) } && !heading.contains("effect")
                for paragraph in section.paragraphs {
                    // "He wanted…" right after a sentence about the cinematographer is theirs too.
                    var aboutThem = false
                    let sentences = Digest.sentences(in: paragraph)
                    var skipNext = false
                    for (index, sentence) in sentences.enumerated() {
                        if skipNext {
                            skipNext = false
                            continue
                        }
                        let lowered = sentence.lowercased()
                        var named = false
                        if triggers.contains(where: { lowered.contains($0) }) {
                            let aboutShooting = shooting.contains { lowered.contains($0) }
                            let aboutRelease = release.contains { lowered.contains($0) }
                            for rule in rules {
                                if rule.needsShooting, !aboutShooting || (aboutRelease && !strongShooting(lowered)) { continue }
                                for name in rule.matches(in: sentence) {
                                    named = true
                                    found.append(Spec(kind: rule.kind, name: name, isFixedName: rule.fixedName != nil))
                                }
                            }
                        }
                        // An interview talks about much else: only what's about the look is read.
                        let onTopic = !text.isInterview || named || matches(lookWords, sentence)
                        let fits = commentary && onTopic && (25...450).contains(sentence.count) && !matches(reception, sentence)
                        let theirs = mentions(names, in: sentence) || (aboutThem && matches(pronoun, sentence))
                            || (text.isInterview && (quoted(sentence) || matches(firstPerson, sentence)))
                        aboutThem = fits && theirs
                        let light = matches(lightTerms, sentence)
                        let camera = visual || matches(cameraTerms, sentence)
                        let colourful = matches(colourTerms, sentence)
                        // In an interview the sentence after often finishes the thought ("…on film.
                        // It gave us…"): read together.
                        var shown = sentence
                        if text.isInterview, index + 1 < sentences.count, matches(continuation, sentences[index + 1]),
                           sentence.count + sentences[index + 1].count < 520 {
                            shown += " " + sentences[index + 1]
                        }
                        let note = Note(text: shown, source: text.source)
                        var placed = true
                        // Where it belongs: the filmmakers' own words first, then the reasons,
                        // the lighting, the colour, the camera, then gear only.
                        if fits, theirs, matches(said, sentence) || quoted(sentence) || text.isInterview {
                            add(note, to: &approach)
                        } else if fits, light || camera || colourful || named, matches(reason, sentence) {
                            add(note, to: &reasons)
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
        var specs = TechSpecs(specs: tidy(found), sentences: Array(gear.prefix(6)))
        specs.approach = Array(approach.prefix(8))
        specs.reasons = Array(reasons.prefix(6))
        specs.lighting = Array(lighting.prefix(6))
        specs.cameraLanguage = Array(cameraLanguage.prefix(6))
        specs.colour = Array(colour.prefix(5))
        return specs
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

    static func quoted(_ sentence: String) -> Bool {
        sentence.contains(where: { "\"“”".contains($0) })
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Whether the sentence names one of them (whole words, as written).
    static func mentions(_ names: [String], in sentence: String) -> Bool {
        let generic = ["cinematographer", "director of photography", "cinematographers"]
        let lowered = sentence.lowercased()
        if generic.contains(where: { lowered.contains($0) }) { return true }
        if sentence.range(of: #"\b(?:DP|DoP|D\.P\.)(?=\W|$)"#, options: .regularExpression) != nil { return true }
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
        pattern: #"\b(?:praised|praising|nominated|nominations?|won|wins|awards?|acclaim\w*|critics?|critical|reviewers?|reviews?|box office|grossed|ranked|Oscars?|BAFTAs?|Academy Awards?|premiere[sd]?|debut\w*|screened|re-screened|screenings?|limited release|festivals?|distribut\w*|audiences?|international community)\b"#,
        options: [.caseInsensitive])
    static let said = try! NSRegularExpression(
        pattern: #"\b(?:said|says|explained|recalled|described|told|wanted|noted|stated|felt|aimed|chose|decided|opted|insisted|preferred|used|shot|lit|lensed|designed|inspired|influenced|referenced|wanted|approach|tried|avoided|had|requested|requests|asked|worked|collaborated|planned|tested|took|gave|kept|filmed|framed)\b"#,
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
        pattern: #"\b(?:handheld|hand-held|Steadicam|long takes?|single takes?|one take|oners?|one-shot|continuous (?:shots?|takes?)|tracking shots?|dolly|dollies|crane shots?|drones?|static (?:shots?|camera)|locked-off|wide shots?|wide-angle|close-ups?|point-of-view|POV|shot compositions?|symmetr\w*|depth of field|shallow focus|deep focus|split diopter|split-screen|zoom(?:s|ed|ing)? (?:in|out|lens\w*|shots?)|crash zooms?|whip pans?|panning|slow[- ]motion|camera movements?|camera moves?|the camera (?:moves?|follows?|stays?|tracks?|pushes|pulls|glides|lingers|never|always|rarely|is)|camerawork|camera work|visual style|visual language|visual approach|lensing|focal lengths?|storyboard\w*|shot lists?|traditional coverage|blocking|aspect ratio|anamorphic|negative space|low[- ]angle|high[- ]angle|Dutch angle|overhead shots?|aerial shots?|360-degree|Snorricam|underwater (?:camera|photography))\b"#,
        options: [.caseInsensitive])

    /// Each name once (the first spelling), and a name left out when a longer one of the same
    /// kind contains it ("ARRI Alexa" when there's "ARRI Alexa 65").
    static func tidy(_ specs: [Spec]) -> [Spec] {
        var seen = Set<String>()
        let unique = specs.filter { seen.insert($0.id).inserted }
        return unique.filter { spec in
            let name = spec.name.lowercased()
            return !unique.contains { other in
                other.kind == spec.kind && other.name.count > spec.name.count && other.name.lowercased().contains(name)
            }
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

        init(_ kind: Kind, _ pattern: String, name: String? = nil, caseSensitive: Bool = false, needsShooting: Bool = false) {
            self.kind = kind
            // The patterns are fixed and tested; a bad one would fail every test.
            regex = try! NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
            fixedName = name
            self.needsShooting = needsShooting
        }

        func matches(in sentence: String) -> [String] {
            let range = NSRange(sentence.startIndex..., in: sentence)
            return regex.matches(in: sentence, range: range).compactMap { match in
                if let fixedName { return fixedName }
                guard let found = Range(match.range, in: sentence) else { return nil }
                return TechSpecs.display(String(sentence[found]))
            }
        }
    }

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
        Rule(.camera, #"\bMoviecam(?:\s+Compact)?\b"#),
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
        Rule(.format, #"\b(?:Super\s?(?:8|16|35)(?:\s?-?\s?mm)?|(?:8|16|35|65|70)\s?-?\s?(?:mm|millimetre|millimeter))(?=\W|$)"#, needsShooting: true),
        Rule(.format, #"\bVistaVision\b"#, name: "VistaVision", needsShooting: true),
        Rule(.format, #"\bTechniscope\b"#, name: "Techniscope", needsShooting: true),
        Rule(.format, #"\bCinemaScope\b"#, name: "CinemaScope", needsShooting: true),
        Rule(.format, #"\b(?:Ultra|Super)\s+Panavision\s+70\b"#, needsShooting: true),
        Rule(.format, #"\bTodd-AO\b(?!\s+lens)"#, name: "Todd-AO", needsShooting: true),
        Rule(.format, #"\bthree-strip\s+Technicolor\b|\bTechnicolor\s+(?:three-strip|Process\s+4)\b"#, name: "Three-strip Technicolor"),
        Rule(.format, #"\b(?:shot|filmed|photographed|captured|recorded)\b(?:(?!releas|screen|project|convert|exhibit)[^.]){0,40}\bIMAX\b|\bIMAX\s+(?:film\s+)?cameras?\b|\bIMAX\s+65\b|\b15/70\b"#, name: "IMAX"),
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
