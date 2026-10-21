import Foundation

/// The reading log: for one film, what was read to tag how it was shot, what was left out and
/// why, and the sentence behind each tag and name. Written as plain text to
/// Documents › Reel › Shot On Readings, so any tag can be checked.
public enum CraftLog {
    public static func text(details: TMDBMovieDetails, articleTitle: String?, articleRead: Bool, reading: CameraReading,
                            specs: TechSpecs, index: CraftIndex, now: Date = Date()) -> String {
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
            lines.append("  \(source.url.absoluteString)")
        }
        if let articleTitle {
            lines.append(articleRead ? "• Wikipedia: \(articleTitle)" : "• Wikipedia: \(articleTitle) — couldn't be reached")
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
                lines.append("  \(skipped.source.url.absoluteString)")
            }
        }
        if !index.unanswered.isEmpty {
            lines.append("")
            lines.append("DIDN'T ANSWER (read again later): " + index.unanswered.joined(separator: ", "))
        }

        lines.append("")
        lines.append("SHOT ON")
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
