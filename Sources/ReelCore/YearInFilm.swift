import Foundation

/// One watched film, as Year in Film needs it.
public struct YearFilm: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let releaseYear: Int?
    public let watchedOn: Date
    public let runtime: Int?
    public let genres: [String]
    public let directors: [String]
    /// Your own stars, if you rated it.
    public let yourRating: Int?
    public let score: Double?
    /// The original language ("ko").
    public let language: String?
    /// The leads, billing order.
    public let cast: [String]
    /// Seen somewhere else (its date is a guess or a month, not a night).
    public let elsewhere: Bool

    public init(id: String, title: String, releaseYear: Int?, watchedOn: Date, runtime: Int?, genres: [String],
                directors: [String], yourRating: Int?, score: Double?, language: String? = nil,
                cast: [String] = [], elsewhere: Bool = false) {
        self.id = id
        self.title = title
        self.releaseYear = releaseYear
        self.watchedOn = watchedOn
        self.runtime = runtime
        self.genres = genres
        self.directors = directors
        self.yourRating = yourRating
        self.score = score
        self.language = language
        self.cast = cast
        self.elsewhere = elsewhere
    }
}

/// A few facts about a film outside the library: one you saw somewhere else (so Year in Film
/// can count it like a film from your drives) or one a list suggests. Downloaded again if lost.
public struct FilmBrief: Codable, Equatable, Sendable {
    public var title: String
    public var year: Int?
    public var runtime: Int?
    public var genres: [String]
    public var directors: [String]
    public var posterPath: String?
    public var backdropPath: String?
    public var voteAverage: Double?
    /// When it came out ("2004-11-20"); missing in briefs kept before Reel 1.7.
    public var released: String?
    /// The original language and leads, for Year in Film (missing before Reel 1.8).
    public var language: String?
    public var cast: [String]?

    public init(title: String, year: Int?, runtime: Int?, genres: [String], directors: [String], posterPath: String?,
                backdropPath: String?, voteAverage: Double?, released: String? = nil, language: String? = nil,
                cast: [String]? = nil) {
        self.title = title
        self.year = year
        self.runtime = runtime
        self.genres = genres
        self.directors = directors
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.voteAverage = voteAverage
        self.released = released
        self.language = language
        self.cast = cast
    }

    public init(_ details: TMDBMovieDetails) {
        self.init(title: details.title, year: details.year, runtime: details.runtime.flatMap { $0 > 0 ? $0 : nil },
                  genres: details.genreNames, directors: details.directors, posterPath: details.posterPath,
                  backdropPath: details.backdropPath, voteAverage: details.voteAverage, released: details.releaseDate,
                  language: details.originalLanguage ?? "",
                  cast: YearFilm.leads(details))
    }

    /// The same, as Year in Film counts it.
    public func yearFilm(id: String, watchedOn: Date, yourRating: Int?) -> YearFilm {
        YearFilm(id: id, title: title, releaseYear: year, watchedOn: watchedOn, runtime: runtime, genres: genres,
                 directors: directors, yourRating: yourRating, score: voteAverage, language: language,
                 cast: cast ?? [], elsewhere: true)
    }
}

extension YearFilm {
    /// The four leads, in billing order.
    public static func leads(_ details: TMDBMovieDetails?) -> [String] {
        (details?.credits?.cast ?? []).sorted { ($0.order ?? 999) < ($1.order ?? 999) }.prefix(4).map(\.name)
    }
}

/// When a film seen elsewhere was most likely seen: in the cinema, the month after it came out.
public enum SeenDate {
    /// The middle of the month after `released` ("2004-11-20" gives 15 December 2004), or now
    /// when that month hasn't come yet; nil when the release date isn't known.
    public static func afterRelease(_ released: String?, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let released else { return nil }
        let parts = released.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2, parts[0] > 1800, (1...12).contains(parts[1]) else { return nil }
        let month = parts[1] == 12 ? 1 : parts[1] + 1
        let year = parts[1] == 12 ? parts[0] + 1 : parts[0]
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 15)) else { return nil }
        // This month or later: now (never a day still to come).
        let today = calendar.dateComponents([.year, .month], from: now)
        if (year, month) >= (today.year ?? 0, today.month ?? 0) { return now }
        return date
    }
}

public struct Tally: Equatable, Sendable, Identifiable {
    public let name: String
    public let count: Int
    public var id: String { name }
}

