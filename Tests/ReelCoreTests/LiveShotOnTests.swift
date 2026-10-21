import XCTest
@testable import ReelCore

/// Live, run with the TMDB check (not offline): Shot on for well-known films whose answers are on
/// record, read from the real sources the way the app reads them. A tag a film shouldn't have is
/// reported with its sentence; a tag it should have and lacks is reported with the sentences that
/// named it but didn't say it was shot that way. It never fails a build (the sites change and
/// refuse): the reports are what's checked. CI reads one film per run (SHOTON_FILM), so a crash in
/// Linux's networking costs one film, not the rest.
final class LiveShotOnTests: XCTestCase {
    private struct Known {
        let title: String
        let year: Int
        /// Tags it must have, and tags it must not.
        let has: Set<ShotOn>
        let hasNot: Set<ShotOn>
        /// Tags it may have only as "in part" (one IMAX shot, black-and-white storylines).
        var partOnly: Set<ShotOn> = []
    }

    private let films: [Known] = [
        Known(title: "Oppenheimer", year: 2023, has: [.film, .imax], hasNot: [.digital, .anamorphic], partOnly: [.blackAndWhite]),
        Known(title: "Interstellar", year: 2014, has: [.film, .imax, .anamorphic], hasNot: [.digital]),
        Known(title: "The Prestige", year: 2006, has: [.film], hasNot: [.digital], partOnly: [.imax]),
        Known(title: "The Dark Knight", year: 2008, has: [.film, .imax], hasNot: [.digital]),
        Known(title: "Inception", year: 2010, has: [.film, .anamorphic], hasNot: [.imax]),
        Known(title: "The Matrix", year: 1999, has: [.film], hasNot: [.digital, .anamorphic]),
        Known(title: "No Country for Old Men", year: 2007, has: [.film], hasNot: [.digital]),
        Known(title: "La La Land", year: 2016, has: [.film, .anamorphic], hasNot: [.digital]),
        Known(title: "The Lighthouse", year: 2019, has: [.film, .blackAndWhite], hasNot: [.digital]),
        Known(title: "Lawrence of Arabia", year: 1962, has: [.film], hasNot: [.digital]),
        Known(title: "Jaws", year: 1975, has: [.film], hasNot: [.digital]),
        Known(title: "Saltburn", year: 2023, has: [.film], hasNot: [.digital, .anamorphic]),
        Known(title: "Roma", year: 2018, has: [.digital, .blackAndWhite], hasNot: [.film]),
        Known(title: "Ex Machina", year: 2015, has: [.digital], hasNot: [.film]),
        Known(title: "Blade Runner 2049", year: 2017, has: [.digital], hasNot: [.film]),
        Known(title: "Arrival", year: 2016, has: [.digital], hasNot: [.film]),
        Known(title: "Dune", year: 2021, has: [.digital, .imax], hasNot: [.film]),
        Known(title: "Mad Max: Fury Road", year: 2015, has: [.digital], hasNot: [.film]),
        Known(title: "Prisoners", year: 2013, has: [.digital], hasNot: [.film]),
        Known(title: "Sicario", year: 2015, has: [.digital], hasNot: [.film]),
        Known(title: "Skyfall", year: 2012, has: [.digital], hasNot: [.film]),
        Known(title: "1917", year: 2019, has: [.digital], hasNot: [.film]),
        Known(title: "Joker", year: 2019, has: [.digital], hasNot: [.film]),
        Known(title: "The Revenant", year: 2015, has: [.digital], hasNot: [.film]),
        Known(title: "The Substance", year: 2024, has: [.digital], hasNot: [.film]),
        Known(title: "Parasite", year: 2019, has: [.digital], hasNot: [.film]),
    ]

