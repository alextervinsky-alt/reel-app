import Foundation
@testable import ReelCore

/// Placeholder until the blind holdout is written (replaced before release).
enum HoldoutCorpus {
    static func corpus() -> BenchCorpus { BenchCorpus(name: "holdout", films: [], pages: [:], searches: []) }
}
