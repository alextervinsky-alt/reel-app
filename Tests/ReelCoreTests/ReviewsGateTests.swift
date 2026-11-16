import XCTest
@testable import ReelCore

/// The Reviews gate (spec §6.4): what Reel would show for public films, checked against labels
/// written by reading each shown sentence. The reviews were read on a Mac by CI's review-check job
/// (public titles, only the sentences that name an aspect, with Apple's sentiment score for each
/// part), so this runs the same everywhere. Set A was used to set the rules; set B, the gate, was
/// not looked at until they were final. A shown sentence with no label fails the gate: it has to be
/// read first.
final class ReviewsGateTests: XCTestCase {
    struct Review: Decodable {
        let rating: Double?
        let critic: Bool
        let sentences: [String]
    }

    struct Film: Decodable {
        let title: String
        let year: Int
        let reviews: [Review]
        let sentiment: [String: Double]
    }

    /// One shown sentence as read: right means it says that about that aspect of this film.
    struct Label: Codable {
        let film: String
        let kind: String
        let aspect: String
        let quote: String
        let right: Bool
        var note: String?
    }

    struct Labels: Decodable {
        /// Sets whose result must reach the bar.
        let gated: [String]
        let labels: [Label]
    }

    struct Shown: Encodable {
        let set: String
        let film: String
        let kind: String
        let aspect: String
        let quote: String
        let right: Bool?
        let note: String?
    }

    static func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
    }

    func testShownLikesAndDislikesAreRight() throws {
        let labelFile = try JSONDecoder().decode(Labels.self, from: Data(contentsOf: Self.fixture("reviews-labels.json")))
        var labels: [String: Label] = [:]
        for label in labelFile.labels { labels["\(label.film)|\(label.kind)|\(label.aspect)|\(label.quote)"] = label }

        var shownAll: [Shown] = []
        for set in ["a", "b"] {
            let url = Self.fixture("reviews-\(set).json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let films = try JSONDecoder().decode([Film].self, from: Data(contentsOf: url))
            var missing = 0
            var shown: [Shown] = []
            for film in films {
                let texts = film.reviews.map { ReviewText(text: $0.sentences.joined(separator: "\n"), rating: $0.rating, isCritic: $0.critic) }
                let summary = ReceptionAnalyzer.summarize(texts, title: film.title, year: film.year) { clause in
                    if let score = film.sentiment[clause] { return score }
                    missing += 1
                    return 0
                }
                for (kind, points) in [("like", summary?.liked ?? []), ("dislike", summary?.disliked ?? [])] {
                    for point in points {
                        let quote = point.quote ?? ""
                        let label = labels["\(film.title)|\(kind)|\(point.aspect)|\(quote)"]
                        shown.append(Shown(set: set, film: film.title, kind: kind, aspect: point.aspect, quote: quote,
                                           right: label?.right, note: label?.note))
                    }
                }
            }
            shownAll += shown
            func line(_ kind: String) -> String {
                let all = shown.filter { $0.kind == kind }
                let read = all.filter { $0.right != nil }
                let right = read.filter { $0.right == true }.count
                let share = read.isEmpty ? "–" : String(format: "%.1f%%", 100 * Double(right) / Double(read.count))
                return "\(kind)s \(right) right of \(read.count) read (\(share)), \(all.count - read.count) not read yet"
            }
            let filmsShowing = Set(shown.map(\.film)).count
            print("REVIEWS| set \(set.uppercased()): \(films.count) films, \(filmsShowing) show something; \(line("like")); \(line("dislike")); "
                  + "\(missing) parts with no stored score")
            if labelFile.gated.contains(set) {
                for kind in ["like", "dislike"] {
                    let all = shown.filter { $0.kind == kind }
                    XCTAssertTrue(all.allSatisfy { $0.right != nil }, "set \(set): every shown \(kind) is read")
                    let right = all.filter { $0.right == true }.count
                    XCTAssertGreaterThanOrEqual(Double(right), 0.95 * Double(all.count), "set \(set): \(kind)s right")
                }
                // The labelled set: at least 150 sentences from at least 25 films (what's shown now,
                // and what Reel 1.10 showed for the same films).
                let names = Set(films.map(\.title))
                let read = labelFile.labels.filter { names.contains($0.film) }
                XCTAssertGreaterThanOrEqual(Set(read.map(\.film)).count, 25)
                XCTAssertGreaterThanOrEqual(read.count, 150)
            }
        }
        if let output = ProcessInfo.processInfo.environment["REEL_REVIEW_EVAL"], !output.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(shownAll).write(to: URL(fileURLWithPath: output))
        }
    }
}
