import Foundation

/// What each way of finding pages for one film turned up, and what became of it: kept, left out and
/// why, asked for, over a limit. Filled from the decisions as they're made (see `CameraSources.about`,
/// `CameraSources.pick`, `CameraSources.merge` and `CameraSourcesClient`), never worked out again
/// afterwards, and written to the film's reading log (DISCOVERY). It observes; it decides nothing.
/// Not kept in the library.
public struct DiscoveryTrace: Equatable, Sendable {
    /// What a request for search results or links brought.
    public enum Outcome: Equatable, Sendable {
        /// Not asked, and why ("no Wikipedia article for the film").
        case notAttempted(String)
        /// Asked, and no answer (the failure's own words: "didn't answer: timed out (read again later)").
        case failed(String)
        /// Answered, but with something other than search results (a page in their place).
        case notASearchAnswer
        /// Answered with this many results.
        case answered(Int)
        /// Answered that there's nothing to search (Wikipedia: no article of that title).
        case answeredNone(String)
    }

    /// Why a search result or a cited link was left out, as the filter that left it out says.
    public enum Rejection: String, CaseIterable, Equatable, Sendable {
        case wrongKind = "not an article, post or news item"
        case notAboutFilm = "doesn't name the film in its title or address"
        case otherFilm = "about another film of its collection"
        case notAnAddress = "not an address Reel reads"
        case duplicate = "the same address twice"
        case overLimit = "over the limit"
        case navigation = "a front, tag, search or category page"
        case unlistedSite = "not a site Reel reads"
        case newsNotCamera = "a news page not about the camera work"
    }

    public struct Hit: Equatable, Sendable {
        public let title: String
        public let url: String
        /// Nil when kept.
        public let rejected: Rejection?
    }

    /// A magazine's own search.
    public struct Search: Equatable, Sendable {
        public let site: String
        public let query: String
        public var outcome: Outcome
        /// Every result, in the order the site gave them.
        public var hits: [Hit] = []
        /// At most this many kept.
        public let limit: Int
    }

    /// The film's Wikipedia article's external links.
    public struct Cited: Equatable, Sendable {
        public var outcome: Outcome
        /// The most Reel asks the API for (it may hold more).
        public let requestLimit: Int
        /// Every link and what became of it, in the article's order.
        public var links: [Hit] = []
        /// At most this many kept.
        public let limit: Int
    }

    /// A guessed address of a story page (Kodak, No Film School).
    public struct Guess: Equatable, Sendable {
        public enum Result: Equatable, Sendable {
            /// Read, and it names the cinematographer: found.
            case found
            /// Read, but it doesn't name the cinematographer (the same title may be another film).
            case doesntNameCinematographer
            /// Not read (the failure's own words: "gone: not found over HTTPS (404)").
            case failed(String)
        }
        public let site: String
        public let url: String
        public let result: Result
    }

    /// The cinematographer's Wikipedia article.
    public enum Person: Equatable, Sendable {
        case notAttempted(String)
        /// Asked, and no answer.
        case failed(String)
        /// No article (or an empty one) under the name.
        case noArticle(String)
        /// An article of that name, but not a cinematographer's.
        case notACinematographer(String)
        /// Its paragraphs naming the film (at most four are read).
        case found(String, paragraphs: Int)
    }

    /// How the pages kept by the ways above became the ones asked for.
    public struct Assembly: Equatable, Sendable {
        /// Kept by the searches and Wikipedia's links together, before duplicates.
        public var candidates = 0
        /// Found by more than one way at the same address: asked for once.
        public var foundTwice: [String] = []
        /// Another address of an article already kept (listed under NOT READ).
        public var otherAddresses: [String] = []
        /// Asked for, in order.
        public var asked: [String] = []
        /// Not asked for: over the limit of pages asked for.
        public var overLimit: [String] = []
        public var askLimit = 8
        public var readLimit = 6
    }

    public var searches: [Search] = []
    public var cited: Cited?
    /// Not tried, and why (no cinematographer, a title with no letters).
    public var guessesNotAttempted: String?
    public var guesses: [Guess] = []
    public var person: Person?
    public var assembly = Assembly()

    public init() {}

    // MARK: The log

