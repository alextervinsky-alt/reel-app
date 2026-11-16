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
        Aspect(name: "Emotion", words: ["emotional", "touching", "heartfelt", "heartbreaking", "tearjerker", "feelings"]),
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

    /// - Parameters:
    ///   - title, year: the film's, so sentences about other films can be told apart.
    ///   - sentiment: scores a sentence from -1 (negative) to 1 (positive).
    /// A like or a dislike is a part of a sentence that judges one aspect of this film in words
    /// ("the score is superb", "critics faulted the pacing"), with nothing said the other way;
    /// the sentence's tone alone never makes one, and when in doubt nothing is shown (1.11, spec §6.4).
    public static func summarize(_ reviews: [ReviewText], title: String? = nil, year: Int? = nil,
                                 sentiment: (String) -> Double) -> ReceptionSummary? {
        guard !reviews.isEmpty else { return nil }

        struct Tally {
            var like = 0
            var dislike = 0
            /// The best sentences for it, best first (one sentence often names several aspects:
            /// each point gets one no other point shows).
            var likeQuotes: [(text: String, quality: Double)] = []
            var dislikeQuotes: [(text: String, quality: Double)] = []
            /// Dislikes said in so many words (all of them since 1.11).
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
            for sentence in sentences(in: clean(review.text)) {
                // Scores, rankings and prizes are facts about the film, not opinions about it;
                // a sentence about another film, a question or what "people" said is left out.
                if reportsFigures(sentence, critic: review.isCritic) || aboutSomethingElse(sentence, title: title, year: year) { continue }
                let quotable = isQuotable(sentence)
                // Each part of "praised the visuals but faulted the pacing" counts on its own.
                for (index, clause) in clauses(of: sentence).enumerated() {
                    let found = judgements(in: clause, startsSentence: index == 0 && sentence.hasPrefix(clause.prefix(8)))
                    guard !found.isEmpty else { continue }
                    let signs = Set(found.map(\.sign))
                    // Praise and complaint in the same part: in doubt, neither.
                    guard signs.count == 1, let sign = signs.first else { continue }
                    // The sentiment model can only veto: a "superb" in a bitter part, or a
                    // complaint word in a glowing one, is left out.
                    if !review.isCritic {
                        let tone = sentiment(clause)
                        if sign > 0, tone < -0.4 { continue }
                        if sign < 0, tone > 0.5 { continue }
                    }
                    let quality = (quotable ? 1 : 0) - lengthPenalty(sentence.count) + Double(found.count) * 0.1
                    for aspect in Set(found.map(\.aspect)) {
                        var t = tallies[aspect] ?? Tally()
                        if sign > 0 {
                            t.like += 1
                            if quotable { keep((sentence, quality), in: &t.likeQuotes) }
                        } else {
                            t.dislike += 1
                            t.complaints += 1
                            if quotable { keep((sentence, quality), in: &t.dislikeQuotes) }
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
                return ReceptionPoint(aspect: key, mentions: mentions(tally), quote: tidyQuotes(quote))
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

    /// Words that praise what they're near ("superb acting", "the score is stunning").
    static let praise: [String] = [
        "great", "good", "excellent", "amazing", "superb", "brilliant", "brilliantly", "stunning", "beautiful", "beautifully",
        "gorgeous", "wonderful", "wonderfully", "fantastic", "incredible", "outstanding", "impressive", "perfect", "perfectly",
        "phenomenal", "breathtaking", "masterful", "masterfully", "top-notch", "top notch", "solid", "strong", "effective",
        "compelling", "captivating", "gripping", "engaging", "engrossing", "mesmerizing", "mesmerising", "memorable",
        "powerful", "terrific", "flawless", "enjoyable", "enjoyed", "loved", "love", "best", "remarkable", "exceptional",
        "spectacular", "epic", "awesome", "standout", "stand-out", "stellar", "delightful", "charming", "funny", "hilarious",
        "touching", "heartfelt", "convincing", "well-written", "well written", "well done", "well-acted", "well acted",
        "well paced", "well-paced", "shines", "shine", "shone", "excels", "nailed", "thrilling", "suspenseful", "tense",
        "atmospheric", "haunting", "striking", "vivid", "rich", "sharp", "clever", "witty", "fun", "entertaining",
        "intense", "immersive", "majestic", "magnificent", "glorious", "sublime", "exquisite", "pitch-perfect",
        "favorite", "favourite", "endearing",
    ]

    /// Words that fault what they're near ("wooden acting", "the plot is a mess").
    static let fault: [String] = negativeCues + [
        "bad", "poor", "poorly", "terrible", "awful", "horrible", "worst", "wooden", "flat", "generic", "lazy", "cringe",
        "cringey", "cringeworthy", "annoying", "unnecessary", "pointless", "nonsensical", "incoherent", "inconsistent",
        "ridiculous", "laughable", "mediocre", "subpar", "sub-par", "unmemorable", "uninteresting", "paper-thin", "thin",
        "lifeless", "soulless", "hollow", "empty", "abrupt", "rushed", "dumb", "stupid", "silly", "overdone", "overwrought",
        "uninspired", "unfunny", "jarring", "clumsy", "lackluster", "lacklustre", "tiresome", "dragging", "dullness",
        "problem", "problems", "issue", "issues", "worse", "awkward", "sloppy", "mess", "cringe-worthy",
    ]

    /// Words that judge only what they stand right next to ("poor acting", not "a poor family").
    static let tight: Set<String> = [
        "poor", "rich", "sharp", "strong", "flat", "thin", "empty", "hollow", "solid", "fun", "silly", "dumb", "intense",
        "tense", "effective", "issue", "issues", "problem", "problems", "love", "best", "favorite", "favourite", "epic",
        "mess", "fine",
    ]

    /// Words that can go either way ("unbelievable visuals", "an unbelievable plot"): a part with
    /// one says nothing for sure.
    static let eitherWay: Set<String> = ["unbelievable", "insane", "crazy", "wild", "mixed", "polarising", "polarizing", "divisive"]

    /// The phrases above by their first word, so a clause is read in one pass.
    static func byFirstWord(_ phrases: [String]) -> [String: [[String]]] {
        var index: [String: [[String]]] = [:]
        for phrase in phrases {
            let parts = phrase.split(separator: " ").map(String.init)
            index[parts[0], default: []].append(parts)
        }
        for key in index.keys { index[key]?.sort { $0.count > $1.count } }
        return index
    }
    static let praiseIndex = byFirstWord(praise)
    static let faultIndex = byFirstWord(fault)
    static let aspectIndex: [String: [(parts: [String], aspect: String)]] = {
        var index: [String: [(parts: [String], aspect: String)]] = [:]
        for aspect in aspects {
            for word in aspect.words {
                let parts = word.split(separator: " ").map(String.init)
                index[parts[0], default: []].append((parts, aspect.name))
            }
        }
        return index
    }()

    /// "lacking in sexism", "no shortage of": a fault word that praises.
    static let notFaults = #"\b(?:lack(?:s|ing)?(?: in| of| any)? (?:sexism|clich[eé]s?|pretension|filler|fat|gore)|no problems?|no issues?|not a (?:single )?(?:dull|boring|wasted)|without (?:a|any) (?:dull|boring|wasted))\b"#

    /// Critics as Wikipedia tells it, said to have praised or faulted something, by their words.
    static let praiseVerbs = #"^(?:prais\w*|laud\w*|applaud\w*|acclaim\w*|admired|admires|admiring|commend\w*|hail\w*|complimen\w*|highlight\w*|celebrat\w*|appreciat\w*)$"#
    static let faultVerbs = #"^(?:critici[sz]\w*|fault\w*|panned|derid\w*|complain\w*|dislik\w*|lament\w*|bemoan\w*|weakness\w*|flaws?|flawed|marred|disappoint(?:ed|ing|ment|s)?)$"#

    struct Judgement: Equatable {
        let aspect: String
        let sign: Int
    }

    /// What a clause judges, and which way: each praising or faulting word paired with the aspect
    /// word nearest it (at most five words away). A word denied just before it ("not boring",
    /// "never dull") judges nothing, except "not good", "not great" and the like, which fault. An
    /// aspect word written as a name ("Toy Story", "the Story of…") isn't one.
    static func judgements(in clause: String, startsSentence: Bool) -> [Judgement] {
        let lowerClause = clause.lowercased()
        if lowerClause.range(of: notFaults, options: .regularExpression) != nil { return [] }
        // Wishes, conditions and what might be: nothing said about this film as it is.
        if lowerClause.range(of: #"^(?:if|unless|when)\b|\b(?:would (?:have )?lov\w*|would have liked to see|i wish|i hope|hopefully|might)\b"#,
                             options: .regularExpression) != nil { return [] }
        // The words, with whether each is written as a name.
        let tokens: [(word: String, name: Bool)] = clause
            .split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" && $0 != "’" })
            .map { raw in
                let word = String(raw)
                let first = word.first.map { $0.isUppercase } ?? false
                let rest = word.dropFirst().contains { $0.isLowercase }
                return (word.lowercased().replacingOccurrences(of: "’", with: "'"), first && rest)
            }
        guard !tokens.isEmpty else { return [] }
        let words = tokens.map(\.word)
        if words.contains(where: eitherWay.contains) { return [] }
        func matches(_ parts: [String], at i: Int) -> Bool {
            guard i + parts.count <= words.count else { return false }
            for (k, part) in parts.enumerated() where words[i + k] != part { return false }
            return true
        }
        // Aspect words, by position.
        var aspectAt: [(index: Int, aspect: String)] = []
        for i in words.indices {
            if tokens[i].name && !(i == 0 && startsSentence) { continue }
            // "to see her in action" isn't the action scenes.
            if words[i] == "action", i > 0, words[i - 1] == "in" { continue }
            // "…, writing: "…"" is a critic writing, not the writing.
            if words[i] == "writing", i + 1 < words.count, words[i + 1] == "that" || lowerClause.range(of: #"writing[,:]?\s*["“]"#, options: .regularExpression) != nil { continue }
            for entry in aspectIndex[words[i]] ?? [] where matches(entry.parts, at: i) {
                if entry.aspect == "Music and sound", words[i] == "score",
                   lowerClause.range(of: #"\bscores?\s+of\s+\d|\bout of \d|\bscored?\s+(?:an?\s+)?\d"#, options: .regularExpression) != nil { continue }
                if !aspectAt.contains(where: { $0.index == i && $0.aspect == entry.aspect }) { aspectAt.append((i, entry.aspect)) }
            }
        }
        // An aspect word that judges ("boring", "funny") is about itself, never what's next to it:
        // in "boring and lazy writing" the laziness is the writing's.
        let judging = Set(aspectAt.map(\.index).filter { praiseIndex[words[$0]] != nil || faultIndex[words[$0]] != nil })
        let aboutTheFilm = words.contains { ["film", "movie", "it", "it's", "this", "picture"].contains($0) }
        guard !aspectAt.isEmpty || aboutTheFilm else { return [] }
        let negators: Set<String> = ["not", "never", "hardly", "without", "nor", "no", "nothing", "none", "neither", "barely", "less", "despite", "spite"]
        func denied(_ i: Int) -> Bool {
            let before = words[max(0, i - 4)..<i]
            let phrase = " " + before.joined(separator: " ")
            if [" not only", " not just", " no less", " not merely"].contains(where: phrase.contains) { return false }
            if before.contains(where: { negators.contains($0) || $0.hasSuffix("n't") }) { return true }
            // "Not a single line of dialogue is wasted."
            let earlier = " " + words[..<i].joined(separator: " ") + " "
            return [" not a single ", " not one ", " nothing about ", " nothing in ", " never once "].contains(where: earlier.contains)
        }
        let softPraise: Set<String> = ["good", "great", "funny", "convincing", "engaging", "enough", "strong", "effective", "fun", "entertaining"]
        var found: [Judgement] = []
        var i = 0
        while i < words.count {
            var sign = 0
            var length = 1
            var verb = false
            if let parts = praiseIndex[words[i]]?.first(where: { matches($0, at: i) }) {
                sign = 1; length = parts.count
            } else if let parts = faultIndex[words[i]]?.first(where: { matches($0, at: i) }) {
                sign = -1; length = parts.count
            } else if words[i].range(of: praiseVerbs, options: .regularExpression) != nil {
                sign = 1; verb = true
            } else if words[i].range(of: faultVerbs, options: .regularExpression) != nil {
                sign = -1; verb = true
            }
            guard sign != 0 else { i += 1; continue }
            let next = i + length < words.count ? words[i + length] : ""
            // "a love story", "her best friend", "it's funny that…": not praise.
            if ["love": ["story", "stories", "triangle", "interest", "affair", "scene", "scenes"],
                "best": ["friend", "friends"], "funny": ["that", "how", "seeing", "watching", "to", "enough"]][words[i]]?.contains(next) == true {
                i += length; continue
            }
            if denied(i) {
                // "not good", "wasn't funny": a complaint; "not boring", "never disappoints": nothing.
                if sign > 0, softPraise.contains(words[i]) { sign = -1 } else { i += length; continue }
            }
            // The aspect it's about: an aspect word close by ("boring characters"), else within five
            // words ("the score of this film is superb"), else its own ("it drags"), else the one
            // its complaint names. A critic's "praised…" looks ahead only, at what was praised.
            let reach = verb ? 6 : (tight.contains(words[i]) ? 2 : 5)
            // "…received praise", "…drew criticism": the nouns look back too.
            let looksBack = !verb || ["praise", "acclaim", "criticism", "criticisms", "complaints", "flaws", "flaw"].contains(words[i])
            let others = aspectAt.filter { !judging.contains($0.index) && (($0.index < i && looksBack) || $0.index >= i + length) }
                .map { (distance: $0.index < i ? i - $0.index : $0.index - (i + length - 1), aspect: $0.aspect) }
                .sorted { $0.distance < $1.distance }
            let own = aspectAt.first { $0.index == i }?.aspect
            var aspect: String?
            if let near = others.first, near.distance <= reach {
                aspect = near.aspect
            } else if let own {
                aspect = own
            } else if sign < 0, !verb, aboutTheFilm, let cue = cueAspects.first(where: { matches($0.cue.split(separator: " ").map(String.init), at: i) }) {
                aspect = cue.aspect
            }
            if let aspect { found.append(Judgement(aspect: aspect, sign: sign)) }
            i += length
        }
        return found
    }

    /// Sentences that aren't about this film, or not someone's own view of it: another film
    /// named (a short title in quotes, another year, a sequel, the book, "compared to"), a
    /// question, or what "people" or "the public" are said to think. When in doubt, left out.
    static func aboutSomethingElse(_ sentence: String, title: String?, year: Int?) -> Bool {
        let lower = sentence.lowercased()
        if sentence.hasSuffix("?") || sentence.hasSuffix("?\"") || sentence.hasSuffix("?”") { return true }
        let others = #"\b(?:sequels?|prequels?|predecessors?|previous (?:films?|movies?|one|entry|entries|instalments?|installments?)|(?:first|last|earlier|original) (?:film|movie|one)|the originals?|original (?:trilogy|series|film|movie)|the (?:books?|novels?|comics?|comic books?|series|miniseries|show|source material)|remakes?|reboots?|solo (?:film|movie)|compared (?:to|with)|comparing|reminiscent of|unlike|in contrast|people said|the public|general public|commentators|online|fans|viewers said|lampoon\w*|sketch|parod\w*|meme)\b"#
        if lower.range(of: others, options: .regularExpression) != nil { return true }
        // Another year: another film (its own year, or the next, is this one).
        if let year, let match = sentence.range(of: #"\b(?:19|20)\d\d\b"#, options: .regularExpression),
           let other = Int(sentence[match]), abs(other - year) > 1 { return true }
        // A short title in quotes ("‘Fargo’", "“Shall We Dance”"), not this film's.
        let quoted = #"[“"‘']([A-Z][^“”"‘’]{0,40}?)[”"’'](?!\w)"#
        var rest = sentence[...]
        while let match = rest.range(of: quoted, options: .regularExpression) {
            let inner = rest[match].dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            let parts = inner.split(separator: " ")
            let small: Set<String> = ["of", "the", "a", "an", "and", "in", "on", "to", "at", "for", "&"]
            let titleLike = (1...6).contains(parts.count) && !inner.hasSuffix(".") && !inner.hasSuffix(",")
                && parts.allSatisfy { part in small.contains(part.lowercased()) || part.first.map { $0.isUppercase || $0.isNumber } ?? false }
            if titleLike, inner.lowercased() != title?.lowercased() { return true }
            rest = rest[match.upperBound...]
        }
        return false
    }

    /// A quote is one whole sentence: it starts with a capital (or a quote mark and a capital),
    /// ends on a full stop, exclamation or question mark (a closing quote may follow), and isn't
    /// too long to read at a glance.
    static func isQuotable(_ sentence: String) -> Bool {
        let text = tidyQuotes(sentence)
        guard (30...240).contains(text.count), !text.contains("\n") else { return false }
        let opening = text.drop { "\"“‘'".contains($0) }
        guard opening.first?.isUppercase == true else { return false }
        let closing = text.reversed().drop { "\"”’'".contains($0) }
        guard let last = closing.first, ".!".contains(last) else { return false }
        // Every quotation in it closed ("…, writing, "Worst of all, it's dishonest." isn't).
        if text.filter({ $0 == "\"" }).count % 2 == 1 || text.filter({ $0 == "“" }).count != text.filter({ $0 == "”" }).count { return false }
        // Ends on "...": trails off.
        return !text.hasSuffix("..") && !text.hasSuffix("…")
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
            // "\r\n" is one Character: kept as one, it never ended a paragraph (before 1.11 a
            // quote could run on into the next paragraphs).
            if ch == "\r\n" { out.append("\n"); continue }
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
