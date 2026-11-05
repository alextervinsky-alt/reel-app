import Foundation

// MARK: - Earlier findings, read again (1.10.9)

extension CraftIndex {
    /// One finding and the passage it stands on: a gear name ("Technocrane") or a Shot on tag
    /// ("film"), where it was read and what became of it. A reading keeps every finding it confirmed,
    /// and every earlier one it couldn't settle, so a reading by newer rules that fails to find an
    /// earlier statement never silently drops it (`SourceReconciliation`).
    public struct Claim: Codable, Equatable, Sendable {
        public enum Status: String, Codable, Sendable, CaseIterable {
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

        public init(name: String, kind: String, text: String?, source: String, status: Status, reason: String? = nil,
                    since: Date, rules: Int, misses: Int = 0) {
            self.name = name
            self.kind = kind
            self.text = text
            self.source = source
            self.status = status
            self.reason = reason
            self.since = since
            self.rules = rules
            self.misses = misses
        }

        /// What makes two findings the same: the name (by its canonical form) and the source.
        var key: String { kind + "|" + TitleMatch.key(name) + "|" + source }
        var site: String { CraftIndex.site(of: source) }
        /// Shown as found: confirmed now, or carried while its source can't be read.
        public var supports: Bool { status == .confirmed || status == .carried }
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

    static func sameName(_ a: String, _ b: String) -> Bool {
        let x = squash(a), y = squash(b)
        return !x.isEmpty && !y.isEmpty && (x == y || x.contains(y) && y.count >= 4 || y.contains(x) && x.count >= 4)
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
                                         source: spec.source ?? "Wikipedia", status: .confirmed, since: now, rules: input.rules)
            if seen.insert(claim.key).inserted { claims.append(claim) }
        }
        for (tag, evidence) in input.shotOn.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let claim = CraftIndex.Claim(name: tag.rawValue, kind: "shotOn", text: evidence.text, source: evidence.source, status: .confirmed,
                                         since: now, rules: input.rules)
            if seen.insert(claim.key).inserted { claims.append(claim) }
        }
        guard let previous else { return claims }
        // 2. Each earlier finding, by its own source.
        for old in earlier(previous) where old.status != .retired {
            let confirmedAgain = claims.firstIndex { $0.status == .confirmed && $0.kind == old.kind && sameName($0.name, old.name) && $0.source == old.source }
            if let index = confirmedAgain {
                // Confirmed again: keep its history.
                claims[index].since = min(claims[index].since, old.since)
                continue
            }
            let outcome = Self.outcome(of: old, input: input)
            // Confirmed by this reading under another source or name form: already among its findings.
            if outcome.status == .confirmed { continue }
            var settled = old
            settled.misses = old.misses + 1
            settled.status = outcome.status
            settled.reason = outcome.reason
            if outcome.status == .carried || outcome.status == .pending {
                // Counted only while its source answers: a site that's down doesn't use up a try.
                if outcome.status == .carried, input.unanswered.contains(old.site) { settled.misses = old.misses }
                if settled.misses > CraftIndex.maxRetries {
                    settled.status = .retired
                    settled.reason = (outcome.reason.map { $0 + "; " } ?? "") + "not settled in \(CraftIndex.maxRetries) readings"
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
    static func outcome(of old: CraftIndex.Claim, input: Input) -> (status: CraftIndex.Claim.Status, reason: String?) {
        // A name kept from before 1.10.9 (no passage, no source): only a confirmation settles it.
        guard let passage = old.text, !old.source.isEmpty else {
            let named = input.accepted.contains { sameName($0.name, old.name) }
            return named ? (.confirmed, nil) : (.pending, "found by rules \(old.rules); no passage was kept to read again")
        }
        // Worked out from Wikidata or TMDB, not read from a page: the new reading's word stands.
        if old.site == "Wikidata" || old.site == "TMDB" {
            return (.retired, "\(old.site) no longer says so")
        }
        let paragraphs = input.read[old.source]
        let fetched = input.fetched[old.site] ?? []
        if paragraphs == nil && fetched.isEmpty {
            if input.unanswered.contains(old.site) { return (.carried, "\(old.site) didn't answer") }
            if input.incomplete.contains(old.site) { return (.carried, "\(old.site)'s page came incomplete") }
            return (.carried, "\(old.source) wasn't found again")
        }
        let text = (paragraphs ?? []) + fetched.flatMap { $0 }
        guard contains(text, passage: passage) else {
            // Read in full and the passage isn't there: the page no longer says it (unless its page
            // came incomplete, which isn't a full reading).
            if input.incomplete.contains(old.site) { return (.carried, "\(old.site)'s page came incomplete") }
            return (.retired, "no longer in \(old.source)")
        }
        // The passage is there: what do these rules say of it?
        let names: (String) -> Bool = { old.kind == "shotOn" ? true : sameName($0, old.name) }
        if let ruled = input.judged.first(where: { names($0.name) && samePassage($0.evidence, passage) }) {
            return (.retired, ruled.reason.label)
        }
        if let named = input.mentioned.first(where: { names($0.name) && samePassage($0.evidence ?? "", passage) }) {
            if named.attribution == .otherProduction || named.attribution == .rejected || named.attribution == .reference {
                return (.retired, ClaimReason.otherProduction.label)
            }
            return (.pending, "read again; not settled whether it's said of this film")
        }
        if old.kind == "shotOn", input.accepted.contains(where: { samePassage($0.evidence ?? "", passage) && $0.capture }) {
            // The sentence is still accepted (for other gear): only the tag it gave isn't, by these rules.
            return (.retired, "the sentence no longer says it was shot that way")
        }
        if input.accepted.contains(where: { names($0.name) && samePassage($0.evidence ?? "", passage) }) {
            return (.confirmed, nil)
        }
        // Present, but not read for this film (its page set aside, or the statement not tied to it).
        return (.pending, "read again; these rules couldn't tie the passage to this film")
    }
}
