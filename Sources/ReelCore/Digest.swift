import Foundation

/// A part of the article under one heading ("Production"), made of its sections ("Development",
/// "Filming", "Music"…), so a few cards stand for the whole article.
public struct Chapter: Sendable, Identifiable {
    public struct Part: Sendable {
        /// The section's own heading under the chapter's ("Filming"), if it has one.
        public let title: String?
        public let paragraphs: [String]
    }

    public let id: Int
    public let title: String
    public let parts: [Part]

    public var paragraphs: [String] { parts.flatMap(\.paragraphs) }
}

/// A section of the film's article made short: its opening in a sentence or two, the facts
/// picked from it, and how long the whole of it takes to read (it opens in place).
public enum Digest {
    /// The opening sentences of a section, in order, up to about `limit` characters: at least
    /// one whole sentence, and a very long one cut at a word. A sentence shown elsewhere (the
    /// "Did you know?") is skipped.
    public static func lead(of paragraphs: [String], limit: Int = 240, skipping shown: String? = nil) -> String {
        let skip = shown.map(normalized)
        var text = ""
        for paragraph in paragraphs.prefix(2) {
            for sentence in sentences(in: paragraph) where normalized(sentence) != skip {
                let longer = text.isEmpty ? sentence : text + " " + sentence
                if !text.isEmpty, longer.count > limit {
                    return text
                }
                text = longer
            }
            if !text.isEmpty { break }
        }
        return text.count > limit + 80 ? ReceptionAnalyzer.shorten(text, limit: limit) : text
    }

    /// A paragraph's sentences, whatever their length.
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        let ends: Set<Character> = [".", "!", "?"]
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if ends.contains(ch) {
                // A closing quote right after belongs to this sentence: it ends after the quote.
                guard next == " " else { continue }
                // "Mr. Bong", "J. R. R. Tolkien" and "the U.S. release" carry on.
                if ch == ".", let word = current.split(separator: " ").last, isAbbreviation(String(word)) { continue }
            } else if ch == "\"" || ch == "”" {
                guard i > 0, ends.contains(chars[i - 1]), next == " " else { continue }
            } else {
                continue
            }
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { result.append(trimmed) }
            current = ""
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    static let abbreviations: Set<String> = ["mr.", "mrs.", "ms.", "dr.", "st.", "jr.", "sr.", "mt.", "vs.", "no.", "vol.",
                                             "inc.", "ltd.", "co.", "approx.", "e.g.", "i.e.", "etc."]

