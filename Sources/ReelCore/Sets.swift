import Foundation

// MARK: - Complete the set

/// A film in a set: a director's or cinematographer's films, or a franchise.
public struct SetFilm: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// TMDB id.
    public var id: Int
    public var title: String
    public var year: Int?
    public var posterPath: String?
    public var backdropPath: String?
    /// TMDB votes; for people's sets, films with few votes (shorts, music videos) only count
    /// when you own them.
    public var votes: Int?

    public init(id: Int, title: String, year: Int?, posterPath: String?, backdropPath: String?, votes: Int? = nil) {
        self.id = id
        self.title = title
        self.year = year
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.votes = votes
    }
}

/// "Denis Villeneuve, director: 10 films", "Blade Runner Collection: 2 films".
public struct FilmSet: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case director, cinematographer, franchise

        public var title: String {
            switch self {
            case .director: "Directors"
            case .cinematographer: "Cinematographers"
            case .franchise: "Franchises"
            }
        }

        /// The TMDB crew job this set is made of.
        public var job: String? {
            switch self {
            case .director: "Director"
            case .cinematographer: "Director of Photography"
            case .franchise: nil
            }
        }
    }

    public var kind: Kind
    /// TMDB person or collection id.
    public var tmdbID: Int
    public var name: String
    /// Profile photo or collection poster.
    public var imagePath: String?
    /// Every credit, oldest first. See `films(owned:)` for the ones that count.
    public var films: [SetFilm]
    /// Films with fewer votes only count when owned.
    public var minimumVotes: Int
    public var fetchedAt: Date

    public var id: String { FilmSet.id(kind, tmdbID) }

    public static func id(_ kind: Kind, _ tmdbID: Int) -> String { "\(kind.rawValue):\(tmdbID)" }

    public init(kind: Kind, tmdbID: Int, name: String, imagePath: String?, films: [SetFilm], minimumVotes: Int = 0, fetchedAt: Date) {
        self.kind = kind
        self.tmdbID = tmdbID
        self.name = name
        self.imagePath = imagePath
        self.films = films
        self.minimumVotes = minimumVotes
        self.fetchedAt = fetchedAt
    }

    enum CodingKeys: String, CodingKey {
        case kind, tmdbID, name, imagePath, films, minimumVotes, fetchedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        tmdbID = try c.decode(Int.self, forKey: .tmdbID)
        name = try c.decode(String.self, forKey: .name)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        films = try c.decode([SetFilm].self, forKey: .films)
        minimumVotes = try c.decodeIfPresent(Int.self, forKey: .minimumVotes) ?? 0
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
    }

    /// The films of the set: well-known ones, plus any lesser-known ones you own.
    public func films(owned: Set<Int>) -> [SetFilm] {
        films.filter { ($0.votes ?? Int.max) >= minimumVotes || owned.contains($0.id) }
    }
}

public enum FilmSets {
    /// Feature films a person directed or shot. TMDB credits include shorts, music videos and
    /// unfinished projects, which TMDB doesn't mark, so a film counts when it's released and rated
    /// by a fair share of the people who rated their best-known film; any you own always count
    /// (see `FilmSet.films(owned:)`).
    public static func person(_ person: TMDBPerson, kind: FilmSet.Kind, now: Date = Date()) -> FilmSet {
        let today = dayString(now)
        let credits = (person.movieCredits?.crew ?? []).filter { credit in
            guard credit.job == kind.job, let date = credit.releaseDate, !date.isEmpty, date <= today,
                  credit.title?.isEmpty == false else { return false }
            return !(credit.genreIDs ?? []).contains(10770) // TV films
        }
        let mostVotes = credits.map { $0.voteCount ?? 0 }.max() ?? 0
        var seen = Set<Int>()
        let films = credits
            .filter { seen.insert($0.id).inserted }
            .map { SetFilm(id: $0.id, title: $0.title ?? "", year: yearFromDate($0.releaseDate),
                           posterPath: $0.posterPath, backdropPath: $0.backdropPath, votes: $0.voteCount ?? 0) }
            .sorted { ($0.year ?? 0, $0.title) < ($1.year ?? 0, $1.title) }
        return FilmSet(kind: kind, tmdbID: person.id, name: person.name, imagePath: person.profilePath,
                       films: films, minimumVotes: max(40, mostVotes / 40), fetchedAt: now)
    }

    /// A franchise's released films, oldest first.
    public static func collection(_ collection: TMDBCollection, now: Date = Date()) -> FilmSet {
        let today = dayString(now)
        let films = collection.parts
            .filter { ($0.releaseDate ?? "").isEmpty == false && ($0.releaseDate ?? "") <= today }
            .map { SetFilm(id: $0.id, title: $0.title, year: $0.year, posterPath: $0.posterPath, backdropPath: $0.backdropPath) }
            .sorted { ($0.year ?? 0, $0.title) < ($1.year ?? 0, $1.title) }
        return FilmSet(kind: .franchise, tmdbID: collection.id, name: collection.name,
                       imagePath: collection.posterPath, films: films, fetchedAt: now)
    }

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Which people and franchises are worth showing: the ones you already own films of,
    /// most owned first. `credits` is each owned film's (person id, name, job) list.
    public static func candidates(_ owned: [(collection: TMDBCollectionRef?, crew: [TMDBCrewMember])],
                                  minimumOwned: Int = 2, limit: Int = 16) -> [(kind: FilmSet.Kind, id: Int, name: String, owned: Int)] {
        var counts: [String: (kind: FilmSet.Kind, id: Int, name: String, owned: Int)] = [:]
        func add(_ kind: FilmSet.Kind, _ id: Int, _ name: String) {
            let key = FilmSet.id(kind, id)
            counts[key] = (kind, id, name, (counts[key]?.owned ?? 0) + 1)
        }
        for film in owned {
            if let collection = film.collection { add(.franchise, collection.id, collection.name) }
            var people = Set<String>()
            for member in film.crew {
                guard let id = member.id else { continue }
                for kind in [FilmSet.Kind.director, .cinematographer] where member.job == kind.job {
                    // Co-directors credited twice count once.
                    if people.insert("\(kind.rawValue):\(id)").inserted { add(kind, id, member.name) }
                }
            }
        }
        var result: [(kind: FilmSet.Kind, id: Int, name: String, owned: Int)] = []
        for kind in FilmSet.Kind.allCases {
            let ofKind = counts.values.filter { $0.kind == kind }
            // Franchises count from one film (you own part of it); people from two.
            let threshold = kind == .franchise ? 1 : minimumOwned
            result += ofKind
                .filter { $0.owned >= threshold }
                .sorted { $0.owned != $1.owned ? $0.owned > $1.owned : $0.name < $1.name }
                .prefix(limit)
        }
        return result
    }
}

/// The saved sets: "Sets.json" in List Data, each refreshed after a month.
public struct FilmSetsFile: Codable, Equatable, Sendable {
    public var sets: [FilmSet]

    public init(sets: [FilmSet] = []) {
        self.sets = sets
    }
}
