import XCTest
@testable import ReelCore

/// The independent claim holdout (1.10.9): 30 invented films, their pages and searches, and 299
/// statements each labelled accept, reject or abstain for the film being read, written by a separate
/// author who saw neither Reel's code nor its other corpora (`Fixtures/claim-holdout.json`; the
/// author's generator, validator and notes are in `Fixtures/claim-holdout-source`). Every film is read
/// through the production path (`ResearchEngine.run`, `CraftReader`, `TechSpecs.read`) and each
/// labelled passage checked: was the term accepted for the film from that passage?
final class ClaimHoldoutTests: XCTestCase {
    struct File: Decodable {
        struct Film: Decodable {
            struct Member: Decodable { let job: String; let name: String }
            let id: Int, title: String, year: Int, director: String
            let crew: [Member]
            let article: [String]
            let firstPass: [String]
        }
        struct Page: Decodable { let url: String, site: String, title: String; let paragraphs: [String]; let failure: String? }
        struct Hit: Decodable { let title: String, url: String }
        struct Search: Decodable { let provider: String, query: String; let hits: [Hit] }
        struct Claim: Decodable {
            let id: String, film: String, source: String, passage: String, term: String, property: String, expected: String
            let aboutFilm: String, evidenceType: String
        }
        let films: [Film]
        let pages: [Page]
        let searches: [Search]
        let claims: [Claim]
    }

    static func load() throws -> File {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/claim-holdout.json")
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }

    /// The file as the benchmark's corpus (claims labelled with the production they establish gear for).
    static func corpus(_ file: File) -> BenchCorpus {
        var pages: [String: BenchPage] = [:]
        for page in file.pages {
            let claims = file.claims.filter { $0.source == page.url && $0.expected == "accept" }
                .map { BenchClaim(text: $0.passage, film: $0.film, gear: [$0.term]) }
            pages[page.url] = BenchPage(title: page.title, url: page.url, site: page.site, paragraphs: page.paragraphs, claims: claims,
                                        failure: page.failure == nil ? nil : .unanswered("didn't answer"))
        }
        let films = file.films.map { film -> BenchFilm in
            var bench = BenchFilm(id: film.id, title: film.title, year: film.year, director: film.director,
                                  crew: film.crew.map { ($0.job, $0.name) })
            bench.article = film.article
            bench.articleClaims = file.claims.filter { $0.source == "article:" + film.title && $0.expected == "accept" }
                .map { BenchClaim(text: $0.passage, film: $0.film, gear: [$0.term]) }
            bench.firstPass = film.firstPass
            return bench
        }
        let searches = file.searches.map { BenchSearch(provider: $0.provider, query: $0.query, hits: $0.hits.map { ($0.title, $0.url) }) }
        return BenchCorpus(name: "claim holdout", films: films, pages: pages, searches: searches)
    }

    static func squash(_ text: String) -> String {
        TitleMatch.fold(text).filter { $0.isLetter || $0.isNumber }
    }

    struct Score: CustomStringConvertible {
        var accept = 0, truePositive = 0, falseNegative = 0, unreached = 0
        var reject = 0, trueNegative = 0, falsePositive = 0, crossFilm = 0
        var abstain = 0, abstained = 0, unsafe = 0
        var byType: [String: (right: Int, total: Int)] = [:]
        var errors: [String] = []
        var precision: Double { truePositive + falsePositive == 0 ? 1 : Double(truePositive) / Double(truePositive + falsePositive) }
        var recall: Double { accept == 0 ? 1 : Double(truePositive) / Double(accept) }
        var description: String {
            String(format: "accept %d: accepted %d, missed %d (of them unreached %d) | reject %d: rejected %d, wrongly accepted %d (cross-film %d) | abstain %d: held back %d, accepted %d | precision %.3f, recall %.3f, rejection %.3f",
                   accept, truePositive, falseNegative, unreached, reject, trueNegative, falsePositive, crossFilm, abstain, abstained, unsafe,
                   precision, recall, reject == 0 ? 1 : Double(trueNegative) / Double(reject))
        }
    }

