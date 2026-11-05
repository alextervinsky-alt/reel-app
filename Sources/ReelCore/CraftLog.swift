import Foundation

/// The reading log: for one film, what was read to tag how it was shot, what was left out and
/// why, and the sentence behind each tag and name; then what Reel stored (see `stored`), which is
/// what it shows. Written as plain text to Documents › Reel › Shot On Readings, so any tag can be
/// checked.
public enum CraftLog {
    /// What one reading found. `articleMissing`: Wikipedia answered that the article isn't there.
    public static func text(details: TMDBMovieDetails, articleTitle: String?, articleRead: Bool, articleMissing: Bool = false,
                            reading: CameraReading, specs: TechSpecs, index: CraftIndex, now: Date = Date()) -> String {
        var lines: [String] = []
        let when = ISO8601DateFormatter().string(from: now)
        lines.append("How \(details.title)\(details.year.map { " (\($0))" } ?? "") was shot: read \(when), rules \(CraftIndex.currentVersion)")
        if !details.cinematographers.isEmpty { lines.append("Cinematography: " + details.cinematographers.joined(separator: ", ")) }
        if !details.directors.isEmpty { lines.append("Directed by: " + details.directors.joined(separator: ", ")) }

        if let discovery = reading.discovery {
            lines.append("")
            lines.append("DISCOVERY (how pages were found; what was read is under READ, what wasn't under NOT READ)")
            lines += discovery.lines()
        }

        lines.append("")
        lines.append("READ")
        for source in reading.sources {
            let roundup = specs.roundups.contains(source.site) ? "  [about many films: read only where it names this one]"
                : source.context.map { $0.aboutFilm ? "" : "  [\($0.kind.label): read only where it's about this film, \($0.anchored) statements]" } ?? ""
            lines.append("• \(source.site): \(source.title) (\(source.paragraphs.count) paragraphs)\(roundup)")
            lines.append("  \(source.url.absoluteString)" + provenance(source))
        }
        if let articleTitle {
            lines.append(articleRead ? "• Wikipedia: \(articleTitle)"
                         : articleMissing ? "• Wikipedia: \(articleTitle) — no such article now" : "• Wikipedia: \(articleTitle) — couldn't be reached")
        } else {
            lines.append("• Wikipedia: no article found for the film")
        }
        if let person = reading.cinematographer {
            lines.append("• Wikipedia: \(person.name) (\(person.aboutThisFilm.count) paragraphs about this film)")
        }
        if !reading.skipped.isEmpty {
            lines.append("")
            lines.append("NOT READ")
            for skipped in reading.skipped {
                lines.append("• \(skipped.source.site): \(skipped.source.title) — \(skipped.reason)")
                lines.append("  \(skipped.source.url.absoluteString)" + provenance(skipped.source))
            }
        }
        if !index.unanswered.isEmpty {
            lines.append("")
            lines.append("DIDN'T ANSWER (read again later): " + index.unanswered.joined(separator: ", "))
        }

        lines.append("")
        lines.append("SHOT ON, IN THIS READING")
        if index.shotOn.isEmpty { lines.append("• nothing said") }
        for kind in index.shotOn {
            let why = index.evidence(for: kind)
            lines.append("• \(index.label(for: kind))" + (why.map { " — \($0.source): “\($0.text)”" } ?? ""))
        }

        lines.append("")
        lines.append("THIS FILM'S GEAR AND TECHNIQUES")
        if specs.specs.isEmpty { lines.append("• none named") }
        for spec in specs.specs {
            let also = spec.support.dropFirst()
            lines.append("• \(spec.kind.rawValue): \(spec.name)\(spec.partial ? " (in part)" : "")" + said(spec)
                         + (also.isEmpty ? "" : " (also said by " + also.joined(separator: ", ") + ")"))
        }
        if !specs.mentioned.isEmpty {
            lines.append("")
            lines.append("NAMED, BUT NOT THIS FILM'S")
            for spec in specs.mentioned {
                let why = spec.aboutThisFilm ? "not said to be what it was shot with" : "about other work, another film or gear in general"
                lines.append("• \(spec.kind.rawValue): \(spec.name) — \(why)" + said(spec))
            }
        }
        if !specs.judged.isEmpty {
            // What each statement set aside says of the gear (1.10.9, `ClaimFrame`), once per name and reason.
            lines.append("")
            lines.append("SET ASIDE (what the statement says of it)")
            var shown = Set<String>()
            for judged in specs.judged where shown.insert(judged.name.lowercased() + "|" + judged.reason.rawValue + "|" + String(judged.evidence.prefix(60))).inserted {
                lines.append("• \(judged.kind.rawValue): \(judged.name) — \(judged.reason.label): \(judged.source ?? "Wikipedia"): “\(judged.evidence.prefix(240))”")
            }
        }
        let earlier = index.claimsKnown.filter { $0.status != .confirmed }
        if !earlier.isEmpty {
            // What became of the reading before's findings (1.10.9, `SourceReconciliation`).
            lines.append("")
            lines.append("EARLIER FINDINGS, READ AGAIN")
            for claim in earlier {
                let what = claim.kind == "shotOn" ? "Shot on " + (ShotOn(rawValue: claim.name)?.title ?? claim.name) : claim.name
                let status: String
                switch claim.status {
                case .carried: status = "carried (source not read again)"
                case .pending: status = "pending reassessment (kept, not shown as found)"
                case .retired: status = "retired"
                case .confirmed: status = "confirmed"
                }
                let from = claim.source.isEmpty ? "found by rules \(claim.rules), no passage kept" : "\(claim.source)"
                lines.append("• \(what) — \(status): \(claim.reason ?? "") — \(from)" + (claim.text.map { ": “\($0.prefix(200))”" } ?? ""))
            }
        }
        lines += research(reading: reading, specs: specs, index: index)
        return lines.joined(separator: "\n") + "\n"
    }

