#if os(macOS)
import Foundation
import ReelCore

/// A place in the sidebar.
enum Shelf: Hashable {
    case all, tonight, recommended, newArrivals, unwatched, watchlist, favorites, watched, yearInFilm, needsCheck
    case genre(String)
    case drive(String)
    /// Films without a full copy on the Backup drive.
    case notOnBackup
    case forYou, explore, lists, wishlist

    /// Shelves shown as the poster grid (search and filters apply to them).
    var isLibrary: Bool { ![.forYou, .explore, .lists, .wishlist, .recommended, .yearInFilm, .tonight].contains(self) }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    /// A different order each launch and each time All Films is chosen (`AppModel.shuffleSeed`).
    case random, title, year, rating, added, runtime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .random: "Random"
        case .title: "Title"
        case .year: "Release Year"
        case .rating: "Rating"
        case .added: "Date Added"
        case .runtime: "Running Time"
        }
    }
}

struct FilmRoute: Hashable {
    let id: String
}

/// A director, cinematographer, actor… page.
struct PersonRoute: Hashable {
    let id: Int
    let name: String
}

/// "See all" for one Explore list.
struct DiscoverRoute: Hashable {
    let list: DiscoverList
    /// Only the films of this mood (Explore's mood chips).
    var mood: Mood? = nil
}

/// One list of the Lists hub (IMDb Top 100 of a year, an award…).
struct ListRoute: Hashable {
    let kind: FilmListKind
}

/// A franchise ("Blade Runner Collection") and how much of it you have.
struct FranchiseRoute: Hashable {
    let id: Int
    let name: String
}

/// Background work counted item by item, for the sidebar.
struct WorkProgress: Equatable {
    let label: String
    var done: Int
    let total: Int

    var text: String { "\(label)… \(min(done + 1, total)) of \(total)" }
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

/// How far along a list or set you are.
struct ListProgress: Equatable {
    var total: Int
    var owned = 0
    var seen = 0
    var wishlisted = 0

    var seenFraction: Double { total == 0 ? 0 : Double(seen) / Double(total) }
    var ownedFraction: Double { total == 0 ? 0 : Double(owned) / Double(total) }
}

/// A film from outside the library (Explore, a filmography, recommendations), for the preview sheet.
struct PreviewFilm: Identifiable, Hashable {
    let id: Int
    let title: String
    let year: Int?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let voteAverage: Double?
    let voteCount: Int
    let genres: [String]
    /// Extra line, e.g. "Director · Cinematographer" or "92% match".
    let note: String?

    init(id: Int, title: String, year: Int?, posterPath: String?, backdropPath: String?, voteAverage: Double?,
         voteCount: Int, genres: [String], note: String?) {
        self.id = id
        self.title = title
        self.year = year
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        overview = nil
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.genres = genres
        self.note = note
    }

    init(_ movie: TMDBMovieSummary, note: String? = nil) {
        id = movie.id
        title = movie.title
        year = movie.year
        posterPath = movie.posterPath
        backdropPath = movie.backdropPath
        overview = movie.overview
        voteAverage = movie.voteAverage
        voteCount = movie.voteCount ?? 0
        genres = movie.genreNames
        self.note = note
    }

    init(_ entry: FilmographyEntry) {
        id = entry.id
        title = entry.title
        year = entry.year
        posterPath = entry.posterPath
        backdropPath = entry.backdropPath
        overview = entry.overview
        voteAverage = entry.voteAverage
        voteCount = entry.voteCount
        genres = []
        note = entry.roles.prefix(2).joined(separator: " · ")
    }

    init(_ wish: WishlistFilm) {
        id = wish.id
        title = wish.title
        year = wish.year
        posterPath = wish.posterPath
        backdropPath = wish.backdropPath
        overview = nil
        voteAverage = nil
        voteCount = 0
        genres = []
        note = nil
    }

    init(_ film: ListFilm, art: ResolvedFilm) {
        id = art.tmdbID
        title = film.title
        year = film.year
        posterPath = art.posterPath
        backdropPath = art.backdropPath
        overview = nil
        voteAverage = art.voteAverage
        voteCount = art.voteCount ?? 0
        genres = []
        note = film.note
    }

    init(_ film: SetFilm) {
        id = film.id
        title = film.title
        year = film.year
        posterPath = film.posterPath
        backdropPath = film.backdropPath
        overview = nil
        voteAverage = nil
        voteCount = 0
        genres = []
        note = nil
    }