/// A year of watching, worked out from the films you marked as watched (with the date).
public struct YearInFilm: Equatable, Sendable {
    public let year: Int
    /// Oldest viewing first.
    public let films: [YearFilm]
    public let minutes: Int
    /// Films per month, January first.
    public let months: [Int]
    public let topGenres: [Tally]
    /// Directors you watched at least twice.
    public let topDirectors: [Tally]
    public let decades: [Tally]
    /// Your highest rated film of the year (else the best reviewed one).
    public let favourite: YearFilm?
    public let longest: YearFilm?
    public let oldest: YearFilm?
    // In numbers:
    /// The average running time, in minutes.
    public let averageRuntime: Int?
    /// The average of your stars (with at least two rated).
    public let averageStars: Double?
    /// Films that came out that same year.
    public let newReleases: Int
    /// The month with the most films (0 = January), when one stands out.
    public let busiestMonth: Int?
    /// The day of the week you watch most (1 = Sunday), from nights on your drives; when one stands out.
    public let favouriteWeekday: Int?
    public let languages: [Tally]
    public let languageCount: Int
    /// Actors in at least two of the year's films.
    public let topActors: [Tally]

    public init(year: Int, from all: [YearFilm], calendar: Calendar = .current) {
        self.year = year
        films = all.filter { calendar.component(.year, from: $0.watchedOn) == year }.sorted { $0.watchedOn < $1.watchedOn }
        minutes = films.reduce(0) { $0 + ($1.runtime ?? 0) }

        var months = Array(repeating: 0, count: 12)
        for film in films { months[calendar.component(.month, from: film.watchedOn) - 1] += 1 }
        self.months = months

        topGenres = Self.tally(films.flatMap { $0.genres }, minimum: 1, limit: 4)
        topDirectors = Self.tally(films.flatMap { $0.directors }, minimum: 2, limit: 3)
        decades = Self.tally(films.compactMap { $0.releaseYear.map { "\($0 / 10 * 10)s" } }, minimum: 1, limit: 12)
            .sorted { $0.name < $1.name }

        let rated = films.filter { $0.yourRating != nil }
        favourite = rated.isEmpty
            ? films.max { ($0.score ?? 0) < ($1.score ?? 0) }
            : rated.max { ($0.yourRating ?? 0, $0.score ?? 0) < ($1.yourRating ?? 0, $1.score ?? 0) }
        longest = films.filter { $0.runtime != nil }.max { ($0.runtime ?? 0) < ($1.runtime ?? 0) }
        oldest = films.filter { $0.releaseYear != nil }.min { ($0.releaseYear ?? 0) < ($1.releaseYear ?? 0) }

        let timed = films.compactMap(\.runtime)
        averageRuntime = timed.isEmpty ? nil : timed.reduce(0, +) / timed.count
        let stars = films.compactMap(\.yourRating)
        averageStars = stars.count < 2 ? nil : Double(stars.reduce(0, +)) / Double(stars.count)
        newReleases = films.filter { $0.releaseYear == year }.count
        let busiest = months.enumerated().max { $0.element < $1.element }
        busiestMonth = busiest.flatMap { top in months.filter { $0 == top.element }.count == 1 && top.element >= 2 ? top.offset : nil }
        var nights = Array(repeating: 0, count: 8)
        for film in films where !film.elsewhere { nights[calendar.component(.weekday, from: film.watchedOn)] += 1 }
        let night = nights.enumerated().max { $0.element < $1.element }
        favouriteWeekday = night.flatMap { top in nights.filter { $0 == top.element }.count == 1 && top.element >= 3 ? top.offset : nil }
        let spoken = films.compactMap { $0.language.flatMap { $0.isEmpty ? nil : FilmLanguage.name($0) } }
        languages = Self.tally(spoken, minimum: 1, limit: 4)
        languageCount = Set(spoken).count
        topActors = Self.tally(films.flatMap(\.cast), minimum: 2, limit: 4)
    }

    /// Years with at least one dated viewing, newest first.
    public static func years(in films: [YearFilm], calendar: Calendar = .current) -> [Int] {
        Set(films.map { calendar.component(.year, from: $0.watchedOn) }).sorted(by: >)
    }

    /// Most common first; ties alphabetically.
    static func tally(_ names: [String], minimum: Int, limit: Int) -> [Tally] {
        var counts: [String: Int] = [:]
        for name in names where !name.isEmpty { counts[name, default: 0] += 1 }
        return counts
            .filter { $0.value >= minimum }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { Tally(name: $0.key, count: $0.value) }
    }
}
