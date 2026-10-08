#if os(macOS)
import NaturalLanguage
import ReelCore

/// Apple's on-device sentiment model, used to sort review sentences into likes and dislikes.
enum Sentiment {
    static func summarize(_ reviews: [ReviewText]) -> ReceptionSummary? {
        guard !reviews.isEmpty else { return nil }
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        return ReceptionAnalyzer.summarize(reviews) { sentence in
            tagger.string = sentence
            let (tag, _) = tagger.tag(at: sentence.startIndex, unit: .paragraph, scheme: .sentimentScore)
            return Double(tag?.rawValue ?? "") ?? 0
        }
    }
}
#endif
