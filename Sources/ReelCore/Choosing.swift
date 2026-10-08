import Foundation

// MARK: - Trailers

/// Which videos Reel plays: only the studio's or distributor's own trailers and teasers on
/// YouTube (TMDB marks them official). Never clips, featurettes, fan edits or re-uploads.
public enum Trailers {
    public static func isOfficial(_ video: TMDBVideo) -> Bool {
        video.official == true && video.site == "YouTube" && (video.type == "Trailer" || video.type == "Teaser")
    }

    /// Up to three to try, best first: English, then no language, then the film's own language,
    /// the trailer before the teaser; with `preferTeaser` (it shows less of the story) any teaser
    /// comes before every trailer. The earliest first (the first release usually gives away least).
    public static func candidates(_ videos: [TMDBVideo], preferTeaser: Bool, originalLanguage: String?) -> [TMDBVideo] {
        func languageRank(_ video: TMDBVideo) -> Int {
            switch video.language {
            case "en": 0
            case nil: 1
            case originalLanguage: 2
            default: 3
            }
        }
        func typeRank(_ video: TMDBVideo) -> Int {
            (video.type == "Teaser") == preferTeaser ? 0 : 1
        }
        var seen = Set<String>()
        return videos
            .filter { isOfficial($0) && languageRank($0) < 3 }
            .filter { seen.insert($0.key).inserted }
            .sorted {
                // A teaser in any of the languages beats a full trailer in English: it's there to
                // keep the story back.
                let first = preferTeaser ? (typeRank($0), languageRank($0)) : (languageRank($0), typeRank($0))
                let second = preferTeaser ? (typeRank($1), languageRank($1)) : (languageRank($1), typeRank($1))
                return (first.0, first.1, $0.publishedAt ?? "~") < (second.0, second.1, $1.publishedAt ?? "~")
            }
            .prefix(3)
            .map { $0 }
    }
}

// MARK: - The evening's order

/// Rows look fresh each evening without losing what they promise: films are grouped in
/// half-point rating bands (8.5–8.9, 8.0–8.4…), and only the order inside a band changes, once
/// per evening. A better film never drops below a clearly worse one; films without a rating
/// stay at the end in their order. Nothing is saved: the order comes from the evening's date.
public enum EveningOrder {
    public static func arrange<T>(_ items: [T], evening: String, id: (T) -> String, score: (T) -> Double?) -> [T] {
        let rated = items.enumerated().compactMap { index, item -> (item: T, band: Int, key: UInt64, index: Int)? in
            guard let score = score(item) else { return nil }
            return (item, Int((score * 2).rounded(.down)), stableHash(evening + "|" + id(item)), index)
        }
        let unrated = items.filter { score($0) == nil }
        return rated.sorted { ($0.band, $1.key) > ($1.band, $0.key) }.map { $0.item } + unrated
    }

    /// FNV-1a: the same for the same text on every launch (Swift's own hashing changes per launch).
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

// MARK: - From the same people

/// How another film in the library is connected to this one, for "From the Same People".
public struct Connection: Equatable, Sendable {
    public let role: String
    public let name: String

    /// "Director · Yorgos Lanthimos"
    public var label: String { "\(role) · \(name)" }
}

public enum SamePeople {
    /// The strongest shared person, in this order: director, writer, cinematographer, composer,
    /// then this film's two lead actors. Nil when the films share none of them.
    public static func connection(of film: LikenessFeatures, to other: LikenessFeatures) -> Connection? {
        func first(_ a: Set<String>, _ b: Set<String>) -> String? { a.intersection(b).sorted().first }
        if let name = first(film.directors, other.directors) { return Connection(role: "Director", name: name) }
        if let name = first(film.writers, other.writers) { return Connection(role: "Writer", name: name) }
        if let name = first(film.cinematographers, other.cinematographers) { return Connection(role: "Cinematographer", name: name) }
        if let name = first(film.composers, other.composers) { return Connection(role: "Music", name: name) }
        if let name = film.leads.first(where: { other.cast.contains($0) }) { return Connection(role: "With", name: name) }
        return nil
    }
}

// MARK: - Languages

/// A film's language for rows and filters, from TMDB's original language.
public enum FilmLanguage {
    /// Mandarin and Cantonese count as one language.
    public static func code(_ original: String?) -> String? {
        guard let original, !original.isEmpty, original != "xx" else { return nil }
        return original == "cn" ? "zh" : original
    }

    /// "Korean", "French"… in English.
    public static func name(_ code: String) -> String {
        if let known = names[code] { return known }
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    static let names = [
        "en": "English", "et": "Estonian", "fr": "French", "de": "German", "es": "Spanish", "it": "Italian",
        "ja": "Japanese", "ko": "Korean", "zh": "Chinese", "ru": "Russian", "sv": "Swedish", "da": "Danish",
        "no": "Norwegian", "fi": "Finnish", "pl": "Polish", "pt": "Portuguese", "hi": "Hindi", "fa": "Persian",
        "tr": "Turkish", "nl": "Dutch", "el": "Greek", "hu": "Hungarian", "cs": "Czech", "ro": "Romanian",
        "he": "Hebrew", "ar": "Arabic", "th": "Thai", "uk": "Ukrainian", "lv": "Latvian", "lt": "Lithuanian",
        "is": "Icelandic",
    ]
}