    /// RESEARCH and CRAFT OBSERVATIONS (1.10.7): who photographed it and in which part, what the
    /// first pass was missing and the searches made for it, where each dimension stands, and what
    /// was said of how it was shot, each with its kind of source, whose words and which part.
    static func research(reading: CameraReading, specs: TechSpecs, index: CraftIndex) -> [String] {
        var lines = ["", "RESEARCH (who photographed it, what was missing, where Reel looked)"]
        if let run = reading.research {
            lines.append("• Crew: " + (run.contributors.isEmpty ? "none known beyond the credits above"
                : run.contributors.map { $0.described + ($0.scope.map { " (\($0.label))" } ?? "") }.joined(separator: "; ")))
            lines.append("• Missing after the first pass: " + (run.missing.isEmpty ? "nothing" : run.missing.map(\.title).joined(separator: ", ")))
            let questions = run.open.compactMap(ResearchQuestions.question)
            if !questions.isEmpty {
                lines.append("• Open questions: " + questions.map { "\($0.purpose) (\($0.dimension.title))" }.joined(separator: "; "))
            }
            for passed in run.passed {
                lines.append("• Not read: \(passed.url) — names the film only in passing (\(passed.why))")
            }
            if run.outcomes.isEmpty, !run.missing.isEmpty, run.quiet.isEmpty {
                lines.append("• No further search: none planned (no crew member to search by, and no search for it)")
            }
            let day = ISO8601DateFormatter()
            day.formatOptions = [.withFullDate]
            for entry in run.quiet {
                lines.append("• Not searched again: \(entry.dimension.title) — searched \(entry.searchedAt.map { day.string(from: $0) } ?? "earlier")"
                             + " with nothing found (again after a year)")
            }
            for outcome in run.outcomes {
                let query = outcome.query
                let what = ([query.dimension] + query.also).map(\.title).joined(separator: ", ")
                var line = "• Searched \(query.site) for “\(query.text)” (\(what)): "
                switch outcome.result {
                case .notTried(let why): line = "• Not searched: \(query.site) for “\(query.text)” (\(what)) — \(why)"
                case .unavailable(let why): line += why
                case .noCandidate(let count): line += count == 0 ? "no results" : "\(count) results; none names the film" + (query.contributor == nil ? "" : " or the person")
                case .nothingUsable(let pages): line += "asked for \(pages.count), none about the film (see NOT READ)"
                case .pageUnavailable(let pages): line += "asked for \(pages.count); a page didn't answer (searched again later; see NOT READ)"
                case .pageLanguage(let pages): line += "asked for \(pages.count); a page is in a language Reel doesn't read (see NOT READ)"
                case .pageUnreadable(let pages): line += "asked for \(pages.count); a page couldn't be read (see NOT READ)"
                case .read(let pages): line += "read " + pages.joined(separator: ", ")
                }
                lines.append(line)
            }
        } else {
            lines.append("• Not researched beyond the first pass")
        }
        if let research = index.research {
            lines.append("• Where it stands: " + research.map { entry in
                let open = entry.open.compactMap(ResearchQuestions.question).map(\.purpose)
                return "\(entry.dimension.title) — \(entry.state.label)" + (open.isEmpty || entry.state == .notSearched ? "" : " (open: " + open.joined(separator: ", ") + ")")
            }.joined(separator: "; "))
        }
        let groups: [(String, [TechSpecs.Note])] = [
            ("In their own words", specs.approach), ("The visual idea", specs.intent), ("Light", specs.lighting),
            ("Frame and movement", specs.cameraLanguage), ("Colour", specs.colour), ("Camera and VFX", specs.cameraVFX),
            ("A scene", specs.scenes), ("A challenge", specs.challenges),
        ]
        let observed = groups.filter { !$0.1.isEmpty }
        lines.append("")
        lines.append("CRAFT OBSERVATIONS (what was said of how it was shot; the kind of source, whose words, which part)")
        if observed.isEmpty { lines.append("• none") }
        for (title, notes) in observed {
            for note in notes.prefix(4) {
                var about = [note.source ?? "Wikipedia"]
                if let evidence = note.evidence { about.append(evidence.label) }
                if let speaker = note.speaker { about.append(speaker.described) }
                if let scope = note.scope { about.append(scope.label) }
                lines.append("• \(title) — \(about.joined(separator: "; ")): “\(note.text.prefix(300))”")
            }
        }
        return lines
    }

