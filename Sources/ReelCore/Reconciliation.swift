import Foundation

// MARK: - Earlier findings, read again (1.10.9)

extension CraftIndex {
    /// One finding and the passage it stands on: a gear name ("Technocrane") or a Shot on tag
    /// ("film"), where it was read and what became of it. A reading keeps every finding it confirmed,
    /// and every earlier one it couldn't settle, so a reading by newer rules that fails to find an
    /// earlier statement never silently drops it (`SourceReconciliation`).
    public struct Claim: Codable, Equatable, Sendable {
        public enum Status: String, Codable, Sendable, CaseIterable {
            /// A status a later Reel wrote that this one doesn't know reads as pending: kept, not shown.
            public init(from decoder: Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Status(rawValue: raw) ?? .pending
            }

            /// Read in this reading's text and accepted by its rules.
            case confirmed
            /// Its source couldn't be read again (didn't answer, an incomplete page, not found this
            /// time): kept as it was, and tried again.
            case carried
            /// Its source was read again, but these rules couldn't settle whether the passage says it
            /// of this film: kept, not shown as found, until a reading settles it.
            case pending
            /// Read again and ruled out (the passage is about another production, denies it, is a
            /// plan or a hypothetical…), or the passage is no longer there: support withdrawn.
            case retired
            /// Recorded by a Reel before 1.10.9, which kept no passage for gear names (1.10.10): it
            /// can't be looked up in its source, so it is never retired for not being found. Shown
            /// apart, as previously recorded and awaiting verification; confirmed when a reading finds
            /// it, retired only when a reading's own text denies it.
            case legacy
        }

        public let name: String
        /// A gear kind (`TechSpecs.Kind`'s raw value) or "shotOn".
        public let kind: String
        /// The passage, as read (at most 400 characters); nil for a finding kept from before 1.10.9,
        /// which stored no passage for gear names.
        public var text: String?
        /// Where it was read ("American Cinematographer", "Wikipedia", "Wikipedia: Roger Deakins").
        public var source: String
        public var status: Status
        /// Why it's carried, pending or retired ("about another production", "no longer on the page").
        public var reason: String?
        /// When it was first found, and the rules that found it.
        public var since: Date
        public var rules: Int
        /// Readings in a row it's been carried or pending without being settled.
        public var misses: Int = 0
        /// Readings in a row its article wasn't read at all (another article of its site was; 1.10.10):
        /// counted apart from `misses`, against twice `CraftIndex.maxRetries`, and never for a finding
        /// pending reassessment (its passage was there when last read).
        /// (Optional, so libraries written before 1.10.10 decode: a missing key is 0.)
        public var unread: Int? = nil
        /// The article it was read from, by its canonical address (1.10.10; nil for a finding read
        /// before, or from Wikipedia): what tells two articles of one site apart.
        public var article: String? = nil

        public init(name: String, kind: String, text: String?, source: String, status: Status, reason: String? = nil,
                    since: Date, rules: Int, misses: Int = 0, article: String? = nil) {
            self.name = name
            self.kind = kind
            self.text = text
            self.source = source
            self.status = status
            self.reason = reason
            self.since = since
            self.rules = rules
            self.misses = misses
            self.article = article
        }

        /// What makes two findings the same: the name (by its canonical form) and the source.
        /// (And the article, 1.10.10: the same name read in two articles of one site is two findings.)
        var key: String { kind + "|" + TitleMatch.key(name) + "|" + source + "|" + (article ?? "") }
        /// The passage's fingerprint: its first 90 letters and digits, the article and the name.
        public var fingerprint: String {
            (article ?? source) + "|" + TitleMatch.key(name) + "|" + String(SourceReconciliation.squash(text ?? "").prefix(90))
        }
        var site: String { CraftIndex.site(of: source) }
        /// Shown as found: confirmed now, or carried while its source can't be read.
        public var supports: Bool { status == .confirmed || status == .carried }
        /// Shown apart, as recorded but not verified by this reading (1.10.10): never invisible.
        public var awaitingVerification: Bool { status == .pending || status == .legacy }
    }

    /// The findings behind a reading by 1.10.9 rules or later, and those it kept or retired; nil
    /// for earlier readings (their tags' sentences are in `evidence`, their names have none).
    public var claimsKnown: [Claim] { claims ?? [] }
}