    /// A film you saw elsewhere (Year in Film).
    init(id: Int, seen: FilmBrief) {
        self.id = id
        title = seen.title
        year = seen.year
        posterPath = seen.posterPath
        backdropPath = seen.backdropPath
        overview = nil
        voteAverage = seen.voteAverage
        voteCount = 0
        genres = seen.genres
        note = nil
    }

    var wishlistEntry: WishlistFilm {
        WishlistFilm(id: id, title: title, year: year, posterPath: posterPath, backdropPath: backdropPath)
    }
}

/// Words a film can be found by, split by how strongly they count.
struct SearchIndex: Equatable {
    let title: String
    let people: String
    let tags: String
    let plot: String
    let words: [String]

    init(film: FilmEntry, moods: [Mood]) {
        let n = TitleSimilarity.normalize
        let d = film.tmdb
        let titles = [film.displayTitle, d?.originalTitle ?? "", film.parsed.title].map(n)
        title = (titles + [titles[0].replacingOccurrences(of: " ", with: "")]).joined(separator: " ")

        var names: [String] = []
        var tagWords: [String] = moods.map { $0.title } + film.parsed.badges
        if let d {
            names += (d.credits?.crew ?? []).map { $0.name }
            names += (d.credits?.cast ?? []).flatMap { [$0.name, $0.character ?? ""] }
            tagWords += d.genreNames + d.keywordNames
            tagWords += (d.productionCountries ?? []).map { $0.name }
            if let code = d.originalLanguage, let language = Locale(identifier: "en_US").localizedString(forLanguageCode: code) {
                tagWords.append(language)
            }
            if let collection = d.collection?.name { tagWords.append(collection) }
        }
        if let year = film.displayYear {
            let decade = year / 10 * 10
            tagWords += [String(year), "\(decade)s", String(format: "%02ds", decade % 100)]
        }
        if let rated = film.ratings?.rated { tagWords.append(rated) }
        if let awards = film.ratings?.awards?.lowercased() {
            if awards.contains("oscar") { tagWords += ["oscar", "oscars", "academy award"] }
            if awards.contains("won") { tagWords.append("award winning") }
        }
        if let quick = film.funFacts?.quick {
            tagWords += quick.basedOn + quick.filmedIn + quick.setIn + quick.notableAwards
        }
        tagWords += film.parsed.audioTracks.compactMap { $0.language }
        // "extras", "interview", "Chris Doyle"…
        let bonus = film.extras.filter { $0.kind.isBonus }
        if !bonus.isEmpty {
            tagWords += ["extras", "bonus"] + Set(bonus.map { $0.kind.label })
            tagWords += bonus.map { $0.title(removing: [film.displayTitle]) }
        }
        // Normalized per word list, not per name (this runs for every film on every rebuild).
        people = n(names.joined(separator: " , "))
        tags = n(tagWords.joined(separator: " , "))
        plot = n([d?.tagline ?? "", d?.overview ?? ""].joined(separator: " "))
        words = Array(Set((title + " " + people).split(separator: " ").map { String($0) }.filter { $0.count >= 3 }))
    }

    /// 0 when a term doesn't match anywhere; higher for title > people > tags > plot > near-miss.
    /// The typo-tolerant pass is only used when exact matching finds (almost) nothing.
    func relevance(_ terms: [String], allowTypos: Bool = false) -> Int {
        var total = 0
        for term in terms {
            var best = 0
            if title.contains(term) {
                best = title.hasPrefix(term) || title.contains(" " + term) ? 120 : 100
            } else if people.contains(term) {
                best = 60
            } else if tags.contains(term) {
                best = 40
            } else if plot.contains(term) {
                best = 15
            } else if allowTypos && term.count >= 4 {
                // Small typos: "blade runer", "villenueve".
                let allowed = term.count >= 7 ? 2 : 1
                if words.contains(where: { abs($0.count - term.count) <= allowed && TitleSimilarity.distance($0, term) <= allowed }) {
                    best = 8
                }
            }
            if best == 0 { return 0 }
            total += best
        }
        return total
    }
}

/// One film in the grid. The same film on the Main and Backup drive is one item with two copies.
/// Everything the grid sorts and filters by is worked out once here, not on every redraw.
struct LibraryItem: Identifiable, Equatable {
    let id: String
    let main: FilmEntry
    let copies: [FilmEntry]
    let isOnline: Bool
    /// Lowercased, accent-free title without a leading article, for fast sorting.
    let sortTitle: String
    let search: SearchIndex
    let moods: [Mood]
    let genres: Set<String>
    let keywords: Set<String>
    /// What "More Like This" compares (people, themes, tone, audience).
    let likeness: LikenessFeatures
    /// The film's original language ("ko"), for language rows and filters.
    let language: String?
    let runtime: Int?
    let score: Double?
    /// When the film first appeared in the library (earliest of its copies).
    let firstAdded: Date
    /// Short genre for captions, e.g. "Sci-Fi".
    let shortGenre: String?
    /// Changes whenever anything a poster card shows changes; lets the grid skip redrawing cards.
    let stamp: Int

