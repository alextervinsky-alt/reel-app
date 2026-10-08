import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Lists

/// A list in the Lists hub.
public enum FilmListKind: Hashable, Codable, Sendable {
    /// The 100 best-rated films of one year on IMDb.
    case imdbYear(Int)
    /// The 250 highest-rated films of all time on IMDb.
    case imdbAllTime
    /// Award winners and nominees, or a collection, from Wikidata.
    case award(AwardList)
    /// Sight and Sound's poll of critics: the 100 greatest films of all time.
    case sightAndSound

    public var title: String {
        switch self {
        case .imdbYear(let year): "IMDb Top 100 of \(year)"
        case .imdbAllTime: "IMDb Top 250"
        case .award(let award): award.title
        case .sightAndSound: "The Greatest Films of All Time"
        }
    }

    public var subtitle: String {
        switch self {
        case .imdbYear: "The year's best-rated films, ranked by IMDb rating and number of votes"
        case .imdbAllTime: "The highest-rated films of all time, ranked by IMDb rating and number of votes"
        case .award(let award): award.subtitle
        case .sightAndSound: "Sight and Sound's 2022 poll of 1,639 critics, held once a decade since 1952"
        }
    }

    /// A warning when the list is known to be incomplete.
    public var coverageNote: String? {
        if case .award(let award) = self { return award.coverageNote }
        return nil
    }

    public var usesIMDb: Bool {
        switch self {
        case .imdbYear, .imdbAllTime: true
        default: false
        }
    }

    /// Lists that have nominees as well as winners.
    public var hasNominees: Bool {
        if case .award(let award) = self { return award != .criterion }
        return false
    }
}

/// One film on a list. IMDb lists know the IMDb id; Wikidata lists usually know both ids.
public struct ListFilm: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var imdbID: String?
    public var tmdbID: Int?
    public var title: String
    public var year: Int?
    /// "8.6 · 2.4M votes", "Won 1995 · Christopher Nolan", "Spine #1"
    public var note: String?
    /// Award lists: won (true) or only nominated (false). Nil for other lists.
    public var won: Bool?
    /// The number shown in front: a poll rank ("21" for a tie) or the year.
    public var rank: String?

    public init(imdbID: String?, tmdbID: Int?, title: String, year: Int?, note: String?, won: Bool? = nil, rank: String? = nil) {
        self.imdbID = imdbID
        self.tmdbID = tmdbID
        self.title = title
        self.year = year
        self.note = note
        self.won = won
        self.rank = rank
    }

    /// Also the key under which the film's TMDB poster and id are remembered.
    public var id: String { ListFilm.key(imdbID: imdbID, tmdbID: tmdbID) ?? "title:\(TitleSimilarity.normalize(title))|\(year ?? 0)" }

    public static func key(imdbID: String?, tmdbID: Int?) -> String? {
        if let imdbID, !imdbID.isEmpty { return imdbID }
        return tmdbID.map { "tmdb:\($0)" }
    }

    /// Winners, and every film on lists without nominees.
    public var isWinner: Bool { won != false }

    public init(_ film: IMDbFilm) {
        self.init(imdbID: film.id, tmdbID: nil, title: film.title, year: film.year,
                  note: String(format: "%.1f", film.rating) + " · " + ListFilm.votes(film.votes) + " votes")
    }

    static func votes(_ count: Int) -> String {
        count >= 1_000_000 ? String(format: "%.1fM", Double(count) / 1_000_000) : "\(count / 1_000)K"
    }
}

/// What Reel remembers about a list film from TMDB: enough for its poster and preview.
public struct ResolvedFilm: Codable, Equatable, Hashable, Sendable {
    public var tmdbID: Int
    public var posterPath: String?
    public var backdropPath: String?
    public var voteAverage: Double?
    public var voteCount: Int?
    /// Its genres (nil in copies saved before Reel kept them: those are looked up again).
    public var genres: [String]?
    /// When it was fetched; looked up again after a month so posters and scores stay current.
    public var fetchedAt: Date?

