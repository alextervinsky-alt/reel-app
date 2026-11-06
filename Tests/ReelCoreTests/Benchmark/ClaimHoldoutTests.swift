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
            enum Keys: String, CodingKey { case id, title, year, director, crew, article, firstPass }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Keys.self)
                id = try c.decode(Int.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
                year = try c.decode(Int.self, forKey: .year); director = (try? c.decode(String.self, forKey: .director)) ?? ""
                crew = (try? c.decode([Member].self, forKey: .crew)) ?? []
                article = (try? c.decode([String].self, forKey: .article)) ?? []
                firstPass = (try? c.decode([String].self, forKey: .firstPass)) ?? []
            }
        }
        struct Page: Decodable { let url: String, site: String, title: String; let paragraphs: [String]; let failure: String? }
        struct Hit: Decodable { let title: String, url: String }
        struct Search: Decodable { let provider: String, query: String; let hits: [Hit] }
        /// (1.10.10) A film is named by its title or its id, and `aboutFilm` is the production the
        /// passage is about (a title) or whether it's this film's (true/false): every corpus is read the same.
        struct Claim: Decodable {
            var id: String, film: String, source: String, passage: String, term: String, property: String, expected: String
            var aboutFilm: String, evidenceType: String
            var filmID: Int?
            var aboutThisFilm: Bool?
            var stage: String?
            enum Keys: String, CodingKey { case id, film, source, passage, term, property, expected, aboutFilm, evidenceType, stage }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Keys.self)
                id = try c.decode(String.self, forKey: .id)
                if let number = try? c.decode(Int.self, forKey: .film) { filmID = number; film = "" } else { film = try c.decode(String.self, forKey: .film) }
                source = try c.decode(String.self, forKey: .source); passage = try c.decode(String.self, forKey: .passage)
                term = try c.decode(String.self, forKey: .term); property = (try? c.decode(String.self, forKey: .property)) ?? ""
                expected = try c.decode(String.self, forKey: .expected)
                if let flag = try? c.decode(Bool.self, forKey: .aboutFilm) { aboutThisFilm = flag; aboutFilm = "" } else {
                    aboutFilm = (try? c.decode(String.self, forKey: .aboutFilm)) ?? ""
                }
                evidenceType = (try? c.decode(String.self, forKey: .evidenceType)) ?? ""
                stage = try? c.decode(String.self, forKey: .stage)
            }
        }
        let films: [Film]
        let pages: [Page]
        let searches: [Search]
        var claims: [Claim]

        /// Claims named by film id, read as named by title (and `aboutFilm` as a title, "" for the film's own).
        mutating func normalise() {
            let titles = Dictionary(films.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            for i in claims.indices {
                if let id = claims[i].filmID { claims[i].film = titles[id] ?? "" }
                if let flag = claims[i].aboutThisFilm { claims[i].aboutFilm = flag ? claims[i].film : "another production" }
            }
        }
    }

    static func load(_ name: String = "claim-holdout.json") throws -> File {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/" + name)
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> File {
        var file = try JSONDecoder().decode(File.self, from: data)
        file.normalise()
        return file
    }

    /// The file as the benchmark's corpus (claims labelled with the production they establish gear for).
    static func corpus(_ file: File) -> BenchCorpus {
        var pages: [String: BenchPage] = [:]
        for page in file.pages {
            let claims = file.claims.filter { $0.source == page.url && $0.expected == "accept" }
                .map { BenchClaim(text: $0.passage, film: $0.film, gear: [$0.term]) }
            pages[page.url] = BenchPage(title: page.title, url: page.url, site: page.site, paragraphs: page.paragraphs, claims: claims,
                                        failure: page.failure == nil || page.failure == "incomplete" ? nil : .unanswered("didn't answer"))
            // ("incomplete": served as it is, cut off mid-sentence, as an incomplete page comes.)
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
        /// Pipeline stages (1.10.10), for each labelled passage: its source was read (discovery), the
        /// passage is in what was read (extraction), it was read as this film's at all (attribution: a
        /// spec from it, accepted or kept as mentioned), and the decision.
        var labelled = 0, discovered = 0, extracted = 0, attributed = 0
        var passageless = 0
        var byType: [String: (right: Int, total: Int)] = [:]
        var errors: [String] = []
        var precision: Double { truePositive + falsePositive == 0 ? 1 : Double(truePositive) / Double(truePositive + falsePositive) }
        var recall: Double { accept == 0 ? 1 : Double(truePositive) / Double(accept) }
        var stages: String {
            "stages: labelled \(labelled), source read \(discovered), passage extracted \(extracted), attributed to the film \(attributed); accepted without a passage \(passageless)"
        }
        var description: String {
            String(format: "accept %d: accepted %d, missed %d (of them unreached %d) | reject %d: rejected %d, wrongly accepted %d (cross-film %d) | abstain %d: held back %d, accepted %d | precision %.3f, recall %.3f, rejection %.3f",
                   accept, truePositive, falseNegative, unreached, reject, trueNegative, falsePositive, crossFilm, abstain, abstained, unsafe,
                   precision, recall, reject == 0 ? 1 : Double(trueNegative) / Double(reject))
        }
    }

    func say(_ line: String) { FileHandle.standardOutput.write(Data(("BENCH| " + line + "\n").utf8)) }

    /// Every film of a corpus in this form read through the production path, and each labelled passage scored.
    static func score(_ file: File) async -> Score {
        let corpus = ClaimHoldoutTests.corpus(file)
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
            score.passageless += specs.accepted.filter { ($0.evidence ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count
            let readText = ClaimHoldoutTests.squash(texts.flatMap { $0.sections.flatMap(\.paragraphs) }.joined(separator: " "))
            for claim in file.claims where claim.film == film.title {
                let term = ClaimHoldoutTests.squash(claim.term)
                let passage = ClaimHoldoutTests.squash(String(claim.passage.prefix(90)))
                // Pipeline stages: discovery, extraction, attribution.
                score.labelled += 1
                if read.contains(claim.source) { score.discovered += 1 }
                if passage.count >= 20, readText.contains(passage) { score.extracted += 1 }
                if (specs.accepted + specs.mentioned).contains(where: { spec in
                    let name = ClaimHoldoutTests.squash(spec.name), evidence = ClaimHoldoutTests.squash(spec.evidence ?? "")
                    return name.count >= 3 && (name.contains(term) || term.contains(name)) && evidence.count >= 20
                        && (evidence.contains(passage) || passage.contains(String(evidence.prefix(60))))
                }) { score.attributed += 1 }
                let accepted = specs.accepted.contains { spec in
                    let name = ClaimHoldoutTests.squash(spec.name)
                    let evidence = ClaimHoldoutTests.squash(spec.evidence ?? "")
                    // The same gear (a name of three letters or more inside the other) from the same passage
                    // (its first 90 letters, or the evidence's first 60 when the evidence is the shorter).
                    return name.count >= 3 && term.count >= 3 && (name.contains(term) || term.contains(name))
                        && evidence.count >= 20 && passage.count >= 20
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
                        // What Reel did with it instead (1.10.10 diagnostics): set aside with a reason, kept as
                        // mentioned, or not recognised at all.
                        let sameGear: (String, String?) -> Bool = { name, evidence in
                            let n = ClaimHoldoutTests.squash(name), e = ClaimHoldoutTests.squash(evidence ?? "")
                            return n.count >= 3 && (n.contains(term) || term.contains(n)) && e.count >= 20
                                && (e.contains(passage) || passage.contains(String(e.prefix(60))))
                        }
                        let did = specs.judged.first { sameGear($0.name, $0.evidence) }.map { "set aside: \($0.reason)" }
                            ?? (specs.mentioned.contains { sameGear($0.name, $0.evidence) } ? "mentioned only" : "not recognised")
                        score.errors.append("MISS \(claim.id) [\(tag)] \(film.title) ← \(claim.term) (\(did)): \(claim.passage.prefix(110))")
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
        return score
    }

    func testTheIndependentClaimHoldout() async throws {
        let file = try Self.load()
        XCTAssertEqual(file.films.count, 30)
        XCTAssertEqual(file.claims.count, 299)
        let score = await Self.score(file)
        say("claim holdout, 1.10.10: \(score)")
        say("claim holdout " + score.stages)
        say("claim holdout by type: " + score.byType.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.right)/\($0.value.total)" }.joined(separator: ", "))
        for error in score.errors { say("claim holdout " + error) }
        // Pinned at what 1.10.9 reaches, so a change either way shows: the remaining cases need to know
        // that a bare word ("Kettle" in "Q: Kettle seems lit by the windows") is another film's title,
        // which no rule here can (see the handoff).
        XCTAssertLessThanOrEqual(score.crossFilm, 3, "cross-film contamination in the claim holdout")
        XCTAssertGreaterThanOrEqual(score.trueNegative, 121, "rejection floor (measured 121/129)")
        XCTAssertGreaterThanOrEqual(score.truePositive, 81, "recall floor (measured 81/128)")
        XCTAssertLessThanOrEqual(score.unsafe, 6, "abstentions accepted (measured 6/42)")
    }
}
