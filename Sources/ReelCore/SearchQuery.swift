import Foundation

/// What a library search is made of: its words, each with the words that may stand in for it
/// ("cartoon" finds animated films, "docs" documentaries, "sci-fi" science fiction), and how
/// many typing slips a word may have when nothing matches it exactly.
public enum SearchQuery {
    /// Each word of the query (normalized) with its stand-ins, the word itself first.
    public static func terms(_ query: String) -> [[String]] {
        var text = " " + TitleSimilarity.normalize(query) + " "
        for (phrase, meaning) in phrases { text = text.replacingOccurrences(of: " \(phrase) ", with: " \(meaning) ") }
        let words = text.split(separator: " ").map(String.init)
        // A phrase replaced above is searched as one: "science fiction", "black and white".
        var result: [[String]] = []
        var i = 0
        while i < words.count {
            if let phrase = joined.first(where: { phrase in
                let parts = phrase.split(separator: " ").map(String.init)
                return i + parts.count <= words.count && Array(words[i..<i + parts.count]) == parts
            }) {
                result.append([phrase])
                i += phrase.split(separator: " ").count
                continue
            }
            let word = words[i]
            var alternatives = [word] + (synonyms[word] ?? [])
            // "westerns" → "western", "thrillers" → "thriller".
            if word.count > 4, word.hasSuffix("s"), !word.hasSuffix("ss") { alternatives.append(String(word.dropLast())) }
            var seen = Set<String>()
            result.append(alternatives.filter { seen.insert($0).inserted })
            i += 1
        }
        return result
    }

    /// How many letters a word may have wrong when nothing matches it exactly: none for short
    /// words (so "cartoon" never finds "Carson"), one from five letters, two from nine.
    public static func typoAllowance(_ word: String) -> Int {
        word.count >= 9 ? 2 : (word.count >= 5 ? 1 : 0)
    }

    static let phrases: [(String, String)] = [
        ("sci fi", "science fiction"), ("rom com", "romance comedy"), ("b and w", "black and white"),
        ("black white", "black and white"), ("film noir", "noir"),
    ]

    /// Searched as one, not word by word.
    static let joined = ["science fiction", "black and white"]

    static let synonyms: [String: [String]] = [
        "cartoon": ["animation", "animated"], "cartoons": ["animation", "animated"], "animated": ["animation"],
        "anime": ["animation"], "animations": ["animation"],
        "doc": ["documentary"], "docs": ["documentary"], "documentaries": ["documentary"],
        "comedies": ["comedy"], "funny": ["comedy"], "romcom": ["romance", "comedy"],
        "scifi": ["science fiction"], "kids": ["family"], "children": ["family"], "childrens": ["family"],
        "musicals": ["music", "musical"], "musical": ["music"], "scary": ["horror"],
        "bw": ["black and white"], "monochrome": ["black and white"],
    ]
}