    func testShotOnForFilmsOnRecord() async throws {
        guard let token = ProcessInfo.processInfo.environment["TMDB_TOKEN"], !token.isEmpty else {
            throw XCTSkip("TMDB_TOKEN not set")
        }
        let client = TMDBClient(token: token)
        // Written as soon as it's known (unbuffered), for CI to sum up.
        func say(_ line: String) { FileHandle.standardOutput.write(Data((line + "\n").utf8)) }
        let chosen = ProcessInfo.processInfo.environment["SHOTON_FILM"].flatMap(Int.init)
        let reading = chosen.map { films.indices.contains($0) ? [films[$0]] : [] } ?? films
        for known in reading {
            guard let id = try? await client.searchMovies(query: known.title, year: known.year).first?.id,
                  let details = try? await client.movieDetails(id: id) else {
                say("Shot on: \(known.title) | not found on TMDB")
                continue
            }
            let facts = try? await WikipediaClient().findings(imdbID: details.imdbID, title: details.title, year: details.year).funFacts
            var others: [String] = []
            if let collection = details.collection, let set = try? await client.collection(id: collection.id) {
                others = set.parts.filter { $0.id != details.id }.map(\.title)
            }
            // Read as CraftReader reads it, keeping what was read to say why a tag is missing.
            async let fetched = CameraSourcesClient().read(articleTitle: facts?.articleTitle, filmTitle: details.title,
                                                           cinematographers: details.cinematographers, directors: details.directors,
                                                           year: details.year, otherTitles: others)
            var article: FilmArticle?
            if let title = facts?.articleTitle { article = try? await WikipediaClient().article(title: title) }
            let texts = CraftReader.texts(article: article, reading: await fetched, hiding: false)
            let specs = TechSpecs.read(texts: texts, cinematographers: details.cinematographers, directors: details.directors,
                                       year: details.year, title: details.title, otherTitles: others)
            let craft = CraftIndex.make(from: specs, colour: facts?.quick?.colour, keywords: details.keywordNames, sources: texts.count)
            let tags = craft.shotOn.map { craft.label(for: $0) }.joined(separator: ", ")
            var wrong: [String] = [], missing: [String] = []
            for tag in ShotOn.allCases where craft.shotOn.contains(tag) {
                let wholeWhenPart = known.partOnly.contains(tag) && craft.evidence(for: tag)?.partial != true
                guard known.hasNot.contains(tag) || wholeWhenPart else { continue }
                wrong.append(tag.title + (wholeWhenPart ? " (whole)" : ""))
                let why = craft.evidence(for: tag).map { "\($0.source): \($0.text.prefix(220))" } ?? ""
                say("::warning::Shot on wrong: \(known.title) is not \(craft.label(for: tag)): \(why)")
            }
            for tag in ShotOn.allCases where known.has.contains(tag) && !craft.shotOn.contains(tag) {
                missing.append(tag.title)
                // What named it without saying it was shot that way.
                for spec in specs.mentioned where CraftIndex.shotOn(spec).contains(tag) {
                    say("Shot on not counted: \(known.title) \(tag.title): \(spec.source ?? "Wikipedia"): \((spec.evidence ?? spec.name).prefix(140))")
                }
                // Sentences that name it at all, when none was read as a name (left out entirely).
                if !(specs.specs + specs.mentioned).contains(where: { CraftIndex.shotOn($0).contains(tag) }) {
                    let words = tag == .digital ? #"(?i)\balexa|\bred\b|\bvenice\b|\bdigital"#
                        : tag == .film ? #"(?i)\b(?:35|65|16)\s?mm|film stock|kodak|celluloid|panavision|\bon film\b"#
                        : tag == .anamorphic ? #"(?i)anamorphic"# : tag == .imax ? #"(?i)imax"# : #"(?i)black[- ]and[- ]white"#
                    let named = texts.flatMap { text in text.sections.flatMap(\.paragraphs).flatMap { Digest.sentences(in: $0) }.map { (text.source ?? "Wikipedia", $0) } }
                        .filter { $0.1.range(of: words, options: .regularExpression) != nil }
                    for (source, sentence) in named.prefix(2) {
                        say("Shot on not counted: \(known.title) \(tag.title) (left out): \(source): \(sentence.prefix(140))")
                    }
                }
            }
            // The sheet's cameras and formats that say what it wasn't shot on ("Red Epic" for a film shot on film).
            let wrongNames = specs.specs.filter { !CraftIndex.shotOn($0).isDisjoint(with: known.hasNot) }.map(\.name)
            say("Shot on: \(known.title) | \(tags.isEmpty ? "nothing" : tags) | \(texts.count) texts | \(specs.specs.count) names"
                + (wrongNames.isEmpty ? "" : " (not its: \(wrongNames.joined(separator: ", ")))")
                + " | known \(known.has.count + known.hasNot.count)"
                + " | wrong \(wrong.joined(separator: "+")) | missing \(missing.joined(separator: "+"))")
        }
    }
}
