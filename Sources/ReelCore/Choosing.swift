import Foundation

// MARK: - Trailers

/// Which videos Reel plays: the film's trailers and teasers on YouTube, never clips, TV spots,
/// featurettes, announcements, reactions or fan edits. TMDB's labels are filled in by people and
/// often wrong ("Teaser" on a date announcement, "Trailer" on a TV spot), so the video's own
/// name has the last word. The studio's or distributor's own uploads come first; a trailer
/// uploaded by someone else (an archive or a regional distributor) is the fallback, so older and
/// smaller films still have one.
public enum Trailers {
    /// Words in a video's name that make it something other than the film's trailer.
    static let notATrailer: NSRegularExpression = {
        let words = [
            "tv[ -]?spots?", "spots?", "clips?", "featurettes?", "behind[ -]the[ -]scenes", "bts", "making[ -]of",
            "interviews?", "reacts?", "reactions?", "reviews?", "recap", "explained", "breakdown", "promos?",
            "announcements?", "announce", "countdown", "sneak[ -](peek|preview)", "(first|special|exclusive|inside) look",
            "music video", "lyric video", "soundtrack", "q ?& ?a", "panel", "red carpet", "fan[ -]?made", "parody",
            "honest trailers?", "mash-?up", "re-?upload", "sizzle", "vignette", "trailer (tease|teaser|reveal|preview)",
            "tickets?", "now playing", "in (cinemas|theaters|theatres) (now|today)", "(blu-?ray|dvd|digital|4k uhd) release",
            "own it", "available now", "commentary",
        ]
        return try! NSRegularExpression(pattern: "\\b(" + words.joined(separator: "|") + ")\\b", options: [.caseInsensitive])
    }()

    /// A trailer or teaser on YouTube, as far as its label and name say. The film's own title is
    /// taken out of the name first ("The Interview | Official Trailer" is a trailer).
    public static func isTrailer(_ video: TMDBVideo, title: String? = nil) -> Bool {
        guard isKept(video) else { return false }
        var name = video.name ?? ""
        if let title, !title.isEmpty {
            name = name.replacingOccurrences(of: title, with: " ", options: [.caseInsensitive, .diacriticInsensitive])
        }
        guard notATrailer.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) == nil else { return false }
        // Someone else's upload must call itself a trailer (or a teaser).
        if video.official != true {
            let lower = name.lowercased()
            return lower.contains("trailer") || lower.contains("teaser")
        }
        return true
    }

    /// What's kept from TMDB (the name is checked when one is picked): YouTube trailers and teasers.
    public static func isKept(_ video: TMDBVideo) -> Bool {
        video.site == "YouTube" && (video.type == "Trailer" || video.type == "Teaser")
    }

    /// A real teaser: labelled one and named one ("Official Teaser", "Teaser Trailer"). Shows less
    /// of the story than the trailer.
    static func isTeaser(_ video: TMDBVideo) -> Bool {
        video.type == "Teaser" || (video.name ?? "").lowercased().contains("teaser")
    }

    /// Up to five to try, best first: the studio's own uploads before anyone else's; English,
    /// then no language, then the film's own language; the trailer before the teaser, or with
    /// `preferTeaser` (spoiler-safe, unwatched) a real teaser first; the earliest first (the first
    /// release usually gives away least). Five, because studios block some of theirs from
    /// playing outside YouTube.
    public static func candidates(_ videos: [TMDBVideo], title: String?, preferTeaser: Bool, originalLanguage: String?) -> [TMDBVideo] {
        func languageRank(_ video: TMDBVideo) -> Int {
            switch video.language {
            case "en": 0
            case nil: 1
            case originalLanguage: 2
            default: 3
            }
        }
        func typeRank(_ video: TMDBVideo) -> Int {
            isTeaser(video) == preferTeaser ? 0 : 1
        }
        func rank(_ video: TMDBVideo) -> (Int, Int, Int, String) {
            let official = video.official == true ? 0 : 1
            // Spoiler-safe: a real teaser in any of the languages beats a full trailer in English.
            return preferTeaser
                ? (official, typeRank(video), languageRank(video), video.publishedAt ?? "~")
                : (official, languageRank(video), typeRank(video), video.publishedAt ?? "~")
        }
        var seen = Set<String>()
        return videos
            .filter { isTrailer($0, title: title) && languageRank($0) < 3 }
            .filter { seen.insert($0.key).inserted }
            .sorted { rank($0) < rank($1) }
            .prefix(5)
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