    public init(tmdbID: Int, posterPath: String?, backdropPath: String?, voteAverage: Double?, voteCount: Int?,
                genres: [String]? = nil, fetchedAt: Date? = Date()) {
        self.tmdbID = tmdbID
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.genres = genres
        self.fetchedAt = fetchedAt
    }

    public init(_ movie: TMDBMovieSummary) {
        self.init(tmdbID: movie.id, posterPath: movie.posterPath, backdropPath: movie.backdropPath,
                  voteAverage: movie.voteAverage, voteCount: movie.voteCount, genres: movie.genreNames)
    }

    public init(_ details: TMDBMovieDetails) {
        self.init(tmdbID: details.id, posterPath: details.posterPath, backdropPath: details.backdropPath,
                  voteAverage: details.voteAverage, voteCount: details.voteCount, genres: details.genreNames)
    }
}

// MARK: - Awards, festivals and collections (Wikidata)

public enum AwardList: String, CaseIterable, Codable, Sendable, Identifiable {
    case oscarBestPicture, oscarDirector, oscarCinematography, oscarInternational, oscarAnimated
    case palmeDOr, goldenLion, goldenBear, goldenLeopard, baftaBestFilm, cesarBestFilm, europeanFilm
    case criterion

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oscarBestPicture: "Oscar for Best Picture"
        case .oscarDirector: "Oscar for Best Director"
        case .oscarCinematography: "Oscar for Best Cinematography"
        case .oscarInternational: "Oscar for Best International Film"
        case .oscarAnimated: "Oscar for Best Animated Film"
        case .palmeDOr: "Palme d'Or"
        case .goldenLion: "Golden Lion"
        case .goldenBear: "Golden Bear"
        case .goldenLeopard: "Golden Leopard"
        case .baftaBestFilm: "BAFTA for Best Film"
        case .cesarBestFilm: "César for Best Film"
        case .europeanFilm: "European Film of the Year"
        case .criterion: "The Criterion Collection"
        }
    }

    public var subtitle: String {
        switch self {
        case .oscarBestPicture: "The Academy Award for Best Picture"
        case .oscarDirector: "The films behind the Academy Award for Best Director"
        case .oscarCinematography: "The films behind the Academy Award for Best Cinematography"
        case .oscarInternational: "The Academy Award for Best International Feature"
        case .oscarAnimated: "The Academy Award for Best Animated Feature"
        case .palmeDOr: "The top prize of the Cannes Film Festival, and the films in competition"
        case .goldenLion: "The top prize of the Venice Film Festival, and the films in competition"
        case .goldenBear: "The top prize of the Berlin Film Festival, and the films in competition"
        case .goldenLeopard: "The top prize of the Locarno Film Festival, where new voices are found"
        case .baftaBestFilm: "The British Academy's Best Film award"
        case .cesarBestFilm: "France's own Academy Award for Best Film"
        case .europeanFilm: "The European Film Academy's Best Film"
        case .criterion: "Important classic and contemporary films, by spine number"
        }
    }

    /// Said on the list when Wikidata, its source, is known to miss years of the award.
    public var coverageNote: String? {
        switch self {
        case .oscarCinematography, .baftaBestFilm:
            "Wikidata, where this list comes from, doesn't record every year of this award yet, so some films are missing."
        default:
            nil
        }
    }

    /// Short name for cards: "Cannes", "Venice"…
    public var source: String {
        switch self {
        case .oscarBestPicture, .oscarDirector, .oscarCinematography, .oscarInternational, .oscarAnimated: "Academy Awards"
        case .palmeDOr: "Cannes"
        case .goldenLion: "Venice"
        case .goldenBear: "Berlinale"
        case .goldenLeopard: "Locarno"
        case .baftaBestFilm: "BAFTA"
        case .cesarBestFilm: "César Awards"
        case .europeanFilm: "European Film Awards"
        case .criterion: "Criterion"
        }
    }

    /// The award's English name on Wikidata (looked up by name, so no ids to go stale).
    var wikidataLabel: String {
        switch self {
        case .oscarBestPicture: "Academy Award for Best Picture"
        case .oscarDirector: "Academy Award for Best Director"
        case .oscarCinematography: "Academy Award for Best Cinematography"
        case .oscarInternational: "Academy Award for Best International Feature Film"
        case .oscarAnimated: "Academy Award for Best Animated Feature"
        case .palmeDOr: "Palme d'Or"
        case .goldenLion: "Golden Lion"
        case .goldenBear: "Golden Bear"
        case .goldenLeopard: "Golden Leopard"
        case .baftaBestFilm: "BAFTA Award for Best Film"
        case .cesarBestFilm: "César Award for Best Film"
        case .europeanFilm: "European Film Award for Best Film"
        case .criterion: "The Criterion Collection spine number"
        }
    }

    /// SPARQL for the list: films with their IMDb id (P345), TMDB id (P4947) and release date (P577).
    /// Winners are recorded on the film ("award received", P166), on the award ("winner", P1346)
    /// or, for awards given to people (director, cinematographer), on the person with the film as
    /// "for work" (P1686). Nominees the same way with "nominated for" (P1411).
    var query: String {
        let ids = """
          OPTIONAL { ?film wdt:P345 ?imdb . }
          OPTIONAL { ?film wdt:P4947 ?tmdb . }
          OPTIONAL { ?film wdt:P577 ?released . }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        """
        if self == .criterion {
            return """
            SELECT ?film ?filmLabel ?imdb ?tmdb ?released ?number WHERE {
              ?property rdfs:label "\(wikidataLabel)"@en ; wikibase:directClaim ?claim .
              ?film ?claim ?number .
            \(ids)
            }
            """
        }
        return """
        SELECT ?film ?filmLabel ?personLabel ?imdb ?tmdb ?released ?date ?won WHERE {
          ?award rdfs:label "\(wikidataLabel)"@en .
          {
            { ?film p:P166 ?statement . ?statement ps:P166 ?award . }
            UNION { ?award p:P1346 ?statement . ?statement ps:P1346 ?film . }
            UNION { ?person p:P166 ?statement . ?statement ps:P166 ?award . ?statement pq:P1686 ?film . }
            BIND("1" AS ?won)
          } UNION {
            { ?film p:P1411 ?statement . ?statement ps:P1411 ?award . }
            UNION { ?person p:P1411 ?statement . ?statement ps:P1411 ?award . ?statement pq:P1686 ?film . }
            BIND("0" AS ?won)
          }
          OPTIONAL { ?statement pq:P585 ?date . }
        \(ids)
        }
        """
    }
}