    static func isAbbreviation(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: "(\"“"))
        if abbreviations.contains(trimmed.lowercased()) { return true }
        // An initial ("J.") or letters with stops ("U.S.").
        let letters = trimmed.dropLast()
        return (letters.count == 1 && letters.first?.isUppercase == true) || (letters.contains(".") && !letters.contains(" "))
    }

    /// Whether the section says more than its lead.
    public static func hasMore(_ paragraphs: [String], lead: String) -> Bool {
        paragraphs.count > 1 || paragraphs.first.map { normalized($0).count > normalized(lead).count + 20 } ?? false
    }

    /// Minutes to read the whole section, at about 230 words a minute (at least 1).
    public static func minutes(_ paragraphs: [String]) -> Int {
        let words = paragraphs.reduce(0) { $0 + $1.split(whereSeparator: \.isWhitespace).count }
        return max(1, Int((Double(words) / 230).rounded()))
    }

    /// The facts that come from this section (each fact is one of the article's sentences),
    /// leaving out those the lead already says.
    public static func facts(_ facts: [FunFact], in paragraphs: [String], lead: String) -> [FunFact] {
        let body = normalized(paragraphs.joined(separator: " "))
        let shown = normalized(lead)
        return facts.filter { fact in
            let text = normalized(fact.text)
            return !text.isEmpty && body.contains(text) && !shown.contains(text)
        }
    }

    /// The facts that come from none of the sections, each section's text read once.
    public static func leftover(_ facts: [FunFact], sections: [FilmArticle.Section]) -> [FunFact] {
        let bodies = sections.map { normalized($0.paragraphs.joined(separator: " ")) }
        return facts.filter { fact in
            let text = normalized(fact.text)
            return !bodies.contains { $0.contains(text) }
        }
    }

    /// Sections in a row under the same heading ("Production · Filming", "Production · Music")
    /// become one chapter ("Production"), in reading order.
    public static func chapters(_ sections: [FilmArticle.Section]) -> [Chapter] {
        var chapters: [Chapter] = []
        for section in sections {
            let names = section.title.components(separatedBy: " · ")
            let top = names[0]
            let part = Chapter.Part(title: names.count > 1 ? names.dropFirst().joined(separator: " · ") : nil,
                                    paragraphs: section.paragraphs)
            if let last = chapters.last, last.title == top {
                chapters[chapters.count - 1] = Chapter(id: last.id, title: top, parts: last.parts + [part])
            } else {
                chapters.append(Chapter(id: section.id, title: top, parts: [part]))
            }
        }
        return chapters
    }

    /// The stages of a film's life, in the order it lived them: Behind the Film tells its
    /// article this way, whatever order the article uses.
    public enum Stage: Int, CaseIterable, Sendable {
        case idea, making, casting, shoot, design, music, release, reception, awards, legacy, other

        public var title: String {
            switch self {
            case .idea: "The Idea"
            case .making: "Making the Film"
            case .casting: "Casting"
            case .shoot: "The Shoot"
            case .design: "Design, Effects and Editing"
            case .music: "Music and Sound"
            case .release: "Release"
            case .reception: "How It Was Received"
            case .awards: "Awards"
            case .legacy: "Legacy"
            case .other: "More"
            }
        }

        /// Words in a heading that put a section in this stage (the most specific heading decides).
        var words: [String] {
            switch self {
            case .idea: ["development", "origin", "conception", "writing", "screenplay", "script", "pre-production",
                         "preproduction", "background", "inspiration", "influences", "premise", "concept", "adaptation", "source material"]
            case .making: ["production"]
            case .casting: ["casting"]
            case .shoot: ["filming", "principal photography", "photography", "shooting", "location", "cinematography", "shoot"]
            case .design: ["design", "costume", "set ", "sets", "makeup", "make-up", "visual effects", "effects", "animation",
                           "vfx", "post-production", "postproduction", "editing", "special effects", "creature"]
            case .music: ["music", "soundtrack", "score", "sound"]
            case .release: ["release", "premiere", "marketing", "distribution", "festival", "home media", "screening", "promotion"]
            case .reception: ["reception", "critical", "response", "review", "box office", "audience", "commercial", "ratings"]
            case .awards: ["accolade", "award", "honour", "honor", "nomination"]
            case .legacy: ["legacy", "impact", "sequel", "prequel", "remake", "other media", "cultural",
                           "future", "follow-up", "spin-off", "spinoff", "television series", "stage adaptation"]
            case .other: []
            }
        }

        /// The stage of a section: its own heading first ("Production · Music" is Music), then the
        /// headings above it. The film's introduction is no stage (nil).
        static func of(_ title: String) -> Stage? {
            let names = title.components(separatedBy: " · ").map { $0.lowercased() }
            if names == ["about the film"] { return nil }
            for name in names.reversed() {
                let padded = name + " "
                // The later stages first ("Stage adaptation" is legacy, not the idea); the general
                // "production" only when nothing more specific matches.
                for stage in [Stage.legacy, .awards, .reception, .release, .music, .design, .casting, .shoot, .idea] {
                    if stage.words.contains(where: { padded.contains($0) }) { return stage }
                }
            }
            return names.contains { $0.contains("production") } ? .making : .other
        }
    }

    /// The article's sections as the story of the film, one chapter per stage in the order the
    /// film lived them (the idea, the casting, the shoot… its legacy); the film's introduction
    /// is left out (the film page already says it). Each chapter's sections keep their headings.
    public static func story(_ sections: [FilmArticle.Section]) -> [(stage: Stage, chapter: Chapter)] {
        var byStage: [Stage: [FilmArticle.Section]] = [:]
        for section in sections {
            guard let stage = Stage.of(section.title) else { continue }
            byStage[stage, default: []].append(section)
        }
        return Stage.allCases.compactMap { stage in
            guard let found = byStage[stage], let first = found.first else { return nil }
            let parts = found.map { section in
                let names = section.title.components(separatedBy: " · ")
                return Chapter.Part(title: found.count > 1 || names.count > 1 ? names.last : nil, paragraphs: section.paragraphs)
            }
            // "More" keeps the article's own heading when there's one section.
            let title = stage == .other && found.count == 1 ? first.title.components(separatedBy: " · ").last ?? stage.title : stage.title
            return (stage, Chapter(id: first.id, title: title, parts: parts))
        }
    }

    /// Someone's words worth setting apart: a sentence quoting a person at some length ("Bong
    /// said he wanted…"), not the lead. Nil when there's none.
    public static func pullQuote(in paragraphs: [String], skipping shown: String) -> String? {
        let skip = normalized(shown)
        let speaking = try? NSRegularExpression(
            pattern: #"\b(?:said|says|recalled|explained|described|told|stated|noted|wrote|called|remarked|admitted|joked|added|according to)\b"#,
            options: [.caseInsensitive])
        let quote = try? NSRegularExpression(pattern: #"[“"]([^”"]{30,})[”"]"#)
        for paragraph in paragraphs {
            for sentence in sentences(in: paragraph) where (60...320).contains(sentence.count) && !skip.contains(normalized(sentence)) {
                let range = NSRange(sentence.startIndex..., in: sentence)
                guard let match = quote?.firstMatch(in: sentence, range: range),
                      let words = Range(match.range(at: 1), in: sentence).map({ sentence[$0].split(separator: " ").count }),
                      words >= 6 else { continue }
                if words >= 12 || speaking?.firstMatch(in: sentence, range: range) != nil { return sentence }
            }
        }
        return nil
    }

    /// The article's sentences about where the film was shot: locations, studios and stages
    /// (from the sections before the story), at most `limit`.
    public static func locationSentences(_ sections: [FilmArticle.Section], limit: Int = 5) -> [String] {
        // A place named after the shooting words ("in Budapest", "in the deserts of Jordan"; not a
        // month or a camera), on location, the locations, a stage or backlot, or a named studio
        // where something was built or shot (not "the studio" that made it).
        let notPlaces = "January|February|March|April|May|June|July|August|September|October|November|December|"
            + "IMAX|Technicolor|CinemaScope|Panavision|VistaVision|Kodak|Eastman|Fujifilm|ARRI|Arri|Alexa|Super|Ultra|Dolby|Sony|RED"
        let parts = [
            #"(?i:\b(?:filmed|shot|filming|shooting|photographed|principal photography)\b)[^.]{0,90}"#
                + #"(?i:\b(?:in|at|on|around|across|near)\s+(?:the\s+(?:[\w-]+\s+){1,2}of\s+|the\s+)?)"#
                + "(?!(?:" + notPlaces + #")\b)\p{Lu}"#,
            #"(?i:\bon location\b)"#,
            #"(?i:\blocations?\b[^.]{0,60}\b(?:included|in|such as)\b)"#,
            #"(?i:\b(?:sound ?stages?|soundstages?|backlots?)\b)"#,
            #"(?i:\b(?:built|constructed|filmed|shot|interiors|sets?)\b)[^.]{0,80}(?i:\b(?:at|in)\s+(?:the\s+)?)"#
                + #"\p{Lu}[\w'’-]*(?:\s+\p{Lu}[\w'’-]*){0,3}\s+Studios?\b"#,
        ]
        let regex = try? NSRegularExpression(pattern: parts.joined(separator: "|"))
        // Not what became of the places later (tourism, money, plans).
        let later = try? NSRegularExpression(pattern: #"(?i:\b(?:touris[mt]\w*|invest\w*|announced|plans? to|grossed|box office)\b)"#)
        var found: [String] = []
        for section in sections {
            for paragraph in section.paragraphs {
                for sentence in sentences(in: paragraph) where (30...360).contains(sentence.count) {
                    let range = NSRange(sentence.startIndex..., in: sentence)
                    guard regex?.firstMatch(in: sentence, range: range) != nil, later?.firstMatch(in: sentence, range: range) == nil,
                          !found.contains(sentence) else { continue }
                    found.append(sentence)
                    if found.count == limit { return found }
                }
            }
        }
        return found
    }

    /// The sentence after `sentence` in the paragraph it's from, to tell more of it: one that
    /// reads well beside it (40–240 characters) and isn't among `excluding`; nil when there's none.
    public static func followUp(to sentence: String, in sections: [FilmArticle.Section], excluding: Set<String> = []) -> String? {
        let target = normalized(sentence)
        for section in sections {
            for paragraph in section.paragraphs {
                let all = sentences(in: paragraph)
                guard let index = all.firstIndex(where: { normalized($0) == target }) else { continue }
                guard index + 1 < all.count else { return nil }
                let next = all[index + 1]
                guard (40...240).contains(next.count), !excluding.contains(next), !next.contains("[") else { return nil }
                return next
            }
        }
        return nil
    }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
