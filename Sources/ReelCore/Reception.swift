import Foundation

/// What reviewers tend to like and dislike about a film, worked out on the Mac from TMDB user
/// reviews. No outside service is involved.
public struct ReceptionSummary: Codable, Equatable, Sendable {
    public var liked: [ReceptionPoint]
    public var disliked: [ReceptionPoint]
    public var reviewCount: Int
    /// Average of the reviewers' own scores (out of 10), when they gave one.
    public var averageRating: Double?
    /// How many critics' sentences (from Wikipedia) were read as well.
    public var criticCount: Int?

    public init(liked: [ReceptionPoint], disliked: [ReceptionPoint], reviewCount: Int, averageRating: Double?, criticCount: Int? = nil) {
        self.liked = liked
        self.disliked = disliked
        self.reviewCount = reviewCount
        self.averageRating = averageRating
        self.criticCount = criticCount
    }

    /// Each quote once: a summary kept before Reel 1.8.1 could give one sentence to several
    /// points (it named the story, the themes and the characters); the later ones are left out.
    public var withoutRepeats: ReceptionSummary {
        var seen = Set<String>()
        func once(_ points: [ReceptionPoint]) -> [ReceptionPoint] {
            points.filter { point in point.quote.map { seen.insert($0).inserted } ?? true }
        }
        var copy = self
        copy.liked = once(liked)
        copy.disliked = once(disliked)
        return copy
    }
}

public struct ReceptionPoint: Codable, Equatable, Sendable {
    public var aspect: String
    public var mentions: Int
    public var quote: String?

    public init(aspect: String, mentions: Int, quote: String?) {
        self.aspect = aspect
        self.mentions = mentions
        self.quote = quote
    }
}

public struct ReviewText: Sendable {
    public var text: String
    public var rating: Double?
    /// A sentence from a critic (via Wikipedia) rather than a viewer's review.
    public var isCritic: Bool

    public init(text: String, rating: Double?, isCritic: Bool = false) {
        self.text = text
        self.rating = rating
        self.isCritic = isCritic
    }
}

public enum ReceptionAnalyzer {
    struct Aspect {
        let name: String
        let words: [String]
    }

    static let aspects: [Aspect] = [
        Aspect(name: "Story", words: ["story", "plot", "script", "screenplay", "writing", "narrative", "storyline", "premise"]),
        Aspect(name: "Acting", words: ["acting", "performance", "performances", "cast", "actor", "actors", "actress", "portrayal"]),
        Aspect(name: "Visuals", words: ["visuals", "visual", "cinematography", "shot", "shots", "imagery", "camera", "photography", "lighting", "colors", "colours"]),
        Aspect(name: "Music and sound", words: ["score", "soundtrack", "music", "sound", "sound design"]),
        Aspect(name: "Pacing", words: ["pacing", "pace", "paced", "slow", "runtime", "length", "drags", "dragged", "overlong", "too long", "tedious", "boring"]),
        Aspect(name: "Direction", words: ["direction", "directing", "director", "directed", "filmmaking"]),
        Aspect(name: "Characters", words: ["character", "characters", "characterization", "characterisation", "protagonist", "villain"]),
        Aspect(name: "Ending", words: ["ending", "finale", "climax", "conclusion", "third act"]),
        Aspect(name: "Action", words: ["action", "fight", "fights", "set piece", "set pieces", "stunts", "battle", "battles"]),
        Aspect(name: "Humour", words: ["funny", "humor", "humour", "jokes", "joke", "laughs", "hilarious", "comedic"]),
        Aspect(name: "Atmosphere", words: ["atmosphere", "atmospheric", "tone", "mood", "worldbuilding", "world-building", "world building", "setting"]),
        Aspect(name: "Effects", words: ["effects", "cgi", "vfx"]),
        Aspect(name: "Dialogue", words: ["dialogue", "dialog"]),
        Aspect(name: "Themes", words: ["themes", "theme", "message", "ideas", "subtext"]),
        Aspect(name: "Tension", words: ["tense", "tension", "suspense", "suspenseful", "thrilling", "gripping", "edge of"]),
        Aspect(name: "Originality", words: ["original", "originality", "unique", "fresh", "predictable", "derivative", "formulaic", "clichés", "cliches"]),
        Aspect(name: "Emotion", words: ["emotional", "moving", "touching", "heartfelt", "heartbreaking", "tearjerker", "feelings"]),
        Aspect(name: "Realism", words: ["realistic", "believable", "plausible", "implausible", "unbelievable", "authentic"]),
        Aspect(name: "Production design", words: ["production design", "sets", "costumes", "costume design", "set design"]),
    ]