/// How a reading treats what the reading before it found (1.10.9). Staged, and decided source by
/// source, never by the order sources were read:
/// 1. every statement this reading accepted is a confirmed finding;
/// 2. each earlier finding not confirmed again is looked up in its own source:
///    - the source wasn't read this time (it didn't answer, its page was incomplete or wasn't found):
///      carried, unchanged, for up to `CraftIndex.maxRetries` readings while every site answers;
///    - the source was read (or fetched and set aside) in full: its passage is looked for. Not
///      there → retired ("no longer on the page"). There and ruled out by these rules (another
///      production, denied, a hypothetical, a plan, a test, a simulation, delivery…) → retired with
///      that reason. There but not settled (the page wasn't read for it, the statement couldn't be
///      tied to this film or another) → pending, kept but not shown as found;
///    - an earlier finding with no stored passage (gear names before 1.10.9) can't be looked for:
///      pending until a reading confirms it, retired after `CraftIndex.maxRetries` readings;
/// 3. a finding supported by any source stands, whatever another source says: one source ruled
///    out never takes away another's support.
/// Nothing is written until the whole reading is reconciled: the result replaces the stored
/// reading in one step, as every reading does (`LibraryStore` writes the file atomically).
public enum SourceReconciliation {
    /// What a reading found and read, as reconciliation needs it.
    public struct Input: Sendable {
        /// The statements accepted (`TechSpecs.accepted`) and set aside with a reason (`TechSpecs.judged`).
        public var accepted: [TechSpecs.Spec]
        public var judged: [TechSpecs.Judgement]
        /// Named but neither accepted nor ruled out (abstained, or not said of the film).
        public var mentioned: [TechSpecs.Spec]
        /// The Shot on tags this reading found.
        public var shotOn: [ShotOn: CraftIndex.Evidence]
        /// The text of every source read, by its source label.
        public var read: [String: [String]]
        /// Pages fetched in full but set aside (another film's, a passing mention…), by site.
        public var fetched: [String: [[String]]]
        /// The articles read or fetched in full, by canonical address (1.10.10).
        public var articles: Set<String> = []
        /// Sites that didn't answer, and sites whose page came incomplete.
        public var unanswered: Set<String>
        public var incomplete: Set<String>
        public var rules: Int

        public init(accepted: [TechSpecs.Spec], judged: [TechSpecs.Judgement], mentioned: [TechSpecs.Spec], shotOn: [ShotOn: CraftIndex.Evidence],
                    read: [String: [String]], fetched: [String: [[String]]], unanswered: Set<String>, incomplete: Set<String>, rules: Int) {
            self.accepted = accepted
            self.judged = judged
            self.mentioned = mentioned
            self.shotOn = shotOn
            self.read = read
            self.fetched = fetched
            self.unanswered = unanswered
            self.incomplete = incomplete
            self.rules = rules
        }
    }

    /// Letters and digits only, lowercase and unaccented: how passages are compared across readings
    /// (quotes, dashes and spacing differ between fetches).
    static func squash(_ text: String) -> String {
        TitleMatch.fold(text).filter { $0.isLetter || $0.isNumber }
    }

