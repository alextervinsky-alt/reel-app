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

    /// How many slips a word may have when nothing matches it exactly (a swap of two letters
    /// is one slip): none for short words, one from five letters, two from eight.
    public static func typoAllowance(_ word: String) -> Int {
        word.count >= 8 ? 2 : (word.count >= 5 ? 1 : 0)
    }

    /// Slips between two words: letters added, left out, changed or swapped ("kubrcik" is one
    /// from "kubrick").
    public static func slips(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var d = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in 1...x.count {
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[x.count][y.count]
    }

    static let phrases: [(String, String)] = [
        ("sci fi", "science fiction"), ("rom com", "romance comedy"), ("b and w", "black and white"),
        ("black white", "black and white"), ("film noir", "noir"), ("romcom", "rom com"),
        ("rom com", "romance comedy"), ("doc", "documentary"), ("docs", "documentary"),
    ]

    /// Searched as one, not word by word.
    static let joined = ["science fiction", "black and white"]

    static let synonyms: [String: [String]] = [
        "cartoon": ["animation", "animated"], "cartoons": ["animation", "animated"], "animated": ["animation"],
        "anime": ["animation"], "animations": ["animation"],
        "documentaries": ["documentary"], "comedies": ["comedy"], "funny": ["comedy"],
        "scifi": ["science fiction"], "kids": ["family"], "children": ["family"], "childrens": ["family"],
        "musicals": ["musical"], "scary": ["horror"],
        "bw": ["black and white"], "monochrome": ["black and white"],
    ]
}
