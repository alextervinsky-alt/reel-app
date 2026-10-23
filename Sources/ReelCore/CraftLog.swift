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

        lines.append("")
        lines.append("READ")
        for source in reading.sources {
            let roundup = specs.roundups.contains(source.site) ? "  [about many films: read only where it names this one]" : ""
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
            lines.append("• \(spec.kind.rawValue): \(spec.name)\(spec.partial ? " (in part)" : "")" + said(spec))
        }
        if !specs.mentioned.isEmpty {
            lines.append("")
            lines.append("NAMED, BUT NOT THIS FILM'S")
            for spec in specs.mentioned {
                let why = spec.aboutThisFilm ? "not said to be what it was shot with" : "about other work, another film or gear in general"
                lines.append("• \(spec.kind.rawValue): \(spec.name) — \(why)" + said(spec))
            }
        }
        return lines.joined(separator: "\n") + "\n"
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
                let how = index.unanswered.contains(why.site) ? "\(why.site) didn't answer this time" : "its page wasn't read this time"
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
        if !index.unanswered.isEmpty {
            lines.append("Incomplete: \(index.unanswered.joined(separator: ", ")) didn't answer.\(next)")
        } else if index.isPartial {
            lines.append("Incomplete: tags carried over from an earlier reading.\(next)")
        } else {
            lines.append("Complete: every source answered (rules \(index.version)).")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "(cited as http://…; the site sent Reel to https://…)".
    private static func provenance(_ source: CameraReading.Source) -> String {
        var notes: [String] = []
        if let cited = source.cited { notes.append("cited as " + cited.absoluteString) }
        if let landed = source.landed { notes.append("the site sent Reel to " + landed.absoluteString) }
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