/// Reads award winners and the Criterion Collection from Wikidata's public query service.
public struct WikidataLists: Sendable {
    private let session: URLSession

    public init(session: URLSession = TMDBClient.sharedSession) {
        self.session = session
    }

    struct Response: Decodable {
        struct Value: Decodable { let value: String }
        struct Results: Decodable { let bindings: [[String: Value]] }
        let results: Results
    }

    public func films(_ list: AwardList) async throws -> [ListFilm] {
        let response: Response = try await Wikimedia.get(
            "https://query.wikidata.org/sparql", ["query": list.query, "format": "json"],
            session: session, accept: "application/sparql-results+json")
        return Self.films(from: response.results.bindings.map { $0.mapValues { $0.value } }, list: list)
    }

    /// One row per film: winners and nominees newest first, winners first within a year
    /// (Criterion by spine number). People who won the award themselves and entries without a
    /// name are left out.
    static func films(from rows: [[String: String]], list: AwardList) -> [ListFilm] {
        struct Draft {
            var title = ""
            var imdb: String?
            var tmdb: Int?
            var released: Int?
            var won = false
            var wonYear: Int?
            var nominatedYear: Int?
            var number: Int?
            var people: [String] = []
        }
        var drafts: [String: Draft] = [:]
        for row in rows {
            guard let film = row["film"] else { continue }
            var draft = drafts[film] ?? Draft()
            if let title = row["filmLabel"] { draft.title = title }
            if let imdb = row["imdb"], imdb.hasPrefix("tt") { draft.imdb = imdb }
            if let tmdb = row["tmdb"].flatMap(Int.init) { draft.tmdb = draft.tmdb ?? tmdb }
            if let year = row["released"].flatMap(Self.year) { draft.released = min(draft.released ?? year, year) }
            let won = row["won"] != "0"
            let year = row["date"].flatMap(Self.year)
            if won {
                draft.won = true
                if let year { draft.wonYear = min(draft.wonYear ?? year, year) }
            } else if let year {
                draft.nominatedYear = min(draft.nominatedYear ?? year, year)
            }
            // The person the award went to; not the film itself, and not a country (International Film).
            if list != .oscarInternational, let person = row["personLabel"], person != row["filmLabel"],
               !person.hasPrefix("Q") || person.contains(" "), won || !draft.won, !draft.people.contains(person) {
                draft.people.append(person)
            }
            if let number = row["number"].flatMap({ Int($0) }) { draft.number = min(draft.number ?? number, number) }
            drafts[film] = draft
        }
        let films = drafts.compactMap { uri, draft -> (ListFilm, Int)? in
            // An entity without an English name comes back as its id ("Q12345"); no ids at all means a person.
            let unnamed = draft.title.isEmpty || uri.hasSuffix("/" + draft.title)
            guard !unnamed, draft.imdb != nil || draft.tmdb != nil else { return nil }
            if list == .criterion {
                let film = ListFilm(imdbID: draft.imdb, tmdbID: draft.tmdb, title: draft.title, year: draft.released,
                                    note: draft.number.map { "Spine #\($0)" }, rank: draft.number.map { "#\($0)" })
                return (film, -(draft.number ?? Int.max / 2))
            }
            let year = (draft.won ? draft.wonYear : draft.nominatedYear) ?? draft.released
            var note = (draft.won ? "Won" : "Nominated") + (year.map { " \($0)" } ?? "")
            if !draft.people.isEmpty { note += " · " + draft.people.prefix(2).joined(separator: ", ") }
            let film = ListFilm(imdbID: draft.imdb, tmdbID: draft.tmdb, title: draft.title, year: draft.released,
                                note: note, won: draft.won, rank: year.map(String.init))
            // Newest first; within a year the winner first.
            return (film, (year ?? 0) * 2 + (draft.won ? 1 : 0))
        }
        return films.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title < $1.0.title }.map { $0.0 }
    }

    /// "1995-05-28T00:00:00Z" → 1995
    static func year(_ date: String) -> Int? {
        guard date.count >= 4, !date.hasPrefix("-"), let year = Int(date.prefix(4)), year > 1880 else { return nil }
        return year
    }
}