    /// How an aspect reads inside a sentence, e.g. "its visuals".
    public static func phrase(for aspect: String, disliked: Bool = false) -> String {
        switch aspect {
        case "Acting": return "the acting"
        case "Music and sound": return "its music and sound"
        case "Pacing": return disliked ? "its slow pacing" : "its pacing"
        case "Originality": return disliked ? "a predictable story" : "its originality"
        case "Emotion": return disliked ? "a lack of emotional pull" : "its emotional pull"
        case "Realism": return disliked ? "implausible moments" : "its realism"
        case "Humour": return "its humour"
        default: return "its \(aspect.lowercased())"
        }
    }

    static let negativeCues = [
        "boring", "drags", "dragged", "overlong", "too long", "tedious", "predictable", "forgettable",
        "confusing", "bland", "messy", "cliched", "clichéd", "dull", "shallow", "pretentious", "cheesy",
        "uneven", "bloated", "disappointing", "underwhelming", "wasted", "lacks", "lacking", "falls flat",
    ]

    static let positiveCues: Set<String> = [
        "masterpiece", "stunning", "brilliant", "beautiful", "gorgeous", "outstanding", "incredible",
        "amazing", "excellent", "superb", "perfect", "fantastic", "phenomenal", "breathtaking",
        "memorable", "powerful", "compelling", "mesmerizing", "mesmerising", "captivating",
    ]