    func say(_ line: String) { FileHandle.standardOutput.write(Data(("BENCH| " + line + "\n").utf8)) }

    func testTheIndependentClaimHoldout() async throws {
        let file = try Self.load()
        XCTAssertEqual(file.films.count, 30)
        XCTAssertEqual(file.claims.count, 299)
        let corpus = Self.corpus(file)
        var score = Score()
        for film in corpus.films {
            let transport = ResearchBenchmarkTests.Transport(corpus)
            let details = ResearchBenchmarkTests.details(film), article = ResearchBenchmarkTests.article(film)
            let people = details.cinematographers + details.directors
            let first = film.firstPass.compactMap { url -> CameraReading.Source? in
                guard let page = corpus.pages[url], page.failure == nil, let address = URL(string: url) else { return nil }
                return CameraSources.judged(CameraReading.Source(title: page.title, site: page.site, url: address, paragraphs: page.paragraphs),
                                            filmTitle: film.title, otherTitles: [], people: people, year: film.year)
            }
            let base = CameraReading(sources: first, more: [], cinematographer: nil)
            let crew = CraftReader.crew(of: details, article: article, reading: base)
            let researched = await ResearchEngine.run(base, article: article, filmTitle: film.title, cinematographers: details.cinematographers,
                                                      directors: details.directors, year: film.year, otherTitles: [], crew: crew,
                                                      previous: nil, transport: transport, now: ResearchBenchmarkTests.now)
            let texts = CraftReader.texts(article: article, reading: researched, hiding: false)
            let specs = TechSpecs.read(texts: texts, cinematographers: details.cinematographers, directors: details.directors,
                                       year: film.year, title: film.title, otherTitles: [], crew: crew)
            let read = Set(researched.sources.map(\.url.absoluteString) + (article == nil ? [] : ["article:" + film.title]))
            for claim in file.claims where claim.film == film.title {
                let term = Self.squash(claim.term)
                let passage = Self.squash(String(claim.passage.prefix(90)))
                let accepted = specs.accepted.contains { spec in
                    let name = Self.squash(spec.name)
                    let evidence = Self.squash(spec.evidence ?? "")
                    return (name.contains(term) || term.contains(name)) && !name.isEmpty
                        && (evidence.contains(passage) || passage.contains(String(evidence.prefix(60))))
                }
                let tag = claim.evidenceType
                var right = false
                switch claim.expected {
                case "accept":
                    score.accept += 1
                    if accepted { score.truePositive += 1; right = true } else {
                        score.falseNegative += 1
                        if !read.contains(claim.source) { score.unreached += 1 }
                        score.errors.append("MISS \(claim.id) [\(tag)] \(film.title) ← \(claim.term): \(claim.passage.prefix(110))")
                    }
                case "reject":
                    score.reject += 1
                    if accepted {
                        score.falsePositive += 1
                        if !claim.aboutFilm.isEmpty && claim.aboutFilm != film.title { score.crossFilm += 1 }
                        score.errors.append("WRONG \(claim.id) [\(tag)] \(film.title) ← \(claim.term): \(claim.passage.prefix(110))")
                    } else { score.trueNegative += 1; right = true }
                default:
                    score.abstain += 1
                    if accepted {
                        score.unsafe += 1
                        score.errors.append("ABSTAIN-ACCEPTED \(claim.id) [\(tag)] \(film.title) ← \(claim.term): \(claim.passage.prefix(110))")
                    } else { score.abstained += 1; right = true }
                }
                var entry = score.byType[tag] ?? (0, 0)
                entry.total += 1
                if right { entry.right += 1 }
                score.byType[tag] = entry
            }
        }
        say("claim holdout, 1.10.9: \(score)")
        say("claim holdout by type: " + score.byType.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.right)/\($0.value.total)" }.joined(separator: ", "))
        for error in score.errors { say("claim holdout " + error) }
        // Measured, not tuned to: zero cross-film contamination on labelled cases is required.
        XCTAssertEqual(score.crossFilm, 0, "cross-film contamination in the claim holdout")
    }
}