/// The saved copy of the award lists: "Award Lists.json" in List Data, refreshed weekly.
public struct AwardListsFile: Codable, Equatable, Sendable {
    /// Bumped when the lists gain information (2: nominees), so older copies are fetched again.
    public static let currentVersion = 2

    public var version: Int?
    public var lists: [String: [ListFilm]]
    public var fetchedAt: [String: Date]

    public init(lists: [String: [ListFilm]] = [:], fetchedAt: [String: Date] = [:]) {
        self.version = AwardListsFile.currentVersion
        self.lists = lists
        self.fetchedAt = fetchedAt
    }
}

// MARK: - Sight and Sound

/// Sight and Sound's critics' poll, held once a decade (the 2022 edition, from bfi.org.uk).
/// It only changes every ten years, so it comes with Reel; posters and TMDB ids are looked up
/// and refreshed like any other list.
public enum SightAndSound {
    /// Rank (shared ranks are ties), title as TMDB knows it, year.
    static let poll2022: [(Int, String, Int)] = [
        (1, "Jeanne Dielman, 23 quai du Commerce, 1080 Bruxelles", 1975), (2, "Vertigo", 1958), (3, "Citizen Kane", 1941),
        (4, "Tokyo Story", 1953), (5, "In the Mood for Love", 2000), (6, "2001: A Space Odyssey", 1968),
        (7, "Beau Travail", 1999), (8, "Mulholland Drive", 2001), (9, "Man with a Movie Camera", 1929),
        (10, "Singin' in the Rain", 1952), (11, "Sunrise: A Song of Two Humans", 1927), (12, "The Godfather", 1972),
        (13, "The Rules of the Game", 1939), (14, "Cléo from 5 to 7", 1962), (15, "The Searchers", 1956),
        (16, "Meshes of the Afternoon", 1943), (17, "Close-Up", 1990), (18, "Persona", 1966), (19, "Apocalypse Now", 1979),
        (20, "Seven Samurai", 1954), (21, "The Passion of Joan of Arc", 1928), (21, "Late Spring", 1949),
        (23, "Playtime", 1967), (24, "Do the Right Thing", 1989), (25, "The Night of the Hunter", 1955),
        (25, "Au Hasard Balthazar", 1966), (27, "Shoah", 1985), (28, "Daisies", 1966), (29, "Taxi Driver", 1976),
        (30, "Portrait of a Lady on Fire", 2019), (31, "Mirror", 1975), (31, "Psycho", 1960), (31, "8½", 1963),
        (34, "L'Atalante", 1934), (35, "Pather Panchali", 1955), (36, "City Lights", 1931), (36, "M", 1931),
        (38, "Some Like It Hot", 1959), (38, "Breathless", 1960), (38, "Rear Window", 1954),
        (41, "Bicycle Thieves", 1948), (41, "Rashomon", 1950), (43, "Killer of Sheep", 1978), (43, "Stalker", 1979),
        (45, "The Battle of Algiers", 1966), (45, "North by Northwest", 1959), (45, "Barry Lyndon", 1975),
        (48, "Wanda", 1970), (48, "Ordet", 1955), (50, "The 400 Blows", 1959), (50, "The Piano", 1993),
        (52, "Ali: Fear Eats the Soul", 1974), (52, "News from Home", 1977), (54, "Blade Runner", 1982),
        (54, "Battleship Potemkin", 1925), (54, "Contempt", 1963), (54, "Sherlock Jr.", 1924), (54, "The Apartment", 1960),
        (59, "Sans Soleil", 1983), (60, "Moonlight", 2016), (60, "La Dolce Vita", 1960), (60, "Daughters of the Dust", 1991),
        (63, "Casablanca", 1942), (63, "GoodFellas", 1990), (63, "The Third Man", 1949), (66, "Touki Bouki", 1973),
        (67, "The Gleaners and I", 2000), (67, "La Jetée", 1962), (67, "Andrei Rublev", 1966), (67, "Metropolis", 1927),
        (67, "The Red Shoes", 1948), (72, "My Neighbor Totoro", 1988), (72, "Journey to Italy", 1954),
        (72, "L'Avventura", 1960), (75, "Imitation of Life", 1959), (75, "Sansho the Bailiff", 1954),
        (75, "Spirited Away", 2001), (78, "Sátántangó", 1994), (78, "A Brighter Summer Day", 1991),
        (78, "Céline and Julie Go Boating", 1974), (78, "Sunset Boulevard", 1950), (78, "Modern Times", 1936),
        (78, "A Matter of Life and Death", 1946), (78, "Histoire(s) du cinéma", 1998), (85, "Pierrot le Fou", 1965),
        (85, "The Spirit of the Beehive", 1973), (85, "Blue Velvet", 1986), (88, "Chungking Express", 1994),
        (88, "The Shining", 1980), (90, "The Earrings of Madame de…", 1953), (90, "The Leopard", 1963),
        (90, "Ugetsu", 1953), (90, "Yi Yi", 2000), (90, "Parasite", 2019), (95, "Get Out", 2017),
        (95, "Tropical Malady", 2004), (95, "Black Girl", 1966), (95, "The General", 1926), (95, "A Man Escaped", 1956),
        (95, "Once Upon a Time in the West", 1968),
    ]

