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
        case "Intensity": return disliked ? "scenes too dark or intense" : "its intensity"
        default: return "its \(aspect.lowercased())"
        }
    }

    static let negativeCues = [
        "boring", "drags", "dragged", "overlong", "too long", "tedious", "predictable", "forgettable",
        "confusing", "bland", "messy", "cliched", "clichéd", "dull", "shallow", "pretentious", "cheesy",
        "uneven", "bloated", "disappointing", "underwhelming", "wasted", "lacks", "lacking", "falls flat",
        // How viewers say what didn't work for them in an otherwise warm review.
        "complaint", "complaints", "gripe", "nitpick", "downside", "drawback", "weakest",
        "would have liked", "a bit too", "a little too", "too slow", "too dark", "too scary", "too intense",
        "too violent", "not enough", "convoluted", "lost me",
        "weak", "fails", "failed", "falls short", "fell flat", "overrated", "unconvincing", "clunky", "not as good",
        "doesn't work", "didn't work", "disjointed", "repetitive", "overstuffed", "underdeveloped",
        "sluggish", "plodding", "meandering", "stilted", "muddled", "derivative", "formulaic", "a mess", "slog",
    ]

    /// What a clause with no aspect word is about, from the way it complains ("it's a bit
    /// confusing" is the story, "it drags" the pacing).
    static let cueAspects: [(cue: String, aspect: String)] = [
        ("confusing", "Story"), ("convoluted", "Story"), ("lost me", "Story"), ("messy", "Story"),
        ("predictable", "Originality"), ("cliched", "Originality"), ("clichéd", "Originality"), ("formulaic", "Originality"),
        ("boring", "Pacing"), ("dull", "Pacing"), ("tedious", "Pacing"), ("drags", "Pacing"), ("dragged", "Pacing"),
        ("overlong", "Pacing"), ("too long", "Pacing"), ("bloated", "Pacing"), ("too slow", "Pacing"),
        ("cheesy", "Dialogue"), ("pretentious", "Atmosphere"),
        ("too dark", "Intensity"), ("too scary", "Intensity"), ("too intense", "Intensity"), ("too violent", "Intensity"),
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
            /// Dislikes that say so in words (a complaint, or a critic said to have faulted it),
            /// not only by the sentence's tone.
            var complaints = 0
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
                // Scores, rankings and prizes are facts about the film, not opinions about it.
                if reportsFigures(sentence, critic: review.isCritic) { continue }
                // Each part of "praised the visuals but faulted the pacing" counts on its own.
                for clause in clauses(of: sentence) {
                    let lower = clause.lowercased()
                    var matched = aspects(in: lower)
                    // "It's a bit confusing at times": a complaint names its aspect itself.
                    if matched.isEmpty, let cue = cueAspects.first(where: { word($0.cue, in: lower) != nil }), !negated(cue.cue, in: lower) {
                        matched = [cue.aspect]
                    }
                    guard !matched.isEmpty else { continue }

                    let said = reported(lower)
                    // Each way of complaining counts ("my only complaint is that it drags");
                    // denied, it praises ("never boring", "no complaints").
                    var cues = 0.0
                    var complains = false
                    for cue in negativeCues where word(cue, in: lower) != nil {
                        if negated(cue, in: lower) {
                            cues += 0.5
                        } else {
                            cues -= 0.4
                            complains = true
                        }
                    }
                    var score: Double
                    if review.isCritic {
                        // A critic as Wikipedia tells it: what they're said to have done decides
                        // ("praised", "faulted"); the sentence's tone alone only when it's clear.
                        if said != 0 {
                            score = 0.6 * Double(said)
                        } else {
                            score = sentiment(clause)
                            guard abs(score) >= 0.5 else { continue }
                        }
                    } else {
                        // A warm review's score doesn't soften what it complains about.
                        score = sentiment(clause) + (complains ? min(bias, 0) : bias) + 0.3 * Double(said)
                    }
                    score += max(cues, -0.8)
                    let words = Set(lower.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map { String($0) })
                    if !words.isDisjoint(with: positiveCues) { score += 0.2 }
                    guard abs(score) >= 0.25 else { continue }
                    // A dislike is said in words: a complaint, a critic said to have faulted it, or a
                    // viewer who rated it low. The tone of a sentence alone isn't one: "a disquieting
                    // chiller" and "a performance of grim determination" are praise.
                    if score < 0, !complains, said >= 0, review.isCritic || (review.rating ?? 10) > 5 { continue }

                    let quality = abs(score) - lengthPenalty(sentence.count)
                    for aspect in matched {
                        var t = tallies[aspect] ?? Tally()
                        if score > 0 {
                            t.like += 1
                            keep((sentence, quality), in: &t.likeQuotes)
                        } else {
                            t.dislike += 1
                            if complains || said < 0 { t.complaints += 1 }
                            keep((sentence, quality), in: &t.dislikeQuotes)
                        }
                        tallies[aspect] = t
                    }
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
        // Still short: a real complaint about something most liked counts too ("the story is
        // beautiful" from many, "a bit confusing" from one), shown with its own sentence.
        for entry in byDislikes where disliked.count < 2 && entry.value.complaints >= 1 && !disliked.contains(entry.key) {
            disliked.append(entry.key)
        }

        // Each sentence quoted once: a point whose sentences are all shown already says nothing new.
        // The points with the fewest sentences to choose from choose first, so one sentence that
        // names several aspects doesn't leave another point without one.
        var used = Set<String>()
        func points(_ keys: [String], quotes: (Tally) -> [(text: String, quality: Double)], mentions: (Tally) -> Int) -> [ReceptionPoint] {
            let order = keys.enumerated().sorted { a, b in
                let ca = tallies[a.element].map { quotes($0).count } ?? 0, cb = tallies[b.element].map { quotes($0).count } ?? 0
                return ca != cb ? ca < cb : a.offset < b.offset
            }
            var chosen: [String: String] = [:]
            for (_, key) in order {
                guard let tally = tallies[key], let quote = quotes(tally).first(where: { !used.contains($0.text) }) else { continue }
                used.insert(quote.text)
                chosen[key] = quote.text
            }
            return keys.compactMap { key in
                guard let tally = tallies[key], let quote = chosen[key] else { return nil }
                return ReceptionPoint(aspect: key, mentions: mentions(tally), quote: shorten(quote))
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

    /// The aspects a clause is about. "Score" is the music only when it isn't a rating ("a
    /// weighted average score of 96", "a score of 8 out of 10").
    static func aspects(in lower: String) -> [String] {
        let words = Set(lower.split(whereSeparator: { !$0.isLetter && $0 != "-" }).map { String($0) })
        let scoreIsRating = lower.range(of: #"\bscores?\s+of\s+\d|\bout of \d|\b(?:weighted|aggregate)\s+(?:average\s+)?scores?\b|\bscored?\s+(?:an?\s+)?(?:perfect\s+)?\d|\bout of (?:five|ten)\b"#,
                                        options: .regularExpression) != nil
        return aspects.filter { aspect in
            aspect.words.contains { word in
                if word == "score", scoreIsRating { return false }
                return word.contains(" ") ? lower.contains(word) : words.contains(word)
            }
        }.map(\.name)
    }

    /// A sentence of figures and honours, which says how the film fared, not what anyone liked
    /// or disliked: review aggregators and box office always; for critics' sentences also
    /// rankings, polls and nominations, unless it says what someone praised or faulted.
    static func reportsFigures(_ sentence: String, critic: Bool) -> Bool {
        let always = #"\b(?:metacritic|rotten tomatoes|cinemascore|approval rating|weighted average|box office|grossed|grossing)\b"#
        let honours = #"\b(?:ranked|ranking|rankings|top \d+|list of|nominat\w*|accolades?|polls?|sight (?:and|&) sound|surveys?|awards?|oscars?|golden globes?|baftas?|festivals?|guild|out of (?:10|100)|based on \d+|\d+ (?:critics|reviews))\b"#
        let lower = sentence.lowercased()
        if lower.range(of: always, options: .regularExpression) != nil { return true }
        return critic && lower.range(of: honours, options: .regularExpression) != nil && reported(lower) == 0
    }

    static let praiseWords = #"\b(?:prais\w*|laud\w*|applaud\w*|acclaim\w*|admired|admires|admiring|admiration|commend\w*|hail\w*|complimen\w*|favou?rabl\w*|enjoy\w*|loved|impressed|impressive\w*|raved?|highlight\w*|singled out|delight\w*|triumph\w*)\b"#
    static let faultWords = #"\b(?:critici[sz]\w*|critical of|fault\w*|panned|derid\w*|dismiss\w*|complain\w*|dislik\w*|took issue|unimpress\w*|less enthusiastic|unfavou?rabl\w*|negative|lament\w*|bemoan\w*|weakness\w*|flaws?|flawed|marred|disappoint(?:ed|ing|ment|s)?)\b"#

    /// What a critic is said to have done: praised (1), faulted (-1), or neither (0). The first
    /// such word decides; denied ("not impressed", "never disappoints") it turns around.
    static func reported(_ lower: String) -> Int {
        let praise = lower.range(of: praiseWords, options: .regularExpression)
        let fault = lower.range(of: faultWords, options: .regularExpression)
        let first: (range: Range<String.Index>, sign: Int)? = switch (praise, fault) {
        case let (p?, f?): p.lowerBound <= f.lowerBound ? (p, 1) : (f, -1)
        case let (p?, nil): (p, 1)
        case let (nil, f?): (f, -1)
        case (nil, nil): nil
        }
        guard let first else { return 0 }
        return denied(before: first.range.lowerBound, in: lower) ? -first.sign : first.sign
    }

    /// Whether a word is denied just before it ("not boring", "never dull", "isn't predictable").
    static func negated(_ cue: String, in lower: String) -> Bool {
        guard let range = word(cue, in: lower) else { return false }
        return denied(before: range.lowerBound, in: lower)
    }

    /// A cue as whole words: "lacks" isn't in "inky blacks", "predictable" isn't "unpredictable",
    /// "dull" isn't "Dullea".
    static func word(_ cue: String, in lower: String) -> Range<String.Index>? {
        lower.range(of: "\\b" + NSRegularExpression.escapedPattern(for: cue) + "\\b", options: .regularExpression)
    }

    /// One of the three words before a position denies it (whole words: "another", "nothing"
    /// and "relentless" don't).
    static func denied(before index: String.Index, in lower: String) -> Bool {
        let before = Array(lower[..<index].split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }).suffix(3))
        // "not only praised", "not just", "no less impressive" aren't denials.
        let phrase = before.joined(separator: " ")
        if [" not only", " not just", " no less", " not merely"].contains(where: { (" " + phrase).contains($0) }) { return false }
        return before.contains { ["not", "never", "hardly", "without", "nor", "no", "less"].contains($0) || $0.hasSuffix("n't") || $0.hasSuffix("n’t") }
    }

    /// A sentence's parts on either side of "but", "although", "however", "whereas", ", while",
    /// ", yet" or a semicolon (and of the comma after a leading "Although …"), each read on its own.
    static func clauses(of sentence: String) -> [String] {
        let marker = #"\s*;\s*|,?\s+(?:but|although|though|however|whereas),?\s+|,\s+(?:while|yet)\s+"#
        var parts: [String] = []
        var rest = sentence[...]
        while let range = rest.range(of: marker, options: [.regularExpression, .caseInsensitive]) {
            parts.append(String(rest[..<range.lowerBound]))
            rest = rest[range.upperBound...]
        }
        parts.append(String(rest))
        // "Although the plot is thin, the visuals are stunning": the comma ends the first part.
        return parts.flatMap { part -> [String] in
            let lower = part.lowercased()
            guard ["although ", "though ", "while ", "despite ", "even if "].contains(where: lower.hasPrefix),
                  let comma = part.firstIndex(of: ",") else { return [part] }
            return [String(part[..<comma]), String(part[part.index(after: comma)...])]
        }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.count >= 8 }
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
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            i += 1
            if ch == "\n" {
                flush(&current, into: &result)
                continue
            }
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                // "listed at No. 5", "St. Louis", "the U.S. release" carry on; "released in the
                // U.S. It grossed…" ends there.
                if ch == ".", let word = current.split(separator: " ").last, Digest.isAbbreviation(String(word)),
                   !startsSentence(after: i, in: chars) { continue }
                var next: Character = i < chars.count ? chars[i] : " "
                // A closing quote stays with its sentence (not at the start of the next one).
                if next == "\"" || next == "”" {
                    current.append(next)
                    i += 1
                    next = i < chars.count ? chars[i] : " "
                }
                if next == " " || next == "\n" {
                    flush(&current, into: &result)
                }
            }
        }
        flush(&current, into: &result)
        return result
    }

    /// Whether the next word starts a sentence of its own ("It", "The", "In"…), so a stop after
    /// "U.S." or an initial ends one.
    static func startsSentence(after index: Int, in chars: [Character]) -> Bool {
        var i = index
        while i < chars.count, chars[i] == " " { i += 1 }
        var word = ""
        while i < chars.count, chars[i].isLetter { word.append(chars[i]); i += 1 }
        return ["It", "The", "He", "She", "They", "This", "These", "In", "A", "An", "But", "However", "After", "When", "Its", "His", "Her"].contains(word)
    }

    /// Quotation marks that open or close nothing are taken off the ends ("" Orlando…" →
    /// "Orlando…"), so a quote shows its own words only.
    static func tidyQuotes(_ text: String) -> String {
        let marks: Set<Character> = ["\"", "“", "”"]
        var result = text.trimmingCharacters(in: .whitespaces)
        func unbalanced() -> Bool { result.filter { marks.contains($0) }.count % 2 == 1 }
        while let first = result.first, marks.contains(first),
              unbalanced() || result.dropFirst().first.map({ $0 == " " || marks.contains($0) }) ?? true {
            result = String(result.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        while let last = result.last, marks.contains(last), unbalanced() {
            result = String(result.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func flush(_ current: inout String, into result: inout [String]) {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 25 && trimmed.count <= 320 { result.append(trimmed) }
        current = ""
    }

    static func shorten(_ sentence: String, limit: Int = 220) -> String {
        let sentence = tidyQuotes(sentence)
        guard sentence.count > limit else { return sentence }
        let cut = sentence.prefix(limit)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]) + "…"
    }
}