    /// What Reel stored after the reading (see `CraftIndex.merge`), which is what it shows: each tag
    /// and whether this reading found it or it was carried over from an earlier one (when, and from
    /// where), the tags dropped and why, and whether the reading is complete.
    public static func stored(_ merged: CraftIndex.Merged) -> String {
        let index = merged.index
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        var lines = ["", "STORED IN REEL"]
        if index.shotOn.isEmpty { lines.append("• no Shot on") }
        for kind in index.shotOn {
            guard let why = index.evidence(for: kind) else { continue }
            if let from = why.carriedFrom {
                let unbounded = index.limits.contains { $0.site == why.site && $0.detail.contains(CameraSources.unboundedArticle) }
                let how = index.unanswered.contains(why.site) ? "\(why.site) didn't answer this time"
                    : unbounded ? "its article couldn't be told apart on \(why.site)'s page this time" : "its page wasn't read this time"
                lines.append("• \(index.label(for: kind)) — carried from the reading of \(day.string(from: from)) (rules \(why.carriedRules ?? index.version)), "
                             + "\(how): \(why.source): “\(why.text.prefix(300))”")
            } else {
                lines.append("• \(index.label(for: kind)) — found in this reading: \(why.source): “\(why.text.prefix(300))”")
            }
        }
        for dropped in merged.dropped {
            lines.append("• dropped: \(dropped.shotOn.title) — \(dropped.reason)")
        }
        let next = index.retryAt.map { " Read again automatically after \(day.string(from: $0))." } ?? ""
        // Pages found and not examined, by why (each is named under NOT READ).
        let unread = index.limits.filter { !$0.kind.retried }
        let counts = Dictionary(grouping: unread, by: \.detail).sorted { $0.key < $1.key }.map { "\($0.value.count) \($0.key)" }
        let limited = unread.isEmpty ? "" : " \(unread.count) page\(unread.count == 1 ? "" : "s") found couldn't be examined: " + counts.joined(separator: "; ") + "."
        switch index.coverage {
        case .partial where !index.unanswered.isEmpty:
            lines.append("Incomplete: \(index.unanswered.joined(separator: ", ")) didn't answer.\(next)\(limited)")
        case .partial:
            lines.append("Incomplete: tags carried over from an earlier reading.\(next)\(limited)")
        case .limited:
            lines.append("Complete, with limits:\(limited) Not tried again until the film is next read (rules \(index.version)).")
        case .full:
            lines.append("Complete: no page found failed to load or was too thin to read; pages left out on purpose (another film's, another craft's, more than the six read, another address of an article) are under NOT READ (rules \(index.version)).")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "(cited as http://…; the site sent Reel to https://…)".
    private static func provenance(_ source: CameraReading.Source) -> String {
        var notes: [String] = []
        if let cited = source.cited { notes.append("cited as " + cited.absoluteString) }
        if let landed = source.landed { notes.append("the site sent Reel to " + landed.absoluteString) }
        // How its article was told apart from the rest of the page (a plain page of paragraphs,
        // nothing left out, says nothing).
        if let boundary = source.boundary, boundary != .region || source.leftOut > 0 {
            var how = "article found by " + boundary.rawValue
            if source.leftOut > 0 {
                how += source.leftOut == 1 ? "; 1 paragraph on the page left out as not the article's"
                    : "; \(source.leftOut) paragraphs on the page left out as not the article's"
            }
            notes.append(how)
        }
        // The address the page gives for itself, when it isn't the one read (or landed on).
        if let canonical = source.canonical {
            func same(_ a: URL, _ b: URL) -> Bool {
                func key(_ u: URL) -> String { (u.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "") + u.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
                return key(a) == key(b)
            }
            if !same(canonical, source.url), source.landed.map({ !same(canonical, $0) }) ?? true {
                notes.append("the page gives its address as " + canonical.absoluteString)
            }
        }
        return notes.isEmpty ? "" : "  (" + notes.joined(separator: "; ") + ")"
    }

    private static func said(_ spec: TechSpecs.Spec) -> String {
        guard let evidence = spec.evidence, !spec.isFixedName || evidence != spec.name else { return "" }
        return " — \(spec.source ?? "Wikipedia"): “\(evidence.prefix(300))”"
    }

    /// "Dune Part Two (2024) 693134.txt": the file's name, safe on any disk.
    public static func fileName(for details: TMDBMovieDetails) -> String {
        let title = details.title.map { "/:\\\0".contains($0) ? " " : $0 }
        let cleaned = String(title).split(separator: " ").joined(separator: " ")
        return "\(cleaned)\(details.year.map { " (\($0))" } ?? "") \(details.id).txt"
    }
}