    public static let films: [ListFilm] = poll2022.map { rank, title, year in
        ListFilm(imdbID: nil, tmdbID: nil, title: title, year: year, note: nil, rank: String(rank))
    }
}

// MARK: - Badges on a film's page

/// "Palme d'Or · 1994", "Sight & Sound poll · #34": the lists a film is on, wins first.
public struct ListBadge: Equatable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let symbol: String
    public let isWin: Bool
    public let kind: FilmListKind
}

public enum ListBadges {
    /// The film's place on each list. A list film is the same film when its IMDb id, its TMDB id
    /// (looked up through `tmdbID`) or, for lists without ids, its title and year match.
    public static func badges(imdbID: String?, tmdbID: Int?, title: String, year: Int?,
                              lists: [(kind: FilmListKind, films: [ListFilm])],
                              tmdbIDOf: (ListFilm) -> Int?) -> [ListBadge] {
        let name = TitleSimilarity.normalize(title)
        func same(_ film: ListFilm) -> Bool {
            if let imdbID, let other = film.imdbID { return other == imdbID }
            if let tmdbID, let other = tmdbIDOf(film) { return other == tmdbID }
            return TitleSimilarity.normalize(film.title) == name && film.year == year
        }
        var result: [(order: Int, badge: ListBadge)] = []
        for (kind, films) in lists {
            guard let film = films.first(where: same) else { continue }
            switch kind {
            case .award(.criterion):
                result.append((2, ListBadge(id: "\(kind)", text: "Criterion Collection" + (film.note.map { " · \($0)" } ?? ""),
                                            symbol: "c.square", isWin: true, kind: kind)))
            case .award(let award):
                let won = film.won ?? true
                let when = film.rank.map { " · \($0)" } ?? ""
                result.append((won ? 0 : 4, ListBadge(id: "\(kind)", text: (won ? award.title : "Nominated: " + award.title) + when,
                                                      symbol: won ? "trophy.fill" : "trophy", isWin: won, kind: kind)))
            case .sightAndSound:
                result.append((1, ListBadge(id: "\(kind)", text: "Sight & Sound greatest films" + (film.rank.map { " · #\($0)" } ?? ""),
                                            symbol: "star.circle", isWin: true, kind: kind)))
            case .imdbAllTime, .imdbYear:
                let place = (films.firstIndex(of: film) ?? 0) + 1
                result.append((3, ListBadge(id: "\(kind)", text: "\(kind.title) · #\(place)", symbol: "list.number",
                                            isWin: true, kind: kind)))
            }
        }
        return result.sorted { $0.order < $1.order }.map { $0.badge }
    }
}