    /// The same name, by its letters and digits, a plural "s" aside: "Alexa Mini" isn't "Alexa Mini LF".
    static func sameName(_ a: String, _ b: String) -> Bool {
        let x = squash(a), y = squash(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || x + "s" == y || y + "s" == x || x + "es" == y || y + "es" == x
    }

    /// The Shot on tags a gear name gives (`CraftIndex.shotOn`).
    static func tags(_ kind: TechSpecs.Kind, _ name: String) -> Set<ShotOn> {
        CraftIndex.shotOn(TechSpecs.Spec(kind: kind, name: name))
    }

    /// Whether `passage` is in `paragraphs` (by its first 90 letters and digits).
    static func contains(_ paragraphs: [String], passage: String) -> Bool {
        let probe = String(squash(passage).prefix(90))
        guard probe.count >= 12 else { return false }
        return paragraphs.contains { squash($0).contains(probe) }
    }

    static func samePassage(_ a: String, _ b: String) -> Bool {
        let x = String(squash(a).prefix(90)), y = String(squash(b).prefix(90))
        return x.count >= 12 && y.count >= 12 && (x.hasPrefix(y) || y.hasPrefix(x))
    }

    /// The findings of this reading, the earlier ones reconciled with it.
    public static func reconcile(previous: CraftIndex?, with input: Input, now: Date) -> [CraftIndex.Claim] {
        // 1. What this reading confirmed, once per name and source.
        var claims: [CraftIndex.Claim] = []
        var seen = Set<String>()
        for spec in input.accepted {
            let claim = CraftIndex.Claim(name: spec.name, kind: spec.kind.rawValue, text: spec.evidence.map { String($0.prefix(400)) },
                                         source: spec.source ?? "Wikipedia", status: .confirmed, since: now, rules: input.rules, article: spec.article)
            if seen.insert(claim.key).inserted { claims.append(claim) }
        }
        // A Shot on tag, once per source that says it: every accepted statement of capture that gives
        // the tag, and the tag's own evidence (Wikidata, TMDB, a sentence saying "black-and-white").
        let tagsFound = Set(input.shotOn.keys)
        for spec in input.accepted where spec.capture {
            for tag in CraftIndex.shotOn(spec).intersection(tagsFound).sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let text = spec.evidence else { continue }
                let claim = CraftIndex.Claim(name: tag.rawValue, kind: "shotOn", text: String(text.prefix(400)), source: spec.source ?? "Wikipedia",
                                             status: .confirmed, since: now, rules: input.rules, article: spec.article)
                if seen.insert(claim.key).inserted { claims.append(claim) }
            }
        }
        for (tag, evidence) in input.shotOn.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let claim = CraftIndex.Claim(name: tag.rawValue, kind: "shotOn", text: evidence.text, source: evidence.source, status: .confirmed,
                                         since: now, rules: input.rules)
            if seen.insert(claim.key).inserted { claims.append(claim) }
        }
        guard let previous else { return claims }
        // 2. Each earlier finding, by its own source.
        for old in earlier(previous) where old.status != .retired {
            let confirmedAgain = claims.firstIndex { $0.status == .confirmed && $0.kind == old.kind && sameName($0.name, old.name) && $0.source == old.source
                && (old.article == nil || $0.article == nil || $0.article == old.article) }
            if let index = confirmedAgain {
                // Confirmed again: keep its history.
                claims[index].since = min(claims[index].since, old.since)
                continue
            }
            let outcome = Self.outcome(of: old, input: input)
            // Confirmed by this reading under another source or name form: already among its findings.
            if outcome.status == .confirmed { continue }
            var settled = old
            settled.status = outcome.status
            settled.reason = outcome.reason
            let unreadArticle = outcome.reason?.hasPrefix("its article on") == true
            settled.misses = old.misses + (outcome.counts && !unreadArticle ? 1 : 0)
            let unreadNow = unreadArticle ? (old.unread ?? 0) + (old.status == .pending ? 0 : 1) : 0
            settled.unread = unreadNow == 0 ? nil : unreadNow
            // A finding with no passage stays as it was recorded until a reading confirms or denies it
            // (1.10.10): not finding it again disproves nothing.
            if outcome.status == .legacy { settled.misses = old.misses }
            // A finding not shown (pending) stays not shown while its source can't be read: an outage
            // never brings back what a full reading couldn't settle.
            if old.status == .pending, outcome.status == .carried {
                settled.status = .pending
                settled.reason = old.reason
            }
            if settled.status == .carried || settled.status == .pending {
                if (settled.unread ?? 0) > 2 * CraftIndex.maxRetries {
                    settled.status = .retired
                    settled.reason = "its article on \(old.site) not read in \(2 * CraftIndex.maxRetries) readings"
                } else if settled.misses > CraftIndex.maxRetries {
                    settled.status = .retired
                    settled.reason = outcome.reason?.hasPrefix("not in what was read") == true
                        ? "no longer in \(old.source) (\(CraftIndex.maxRetries) readings)"
                        : (outcome.reason.map { $0 + "; " } ?? "") + "not settled in \(CraftIndex.maxRetries) readings"
                }
            }
            if seen.insert(settled.key).inserted { claims.append(settled) }
        }
        return claims
    }

    /// An earlier reading's findings: its own (1.10.9 on), or, before, its tags' sentences and its
    /// names (with no passage).
    static func earlier(_ previous: CraftIndex) -> [CraftIndex.Claim] {
        if let claims = previous.claims { return claims }
        var found: [CraftIndex.Claim] = previous.evidence.map {
            CraftIndex.Claim(name: $0.shotOn.rawValue, kind: "shotOn", text: $0.text, source: $0.source, status: .confirmed,
                             since: $0.carriedFrom ?? previous.readAt, rules: $0.carriedRules ?? previous.version)
        }
        for name in previous.names {
            found.append(CraftIndex.Claim(name: name, kind: "name", text: nil, source: "", status: .confirmed,
                                          since: previous.readAt, rules: previous.version))
        }
        return found
    }

    /// What a finding's own source says of it now.
    /// `counts`: whether the reading uses up one of the finding's tries. Only a reading that could have
    /// settled it does: its site answered, its page came whole, and its passage isn't still there
    /// waiting to be read for this film (a passage still on the page is never retired for want of a
    /// settled reading: it stays pending, not shown).
    static func outcome(of old: CraftIndex.Claim, input: Input) -> (status: CraftIndex.Claim.Status, reason: String?, counts: Bool) {
        // A name kept from before 1.10.9 (no passage, no source): a confirmation settles it, and a
        // denial in this reading's own text retires it; nothing else does (1.10.10).
        guard let passage = old.text, !old.source.isEmpty else {
            let named = input.accepted.contains { sameName($0.name, old.name) }
            if named { return (.confirmed, nil, false) }
            if let denial = input.judged.first(where: { sameName($0.name, old.name) && $0.reason == .denied }) {
                return (.retired, denial.reason.label + " (\(denial.source ?? "Wikipedia"))", false)
            }
            return (.legacy, "recorded by rules \(old.rules), before passages were kept; awaiting verification", false)
        }
        // Worked out from Wikidata or TMDB, not read from a page: the new reading's word stands.
        if old.site == "Wikidata" || old.site == "TMDB" {
            return (.retired, "\(old.site) no longer says so", false)
        }
        let paragraphs = input.read[old.source]
        let fetched = input.fetched[old.site] ?? []
        if paragraphs == nil && fetched.isEmpty {
            if input.unanswered.contains(old.site) { return (.carried, "\(old.site) didn't answer", false) }
            // An incomplete page (a shell, an article that couldn't be told apart) is counted, as it
            // is for Shot on tags (`CraftIndex.merging`): a page that never comes whole doesn't keep a
            // finding for good.
            if input.incomplete.contains(old.site) { return (.carried, "\(old.site)'s page came incomplete", true) }
            return (.carried, "\(old.source) wasn't found again", true)
        }
        let text = (paragraphs ?? []) + fetched.flatMap { $0 }
        guard contains(text, passage: passage) else {
            // Read in full and the passage isn't there: the page no longer says it (unless its page
            // came incomplete, which isn't a full reading).
            if input.incomplete.contains(old.site) { return (.carried, "\(old.site)'s page came incomplete", true) }
            // Its own article wasn't read this time (another article of the site was): not a reading of
            // it at all (1.10.10). Carried, and tried again on the retry schedule.
            if let article = old.article, !input.articles.contains(article) {
                // A try used, against a longer allowance (twice `maxRetries`, see `reconcile`): an article
                // dropped from search or re-filed under a new slug isn't kept for ever.
                return (.carried, "its article on \(old.site) wasn't read this time", true)
            }
            // Sources are labelled by site, so another article of the same site may have been read
            // in its place: not shown, and retired only when `CraftIndex.maxRetries` readings in a row
            // don't find it (a reading that finds it again confirms it).
            return (.pending, "not in what was read from \(old.source)", true)
        }
        // The passage is there: what do these rules say of it? For a Shot on tag, only gear in the
        // passage that gives that tag speaks to it ("film" isn't ruled out by a denied Steadicam).
        let tag = old.kind == "shotOn" ? ShotOn(rawValue: old.name) : nil
        let names: (TechSpecs.Kind, String) -> Bool = { kind, name in
            if let tag { return tags(kind, name).contains(tag) }
            return old.kind == kind.rawValue && sameName(name, old.name) || old.kind == "name" && sameName(name, old.name)
        }
        if input.accepted.contains(where: { names($0.kind, $0.name) && samePassage($0.evidence ?? "", passage) && (tag == nil || $0.capture) }) {
            // A tag this reading didn't settle on, though the passage still gives it: kept, not shown.
            if let tag, input.shotOn[tag] == nil {
                return (.pending, "the passage still says it, but this reading's tags don't include it", false)
            }
            return (.confirmed, nil, false)
        }
        if let ruled = input.judged.first(where: { names($0.kind, $0.name) && samePassage($0.evidence, passage) }) {
            // A reason that holds back (too uncertain, a presentation of unknown stage, not enough
            // context) disproves nothing: kept, awaiting verification (1.10.10).
            if ruled.reason.abstains { return (.pending, ruled.reason.label, false) }
            return (.retired, ruled.reason.label, false)
        }
        if let named = input.mentioned.first(where: { names($0.kind, $0.name) && samePassage($0.evidence ?? "", passage) }) {
            if named.attribution == .otherProduction || named.attribution == .rejected || named.attribution == .reference {
                return (.retired, ClaimReason.otherProduction.label, false)
            }
            return (.pending, "read again; not settled whether it's said of this film", false)
        }
        // Present, but not read for this film (its page set aside, the statement not tied to it, or
        // no gear in it gives the tag by these rules).
        return (.pending, "read again; these rules couldn't tie the passage to this film", false)
    }
}
