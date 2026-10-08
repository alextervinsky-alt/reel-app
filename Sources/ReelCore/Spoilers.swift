import Foundation

/// Telling story details apart from everything else, so a film you haven't seen stays unspoiled.
/// It errs on the side of hiding: a sentence that might give something away counts as a spoiler.
public enum Spoilers {
    /// Single words that point at what happens in the story.
    static let words: Set<String> = [
        "ending", "endings", "twist", "twists", "climax", "climactic", "reveal", "reveals", "revealed", "revealing",
        "revelation", "dies", "died", "dying", "killed", "kills", "murdered", "suicide", "betrays", "betrayed",
        "betrayal", "secretly", "epilogue", "spoiler", "spoilers", "survives", "survived", "unmasked", "executed",
        "sacrifices", "finale", "denouement", "flashforward",
    ]

    /// Phrases that point at what happens in the story.
    static let phrases: [String] = [
        "turns out", "final scene", "final shot", "final sequence", "last scene", "last shot", "final act",
        "third act", "true identity", "real identity", "is actually", "was actually", "in the end", "at the end",
        "end of the film", "end of the movie", "death of", "fate of", "flash forward", "final confrontation",
        "closing scene", "closing shot", "the reveal",
    ]

    /// Whether a sentence or paragraph may give away the story.
    public static func mentionsPlot(_ text: String) -> Bool {
        let lower = text.lowercased()
        let padded = " " + lower.map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce(into: "") { $0.append($1) } + " "
        if phrases.contains(where: { padded.contains(" " + $0 + " ") }) { return true }
        let tokens = lower.split(whereSeparator: { !$0.isLetter })
        return tokens.contains { words.contains(String($0)) }
    }

    /// Article sections that are about the story itself: read after the film.
    public static func isAfterSection(_ path: [String]) -> Bool {
        // Whole words ("Production history" isn't the story); word starts cover plurals and forms.
        let words = path.joined(separator: " ").lowercased().split(whereSeparator: { !$0.isLetter })
        let starts = ["plot", "synopsis", "summary", "summaries", "story", "stories", "storyline", "ending", "theme",
                      "thematic", "analysis", "interpretation", "symbolism", "allegor", "meaning", "spoiler"]
        return words.contains { word in starts.contains { word.hasPrefix($0) } }
    }
}

/// A film's Wikipedia article as Reel's Behind the Film tab shows it: what's safe before watching, and what
/// to read after (the story, its themes, and every paragraph that gives something away).
public struct FilmArticle: Equatable, Sendable {
    public struct Section: Equatable, Sendable, Identifiable {
        public let id: Int
        public let title: String
        public let paragraphs: [String]
    }

    public let title: String
    public let before: [Section]
    public let after: [Section]

    public var url: URL? {
        title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            .flatMap { URL(string: "https://en.wikipedia.org/wiki/\($0)") }
    }

    /// Lists, references and links: nothing to read there.
    static let skipped = ["cast", "references", "external links", "see also", "notes", "further reading",
                          "bibliography", "sources", "citations", "track listing", "footnotes", "works cited"]

    public init(title: String, extract: String) {
        self.title = title
        var before: [Section] = []
        var after: [Section] = []
        var id = 0
        for section in FunFactExtractor.sections(from: extract) {
            let top = section.path.first?.lowercased() ?? ""
            if Self.skipped.contains(where: { top == $0 || top.hasPrefix($0 + " ") }) { continue }
            let heading = section.path.first == "Introduction"
                ? "About the Film"
                : section.path.filter { $0 != "Introduction" }.joined(separator: " · ")
            let paragraphs = section.text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= 40 }
            guard !paragraphs.isEmpty else { continue }
            if Spoilers.isAfterSection(section.path) {
                id += 1
                after.append(Section(id: id, title: heading, paragraphs: paragraphs))
                continue
            }
            let safe = paragraphs.filter { !Spoilers.mentionsPlot($0) }
            let telling = paragraphs.filter { Spoilers.mentionsPlot($0) }
            if !safe.isEmpty {
                id += 1
                before.append(Section(id: id, title: heading, paragraphs: safe))
            }
            if !telling.isEmpty {
                id += 1
                after.append(Section(id: id, title: heading, paragraphs: telling))
            }
        }
        self.before = before
        self.after = after
    }

    public var isEmpty: Bool { before.isEmpty && after.isEmpty }
}

extension WikipediaClient {
    /// The film's article, split for reading before and after watching.
    public func article(title: String) async throws -> FilmArticle? {
        guard let text = try await extract(title: title), !text.isEmpty else { return nil }
        return FilmArticle(title: title, extract: text)
    }
}