    /// - Parameter sentiment: scores a sentence from -1 (negative) to 1 (positive).
    /// Always tries to find two likes and two dislikes: aspects mentioned by several people come
    /// first, then single mentions fill the gap.
    public static func summarize(_ reviews: [ReviewText], sentiment: (String) -> Double) -> ReceptionSummary? {
        guard !reviews.isEmpty else { return nil }

        struct Tally {
            var like = 0
            var dislike = 0
            /// The best sentences for it, best first (one sentence often names several aspects:
            /// each point gets one no other point shows).
            var likeQuotes: [(text: String, quality: Double)] = []
            var dislikeQuotes: [(text: String, quality: Double)] = []
        }
        func keep(_ quote: (text: String, quality: Double), in quotes: inout [(text: String, quality: Double)]) {
            guard !quotes.contains(where: { $0.text == quote.text }) else { return }
            quotes.append(quote)
            quotes.sort { $0.quality > $1.quality }
            if quotes.count > 6 { quotes.removeLast() }
        }
        var tallies: [String: Tally] = [:]

        for review in reviews {
            var bias = 0.0
            if let rating = review.rating {
                if rating >= 7 { bias = 0.2 } else if rating <= 4 { bias = -0.2 }
            }
            for sentence in sentences(in: clean(review.text)) {
                let lower = sentence.lowercased()
                let words = Set(lower.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map { String($0) })
                let matched = aspects.filter { aspect in
                    aspect.words.contains { word in word.contains(" ") ? lower.contains(word) : words.contains(word) }
                }
                guard !matched.isEmpty else { continue }

                var score = sentiment(sentence) + bias
                if negativeCues.contains(where: { lower.contains($0) }) { score -= 0.4 }
                if !words.isDisjoint(with: positiveCues) { score += 0.2 }
                guard abs(score) >= 0.25 else { continue }

                let quality = abs(score) - lengthPenalty(sentence.count)
                for aspect in matched {
                    var t = tallies[aspect.name] ?? Tally()
                    if score > 0 {
                        t.like += 1
                        keep((sentence, quality), in: &t.likeQuotes)
                    } else {
                        t.dislike += 1
                        keep((sentence, quality), in: &t.dislikeQuotes)
                    }
                    tallies[aspect.name] = t
                }
            }
        }

        let audience = reviews.filter { !$0.isCritic }
        let minimum = audience.count >= 6 ? 2 : 1
        let byLikes = tallies.sorted { $0.value.like != $1.value.like ? $0.value.like > $1.value.like : $0.key < $1.key }
        let byDislikes = tallies.sorted { $0.value.dislike != $1.value.dislike ? $0.value.dislike > $1.value.dislike : $0.key < $1.key }

        var liked = byLikes.filter { $0.value.like >= minimum && $0.value.like > $0.value.dislike }.map { $0.key }
        for entry in byLikes where liked.count < 2 && entry.value.like >= 1 && entry.value.like >= entry.value.dislike && !liked.contains(entry.key) {
            liked.append(entry.key)
        }
        var disliked = byDislikes
            .filter { $0.value.dislike >= minimum && Double($0.value.dislike) >= Double($0.value.like) * 0.4 && !liked.contains($0.key) }
            .map { $0.key }
        for entry in byDislikes where disliked.count < 2 && entry.value.dislike >= 1 && !disliked.contains(entry.key) && !liked.prefix(2).contains(entry.key) {
            disliked.append(entry.key)
        }

        // Each sentence quoted once: a point whose sentences are all shown already says nothing new.
        var used = Set<String>()
        func points(_ keys: [String], quotes: (Tally) -> [(text: String, quality: Double)], mentions: (Tally) -> Int) -> [ReceptionPoint] {
            keys.compactMap { key in
                guard let tally = tallies[key] else { return nil }
                guard let quote = quotes(tally).first(where: { !used.contains($0.text) }) else { return nil }
                used.insert(quote.text)
                return ReceptionPoint(aspect: key, mentions: mentions(tally), quote: shorten(quote.text))
            }
        }
        let likedPoints = points(liked, quotes: \.likeQuotes, mentions: \.like).prefix(4)
        let dislikedPoints = points(disliked, quotes: \.dislikeQuotes, mentions: \.dislike).prefix(4)
        let scores = audience.compactMap { $0.rating }
        let average = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        let critics = reviews.count - audience.count
        return ReceptionSummary(liked: Array(likedPoints), disliked: Array(dislikedPoints), reviewCount: audience.count,
                                averageRating: average, criticCount: critics > 0 ? critics : nil)
    }

    /// Quotes read best at 40–200 characters.
    static func lengthPenalty(_ length: Int) -> Double {
        if length < 40 { return Double(40 - length) / 80 }
        if length > 200 { return Double(length - 200) / 400 }
        return 0
    }

    /// Removes markdown and HTML from review text.
    static func clean(_ text: String) -> String {
        var out = ""
        var inTag = false
        for ch in text {
            if ch == "<" { inTag = true; continue }
            if ch == ">" && inTag { inTag = false; continue }
            if inTag { continue }
            if ch == "*" || ch == "#" || ch == "_" || ch == "\r" { continue }
            out.append(ch)
        }
        return out
    }

    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            if ch == "\n" {
                flush(&current, into: &result)
                continue
            }
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                if next == " " || next == "\n" || next == "\"" || next == "”" {
                    flush(&current, into: &result)
                }
            }
        }
        flush(&current, into: &result)
        return result
    }

    private static func flush(_ current: inout String, into result: inout [String]) {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 25 && trimmed.count <= 320 { result.append(trimmed) }
        current = ""
    }

    static func shorten(_ sentence: String, limit: Int = 220) -> String {
        guard sentence.count > limit else { return sentence }
        let cut = sentence.prefix(limit)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]) + "…"
    }
}