// MARK: - The same film on several lists

/// A film as the lists see it, gathered across them: the more (and the weightier) lists a film
/// is on, the surer a choice it is. Award lists count their winners.
public struct ListPick: Sendable {
    /// The film as one of its lists has it (one with a TMDB id when there is one).
    public let film: ListFilm
    /// Every list it's on, weightiest first.
    public let lists: [FilmListKind]
    /// How much the lists together say.
    public let weight: Double
    /// Its TMDB id, when a list or a lookup knows it.
    public let tmdbID: Int?
    /// The `ListFilm.id` of each of its entries, to find it from any of its lists.
    public let ids: [String]
}

public enum ListConsensus {
    /// How much being on a list says about a film: a once-a-decade critics' poll more than a
    /// collection, a top festival prize more than a national award.
    public static func weight(of kind: FilmListKind) -> Double {
        switch kind {
        case .sightAndSound: 1.6
        case .imdbAllTime: 1.0
        case .imdbYear: 0.5
        case .award(let award):
            switch award {
            case .palmeDOr: 1.3
            case .goldenLion, .oscarBestPicture: 1.1
            case .goldenBear: 1.0
            case .oscarInternational: 0.9
            case .oscarDirector, .goldenLeopard: 0.8
            case .baftaBestFilm, .oscarAnimated: 0.7
            case .oscarCinematography, .cesarBestFilm, .europeanFilm, .criterion: 0.6
            }
        }
    }

