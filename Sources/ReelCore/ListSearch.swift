import Foundation

/// Lists' search: lists of films for any word, to find films outside your usual taste. A theme
/// TMDB tags films with ("heist", "time travel", "lighthouse") is a list of its own, best-rated
/// first; so is a film series, a person's films, a country's cinema or a decade; and Wikipedia's
/// own "List of … films" articles are there to read.
public enum ListSearch {
    public struct Theme: Decodable, Equatable, Hashable, Sendable, Identifiable {
        public let id: Int
        public let name: String

        public init(id: Int, name: String) {
            self.id = id
            self.name = name
        }

        /// "time travel" → "Time Travel"; "tokyo, japan" → "Tokyo, Japan".
        public var title: String {
            name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
    }

    public struct Series: Decodable, Equatable, Hashable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let posterPath: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case posterPath = "poster_path"
        }
    }

    public struct Person: Decodable, Equatable, Hashable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let department: String?
        public let profilePath: String?
        public let popularity: Double?

        enum CodingKeys: String, CodingKey {
            case id, name, popularity
            case department = "known_for_department"
            case profilePath = "profile_path"
        }

        public var role: String {
            switch department {
            case "Directing": "Director"
            case "Camera": "Cinematographer"
            case "Writing": "Writer"
            case "Sound": "Composer"
            case "Acting": "Actor"
            default: department ?? ""
            }
        }
    }

    public struct WikiList: Equatable, Hashable, Sendable, Identifiable {
        public let title: String
        public let url: URL
        public var id: String { title }
    }

    public struct Results: Equatable, Sendable {
        public var themes: [Theme] = []
        public var series: [Series] = []
        public var people: [Person] = []
        /// A country's cinema or a decade the words name.
        public var cinema: [DiscoverList] = []
        public var wikipedia: [WikiList] = []

        public init(themes: [Theme] = [], series: [Series] = [], people: [Person] = [], cinema: [DiscoverList] = [],
                    wikipedia: [WikiList] = []) {
            self.themes = themes
            self.series = series
            self.people = people
            self.cinema = cinema
            self.wikipedia = wikipedia
        }

        public var isEmpty: Bool { themes.isEmpty && series.isEmpty && people.isEmpty && cinema.isEmpty && wikipedia.isEmpty }
    }

    /// The themes worth a list, best match first: the words themselves, then themes starting
    /// with them, then the rest; at most eight.
    public static func rank(_ themes: [Theme], for query: String) -> [Theme] {
        let wanted = query.lowercased().trimmingCharacters(in: .whitespaces)
        func score(_ theme: Theme) -> Int {
            let name = theme.name.lowercased()
            if name == wanted { return 0 }
            if name.hasPrefix(wanted + " ") || name.hasPrefix(wanted + ",") || name == wanted + "s" { return 1 }
            if name.hasPrefix(wanted) { return 2 }
            return 3
        }
        var seen = Set<String>()
        return themes
            .filter { seen.insert($0.name.lowercased()).inserted }
            .enumerated()
            .sorted { (score($0.element), $0.offset) < (score($1.element), $1.offset) }
            .prefix(8)
            .map(\.element)
    }

    /// A country's cinema or a decade, when the words name one ("japan", "korean cinema",
    /// "1970s", "70s").
    public static func cinema(for query: String) -> [DiscoverList] {
        var wanted = query.lowercased().trimmingCharacters(in: .whitespaces)
        for suffix in [" cinema", " films", " film", " movies"] where wanted.hasSuffix(suffix) {
            wanted = String(wanted.dropLast(suffix.count))
        }
        guard wanted.count >= 3 else { return [] }
        var found: [DiscoverList] = []
        let generic: Set<String> = ["south", "the", "republic", "new", "hong", "czech"]
        for country in DiscoverList.countries {
            let name = country.name.lowercased().replacingOccurrences(of: "the ", with: "")
            let words = name.split(separator: " ").map(String.init).filter { !generic.contains($0) }
            if name == wanted || words.contains(wanted) || demonyms[wanted] == country.code {
                found.append(.country(code: country.code))
            }
        }
        if let match = wanted.range(of: #"^(?:(19|20)?(\d)0)'?s$"#, options: .regularExpression) {
            let digits = wanted[match].filter(\.isNumber)
            let start = digits.count == 4 ? Int(digits) : Int(digits).map { ($0 >= 30 ? 1900 : 2000) + $0 }
            if let start, DiscoverList.decades.contains(start) || start == 2020 { found.append(.decade(start)) }
        }
        return found
    }

    static let demonyms: [String: String] = [
        "japanese": "JP", "korean": "KR", "french": "FR", "italian": "IT", "german": "DE", "spanish": "ES", "mexican": "MX",
        "iranian": "IR", "persian": "IR", "danish": "DK", "swedish": "SE", "indian": "IN", "bollywood": "IN", "brazilian": "BR",
        "argentine": "AR", "argentinian": "AR", "taiwanese": "TW", "polish": "PL", "romanian": "RO", "belgian": "BE",
        "british": "GB", "english": "GB", "uk": "GB", "irish": "IE", "norwegian": "NO", "finnish": "FI", "estonian": "EE",
        "chinese": "CN", "turkish": "TR", "greek": "GR", "hungarian": "HU", "czech": "CZ", "australian": "AU", "canadian": "CA",
        "hong kong": "HK", "czech republic": "CZ",
    ]
}

extension WikipediaClient {
    /// Wikipedia's "List of … films" articles for the words ("List of heist films").
    public func filmLists(_ query: String) async throws -> [ListSearch.WikiList] {
        struct Search: Decodable {
            struct Query: Decodable {
                struct Hit: Decodable { let title: String }
                let search: [Hit]
            }
            let query: Query?
        }
        let result: Search = try await Wikimedia.get("https://en.wikipedia.org/w/api.php", [
            "action": "query", "list": "search", "srsearch": "intitle:\"List of\" intitle:films \(query)", "srlimit": "8",
            "format": "json",
        ], session: session)
        return (result.query?.search ?? []).compactMap { hit in
            guard hit.title.hasPrefix("List of"), hit.title.localizedCaseInsensitiveContains("film") else { return nil }
            let encoded = hit.title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            return encoded.flatMap { URL(string: "https://en.wikipedia.org/wiki/\($0)") }.map { ListSearch.WikiList(title: hit.title, url: $0) }
        }
        .prefix(5).map { $0 }
    }
}