    init(key: String, main: FilmEntry, copies: [FilmEntry], isOnline: Bool, moods: [Mood]) {
        self.id = key
        self.main = main
        self.copies = copies
        self.isOnline = isOnline

        var title = TitleSimilarity.normalize(main.displayTitle)
        for article in ["a ", "an "] where title.hasPrefix(article) && title.count > article.count {
            title.removeFirst(article.count)
            break
        }
        self.sortTitle = title

        let d = main.tmdb
        self.genres = Set(d?.genreNames ?? [])
        self.keywords = Set(d?.keywordNames ?? [])
        self.likeness = LikenessFeatures(
            tmdbID: d?.id, directors: d?.directors ?? [], writers: d?.writers ?? [],
            cinematographers: d?.cinematographers ?? [], cast: d.map { $0.topCast.prefix(5).map { $0.name } } ?? [],
            composers: d.map { $0.people(forJobs: TMDBMovieDetails.composerJobs).map { $0.name } } ?? [],
            genres: d?.genreNames ?? [], keywords: d?.keywordNames ?? [], moods: moods, year: main.displayYear)
        self.language = FilmLanguage.code(d?.originalLanguage)
        self.firstAdded = copies.map { $0.addedAt }.min() ?? main.addedAt
        self.shortGenre = d?.genreNames.first.map { LibraryItem.shortGenreNames[$0] ?? $0 }
        self.runtime = d?.runtime
        self.score = main.score
        self.moods = moods
        self.search = SearchIndex(film: main, moods: moods)
        var hasher = Hasher()
        hasher.combine(main.id)
        hasher.combine(main.displayTitle)
        hasher.combine(main.displayYear)
        hasher.combine(d?.posterPath)
        hasher.combine(main.matchState.rawValue)
        hasher.combine(main.ratings?.imdb)
        hasher.combine(main.ratings?.rottenTomatoes)
        hasher.combine(main.ratings?.metacritic)
        hasher.combine(main.score)
        hasher.combine(isOnline)
        self.stamp = hasher.finalize()
    }

    static let shortGenreNames = [
        "Science Fiction": "Sci-Fi", "Documentary": "Doc", "TV Movie": "TV Film", "Animation": "Animated",
    ]
}

/// Film info fetched for one TMDB id.
struct FilmInfo: Sendable {
    let details: TMDBMovieDetails
    let ratings: ExternalRatings?
    let reception: ReceptionSummary?
    let funFacts: FunFacts?
    /// Wikipedia couldn't be reached: the film is refreshed again next launch for its fun facts
    /// and critics' lines.
    let findingsFailed: Bool
    /// Ratings were wanted but OMDb couldn't give them (daily limit, offline): keep the old
    /// ones and try again later.
    let ratingsFailed: Bool
    /// OMDb refused the key (or the daily limit is reached): stop asking for this run.
    let ratingsRefused: Bool
    /// Ratings weren't asked for (still fresh): keep the stored ones.
    let ratingsSkipped: Bool

    /// Stores this info in a library entry.
    func store(in entry: inout FilmEntry) {
        if ratingsSkipped {
            entry.applyDetails(details, reception: reception)
        } else {
            entry.apply(details, ratings: ratings, ratingsFailed: ratingsFailed, reception: reception)
        }
        if let funFacts { entry.funFacts = funFacts }
        if findingsFailed { entry.infoVersion = FilmEntry.currentInfoVersion - 1 }
    }
}

enum FilmTab: String, CaseIterable, Identifiable {
    case overview, reviews, behindTheFilm, cinematography, extras

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .reviews: "Reviews"
        case .behindTheFilm: "Behind the Film"
        case .cinematography: "Cinematography"
        case .extras: "Extras"
        }
    }
}

struct LookupJob: Sendable {
    let id: String
    let fileName: String
    /// File name title, folder title… (see `FilmEntry.lookupTitles`).
    let titles: [String]
    let year: Int?
    /// A match the user fixed earlier; skips the search.
    let correctedID: Int?
}

enum LookupOutcome: Sendable {
    case matched(MatchResult, FilmInfo?)
    case corrected(FilmInfo)
    case failed(String)
    case offline
    case unauthorized
}
#endif