    /// The films on the given lists, each once: the same film on two lists is recognised by its
    /// IMDb id, its TMDB id (looked up through `tmdbIDOf`) or its title and year. Weightiest first.
    public static func gather(_ lists: [(kind: FilmListKind, films: [ListFilm])],
                              tmdbIDOf: (ListFilm) -> Int?) -> [ListPick] {
        var groupOf: [String: Int] = [:]
        var members: [[(kind: FilmListKind, film: ListFilm, tmdbID: Int?)]] = []
        var keysOf: [[String]] = []
        for (kind, films) in lists {
            for film in films where film.isWinner {
                let tmdbID = film.tmdbID ?? tmdbIDOf(film)
                var keys: [String] = []
                if let year = film.year { keys.append("t:" + TitleSimilarity.normalize(film.title) + "|\(year)") }
                if let imdb = film.imdbID, !imdb.isEmpty { keys.append(imdb) }
                if let tmdbID { keys.append("tmdb:\(tmdbID)") }
                let found = Set(keys.compactMap { groupOf[$0] }).sorted()
                let target: Int
                if let first = found.first {
                    target = first
                    // The film turned out to be on two groups' lists: they become one.
                    for other in found.dropFirst() {
                        members[target] += members[other]
                        members[other] = []
                        for key in keysOf[other] { groupOf[key] = target }
                        keysOf[target] += keysOf[other]
                        keysOf[other] = []
                    }
                } else {
                    target = members.count
                    members.append([])
                    keysOf.append([])
                }
                members[target].append((kind, film, tmdbID))
                for key in keys where groupOf[key] != target {
                    groupOf[key] = target
                    keysOf[target].append(key)
                }
            }
        }
        return members.compactMap { entries -> ListPick? in
            guard !entries.isEmpty else { return nil }
            var kinds: [FilmListKind] = []
            for entry in entries where !kinds.contains(entry.kind) { kinds.append(entry.kind) }
            kinds.sort { weight(of: $0) > weight(of: $1) }
            let film = entries.first { $0.tmdbID != nil }?.film ?? entries[0].film
            return ListPick(film: film, lists: kinds, weight: kinds.reduce(0) { $0 + weight(of: $1) },
                            tmdbID: entries.lazy.compactMap { $0.tmdbID }.first, ids: entries.map { $0.film.id })
        }
        .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.film.title < $1.film.title }
    }

    /// "Palme d'Or · Sight & Sound · +2": the weightiest lists a film is on, in a few words.
    public static func summary(_ kinds: [FilmListKind], limit: Int = 2) -> String {
        let names = kinds.prefix(limit).map(shortName)
        let more = kinds.count - names.count
        return names.joined(separator: " · ") + (more > 0 ? " · +\(more)" : "")
    }

    public static func shortName(_ kind: FilmListKind) -> String {
        switch kind {
        case .sightAndSound: "Sight & Sound"
        case .imdbAllTime: "IMDb Top 250"
        case .imdbYear(let year): "IMDb Top 100 of \(year)"
        case .award(let award):
            switch award {
            case .oscarBestPicture: "Best Picture"
            case .oscarDirector: "Oscar for Directing"
            case .oscarCinematography: "Oscar for Cinematography"
            case .oscarInternational: "Oscar, International"
            case .oscarAnimated: "Oscar, Animated"
            case .criterion: "Criterion"
            case .baftaBestFilm: "BAFTA Best Film"
            case .cesarBestFilm: "César Best Film"
            case .europeanFilm: "European Film Award"
            default: award.title
            }
        }
    }
}
