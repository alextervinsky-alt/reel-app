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

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
