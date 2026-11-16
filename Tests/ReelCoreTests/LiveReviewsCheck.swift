import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
@testable import ReelCore

/// Public reviews read live for well-known films (public titles, not anyone's library), for the
/// hand-labelled Reviews gate (spec §6.4). Runs only when REEL_REVIEW_CHECK names a file to
/// write; CI's review-check job does that on a Mac, so Apple's sentiment model scores the
/// sentences exactly as the app does. What's written: every sentence that names an aspect (the
/// only ones that can be shown), the model's score for each part, and what Reel shows today.
final class LiveReviewsCheck: XCTestCase {
    /// Set A: the rules are tuned on these.
    static let tuning: [(String, Int)] = [
        ("Oppenheimer", 2023), ("Parasite", 2019), ("Joker", 2019), ("Blade Runner 2049", 2017), ("Dune", 2021),
        ("Mad Max: Fury Road", 2015), ("La La Land", 2016), ("Inception", 2010), ("Interstellar", 2014), ("Poor Things", 2023),
        ("Killers of the Flower Moon", 2023), ("Tenet", 2020), ("Venom", 2018), ("Suicide Squad", 2016), ("Justice League", 2017),
        ("Eternals", 2021), ("The Flash", 2023), ("Morbius", 2022), ("Don't Look Up", 2021), ("Babylon", 2022),
        ("Black Adam", 2022), ("Aquaman", 2018), ("Glass", 2019), ("Napoleon", 2023), ("Argylle", 2024),
        ("Madame Web", 2024), ("Megalopolis", 2024), ("The Batman", 2022), ("Barbie", 2023), ("Wonka", 2023),
    ]

    /// Set B: not looked at while the rules are set; the gate is its first reading.
    static let heldOut: [(String, Int)] = [
        ("Gravity", 2013), ("Birdman", 2014), ("Her", 2013), ("Skyfall", 2012), ("Gone Girl", 2014),
        ("Prisoners", 2013), ("The Irishman", 2019), ("Once Upon a Time in Hollywood", 2019), ("Everything Everywhere All at Once", 2022), ("The Holdovers", 2023),
        ("Challengers", 2024), ("Whiplash", 2014), ("The Shape of Water", 2017), ("The Whale", 2022), ("Elvis", 2022),
        ("Spectre", 2015), ("Batman v Superman: Dawn of Justice", 2016), ("Wonder Woman 1984", 2020), ("Doctor Strange in the Multiverse of Madness", 2022), ("Thor: Love and Thunder", 2022),
        ("Transformers: The Last Knight", 2017), ("Jurassic World Dominion", 2022), ("The Little Mermaid", 2023), ("Aquaman and the Lost Kingdom", 2023), ("The Marvels", 2023),
        ("Rebel Moon - Part One: A Child of Fire", 2023), ("Borderlands", 2024), ("Joker: Folie à Deux", 2024), ("Kraven the Hunter", 2024), ("Red One", 2024),
    ]

    struct Review: Codable {
        let rating: Double?
        let critic: Bool
        /// Only the sentences that name an aspect (the others are never shown).
        let sentences: [String]
    }

    struct Shown: Codable {
        let aspect: String
        let quote: String?
    }

    struct Film: Codable {
        let title: String
        let year: Int
        let reviews: [Review]
        /// The sentiment model's score for each part of each sentence kept.
        let sentiment: [String: Double]
        let liked: [Shown]
        let disliked: [Shown]
    }

    func testReadTheReviewsLive() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let output = env["REEL_REVIEW_CHECK"], !output.isEmpty, let token = env["TMDB_TOKEN"], !token.isEmpty else {
            throw XCTSkip("REEL_REVIEW_CHECK and TMDB_TOKEN not set")
        }
        #if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        func score(_ text: String) -> Double {
            tagger.string = text
            let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
            return Double(tag?.rawValue ?? "") ?? 0
        }
        #else
        func score(_ text: String) -> Double { 0 }
        #endif
        let tmdb = TMDBClient(token: token)
        let set = env["REEL_REVIEW_SET"] == "held-out" ? Self.heldOut : Self.tuning
        var films: [Film] = []
        for (title, year) in set {
            guard let hit = try await tmdb.searchMovies(query: title, year: year).first else { continue }
            let details = try await tmdb.movieDetails(id: hit.id)
            let findings = try? await WikipediaClient().findings(imdbID: details.imdbID, title: details.title, year: details.year)
            var texts = (details.reviews?.results ?? []).map { ReviewText(text: $0.content, rating: $0.authorDetails?.rating) }
            texts += (findings?.criticSentences ?? []).map { ReviewText(text: $0, rating: nil, isCritic: true) }
            var sentiment: [String: Double] = [:]
            let reviews = texts.map { review -> Review in
                let kept = ReceptionAnalyzer.sentences(in: ReceptionAnalyzer.clean(review.text)).filter { sentence in
                    ReceptionAnalyzer.clauses(of: sentence).contains { clause in
                        let lower = clause.lowercased()
                        return !ReceptionAnalyzer.aspects(in: lower).isEmpty
                            || ReceptionAnalyzer.cueAspects.contains { ReceptionAnalyzer.word($0.cue, in: lower) != nil }
                    }
                }
                for sentence in kept {
                    for clause in ReceptionAnalyzer.clauses(of: sentence) { sentiment[clause] = score(clause) }
                }
                return Review(rating: review.rating, critic: review.isCritic, sentences: kept)
            }
            let summary = ReceptionAnalyzer.summarize(texts) { sentiment[$0] ?? score($0) }
            films.append(Film(title: details.title, year: year, reviews: reviews, sentiment: sentiment,
                              liked: summary?.liked.map { Shown(aspect: $0.aspect, quote: $0.quote) } ?? [],
                              disliked: summary?.disliked.map { Shown(aspect: $0.aspect, quote: $0.quote) } ?? []))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(films).write(to: URL(fileURLWithPath: output))
        let sentences = films.flatMap { $0.reviews.flatMap(\.sentences) }.count
        print("REVIEWS| \(films.count) films read; \(films.map { $0.reviews.count }.reduce(0, +)) reviews; "
              + "\(sentences) sentences naming an aspect; shown today: \(films.map { $0.liked.count }.reduce(0, +)) likes, "
              + "\(films.map { $0.disliked.count }.reduce(0, +)) dislikes")
        XCTAssertGreaterThanOrEqual(films.count, 25)
    }
}