    /// The DISCOVERY section's lines.
    public func lines() -> [String] {
        var lines: [String] = []
        for search in searches {
            lines.append("• \(search.site) search for “\(search.query)”: " + Self.describe(search.outcome, kept: search.hits, limit: search.limit))
            lines += Self.hitLines(search.hits)
        }
        if let cited {
            var line = "• Wikipedia's cited links: " + Self.describe(cited.outcome, kept: cited.links, limit: cited.limit, noun: "link")
            if case .answered(let count) = cited.outcome, count >= cited.requestLimit {
                line += " (Reel asks for at most \(cited.requestLimit); the article may cite more)"
            }
            lines.append(line)
            lines += Self.hitLines(cited.links, titled: false)
        }
        if let why = guessesNotAttempted {
            lines.append("• Story pages (Kodak, No Film School): not tried: \(why)")
        } else if !guesses.isEmpty {
            lines.append("• Story pages (Kodak, No Film School), guessed from the title:")
            for guess in guesses {
                let result: String
                switch guess.result {
                case .found: result = "found, and it names the cinematographer"
                case .doesntNameCinematographer: result = "found, but it doesn't name the cinematographer: left out"
                case .failed(let why): result = why
                }
                lines.append("  \(guess.site): \(guess.url) — \(result)")
            }
        }
        if let person {
            let text: String
            switch person {
            case .notAttempted(let why): text = "not looked up: \(why)"
            case .failed(let why): text = "couldn't be reached: \(why)"
            case .noArticle(let name): text = "\(name) — no article found"
            case .notACinematographer(let name): text = "\(name) — an article of that name, not a cinematographer's: left out"
            case .found(let name, let count):
                text = count == 0 ? "\(name) — no paragraph names the film"
                    : "\(name) — \(count) paragraph\(count == 1 ? "" : "s") naming the film, read with the rest"
            }
            lines.append("• The cinematographer's Wikipedia article: " + text)
        }
        let a = assembly
        var pages = "• Pages: \(a.candidates) kept above"
        if !a.foundTwice.isEmpty { pages += "; \(a.foundTwice.count) found twice, asked for once" }
        if !a.otherAddresses.isEmpty { pages += "; \(a.otherAddresses.count) another address of an article kept (under NOT READ)" }
        pages += "; \(a.asked.count) asked for"
        pages += a.overLimit.isEmpty ? "" : "; \(a.overLimit.count) not asked for, over the limit of \(a.askLimit)"
        pages += "; at most \(a.readLimit) read (see READ and NOT READ)"
        lines.append(pages)
        for url in a.overLimit.prefix(Self.examples) { lines.append("  not asked for (over the limit): \(url)") }
        if a.overLimit.count > Self.examples { lines.append("  … and \(a.overLimit.count - Self.examples) more") }
        return lines
    }

    /// At most this many left-out examples of each reason.
    static let examples = 5

    static func describe(_ outcome: Outcome, kept hits: [Hit], limit: Int, noun: String = "result") -> String {
        switch outcome {
        case .notAttempted(let why): return "not tried: \(why)"
        case .failed(let why): return why
        case .answeredNone(let why): return why
        case .notASearchAnswer: return "answered with a page, not search results (read again later)"
        case .answered(let count):
            guard count > 0 else { return "no \(noun)s" }
            let kept = hits.filter { $0.rejected == nil }.count
            var text = "\(count) \(noun)\(count == 1 ? "" : "s"); \(kept) kept (at most \(limit))"
            let left = Rejection.allCases.compactMap { reason -> String? in
                let n = hits.filter { $0.rejected == reason }.count
                return n == 0 ? nil : "\(n) \(reason.rawValue)"
            }
            if !left.isEmpty { text += ", \(hits.count - kept) left out: " + left.joined(separator: "; ") }
            return text
        }
    }

    static func hitLines(_ hits: [Hit], titled: Bool = true) -> [String] {
        var lines: [String] = []
        for hit in hits where hit.rejected == nil {
            lines.append("  kept: " + (titled && !hit.title.isEmpty ? "\(hit.title) — " : "") + hit.url)
        }
        for reason in Rejection.allCases {
            let left = hits.filter { $0.rejected == reason }
            for hit in left.prefix(examples) {
                lines.append("  left out (\(reason.rawValue)): " + (titled && !hit.title.isEmpty ? "\(hit.title) — " : "") + hit.url)
            }
            if left.count > examples { lines.append("  … and \(left.count - examples) more \(reason.rawValue)") }
        }
        return lines
    }
}
