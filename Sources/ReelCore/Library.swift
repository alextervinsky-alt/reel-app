import Foundation

// MARK: - Drive scanning (zero-touch: only folder listings, never file contents)

public struct ScannedFile: Codable, Equatable, Sendable {
    public var relativePath: String
    public var fileName: String
    public var size: Int64
    public var modified: Date?
    /// Bonus videos, subtitles, notes and artwork that belong to this film.
    public var extras: [FilmExtra]

    public init(relativePath: String, fileName: String, size: Int64, modified: Date?, extras: [FilmExtra] = []) {
        self.relativePath = relativePath
        self.fileName = fileName
        self.size = size
        self.modified = modified
        self.extras = extras
    }
}

public enum DriveScanner {
    /// System folders of Mac and Windows drives.
    public static let ignoredFolders: Set<String> = [
        "$recycle.bin", "recycler", "system volume information", "lost+found", "backups.backupdb",
    ]

    /// Smaller video files are trailers, samples or leftovers, not films.
    public static let defaultMinimumSize: Int64 = 30_000_000

    /// Lists the films under `root`, each with its extras (see `FilmGrouping`), with the user's
    /// grouping fixes applied. Reads names, sizes and dates from the folder listing only: no file
    /// is ever opened, read or changed, and nothing is written to the drive.
    /// - Parameter progress: told how many files have been read so far (every 250 files).
    public static func scan(root: URL, fixes: GroupingFixes = GroupingFixes(),
                            minimumSize: Int64 = defaultMinimumSize, progress: ((Int) -> Void)? = nil) -> [ScannedFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        let rootPrefix = folderPrefix(root.standardizedFileURL.path)
        let resolvedPrefix = folderPrefix(root.resolvingSymlinksInPath().path)
        let keySet = Set(keys)
        var files: [FilmGrouping.File] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keySet) else { continue }
            if values.isDirectory == true {
                if ignoredFolders.contains(url.lastPathComponent.lowercased()) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }

            // The enumerator builds paths from `root`, so a plain prefix check works; resolving
            // links (a disk access) is only the fallback.
            var relative = url.lastPathComponent
            let path = url.standardizedFileURL.path
            if path.hasPrefix(rootPrefix) {
                relative = String(path.dropFirst(rootPrefix.count))
            } else {
                let resolved = url.resolvingSymlinksInPath().path
                if resolved.hasPrefix(resolvedPrefix) { relative = String(resolved.dropFirst(resolvedPrefix.count)) }
            }
            files.append(FilmGrouping.File(relativePath: relative, size: Int64(values.fileSize ?? 0),
                                           modified: values.contentModificationDate))
            if files.count % 250 == 0 { progress?(files.count) }
        }
        return fixes.apply(to: FilmGrouping.group(files, minimumSize: minimumSize))
    }

    private static func folderPrefix(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }
}

// MARK: - Drives

/// A film drive (or a folder on one). Recognised by the volume's built-in ID, so two drives
/// with the same name, or a drive that mounts under a new name, are never mixed up.
public struct Drive: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var volumeUUID: String?
    /// Folder inside the volume, "" for the whole drive.
    public var folderInVolume: String
    public var lastKnownPath: String
    /// A mirror of another drive: Play prefers the other drives, and Reel lists the films missing here.
    public var isBackup: Bool
    /// Films found on this drive after this moment count as new arrivals. Set when the drive is
    /// first scanned, so a drive's first scan never floods New Arrivals.
    public var arrivalsSince: Date?
    /// The last complete scan, for "Backup last scanned 12 days ago".
    public var lastScanned: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, volumeUUID, folderInVolume, lastKnownPath, isBackup, arrivalsSince, lastScanned
    }

    public init(id: String = UUID().uuidString, name: String, volumeUUID: String?, folderInVolume: String, lastKnownPath: String,
                isBackup: Bool = false, arrivalsSince: Date? = nil, lastScanned: Date? = nil) {
        self.id = id
        self.name = name
        self.volumeUUID = volumeUUID
        self.folderInVolume = folderInVolume
        self.lastKnownPath = lastKnownPath
        self.isBackup = isBackup
        self.arrivalsSince = arrivalsSince
        self.lastScanned = lastScanned
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        volumeUUID = try c.decodeIfPresent(String.self, forKey: .volumeUUID)
        folderInVolume = try c.decodeIfPresent(String.self, forKey: .folderInVolume) ?? ""
        lastKnownPath = try c.decodeIfPresent(String.self, forKey: .lastKnownPath) ?? ""
        // Drives added before 1.0 named their mirror "… (Backup)".
        isBackup = try c.decodeIfPresent(Bool.self, forKey: .isBackup) ?? name.hasSuffix("(Backup)")
        arrivalsSince = try c.decodeIfPresent(Date.self, forKey: .arrivalsSince)
        lastScanned = try c.decodeIfPresent(Date.self, forKey: .lastScanned)
    }
}

// MARK: - Library

public enum MatchState: String, Codable, Sendable {
    case pending, auto, review, manual, confirmed, failed

    /// True when Reel isn't sure which film this is.
    public var needsCheck: Bool { self == .review || self == .manual || self == .failed }
}

public struct FilmEntry: Codable, Identifiable, Equatable, Sendable {
    public private(set) var id: String
    public private(set) var driveID: String
    public private(set) var relativePath: String
    public let fileName: String
    public var size: Int64
    public var modified: Date?
    public var addedAt: Date
    public var matchState: MatchState
    public var matchScore: Double?
    public var tmdb: TMDBMovieDetails?
    public var candidates: [ScoredCandidate]
    public var lastError: String?
    /// IMDb, Rotten Tomatoes and Metacritic scores.
    public var ratings: ExternalRatings?
    /// What reviewers like and dislike.
    public var reception: ReceptionSummary?
    /// Which generation of film info this entry holds; older entries are refreshed in the background.
    public var infoVersion: Int
    /// When TMDB was last searched for this file (used to retry unknown files only now and then).
    public var lastLookup: Date?
    /// Ratings couldn't be fetched last time; tried again at most once a day, ratings only.
    public var ratingsDue: Bool
    public var ratingsTriedAt: Date?
    /// Behind-the-scenes facts, Quick facts and critics' notes from Wikipedia and Wikidata.
    public var funFacts: FunFacts?
    /// Stills that passed the on-device check (no text, no film gear), once checked.
    public var checkedStills: [String]?
    /// When the TMDB and Wikipedia info was last fetched; it's fetched again after a month.
    public var infoUpdatedAt: Date?
    /// Which version of the stills check `checkedStills` comes from; older results are checked again.
    public var checkedStillsVersion: Int?
    public static let currentStillsCheck = 2
    /// Bonus videos, subtitles, notes and artwork found with the film (from the last scan).
    public var extras: [FilmExtra]
    /// Read from the file name once, not stored on disk (so parser improvements apply automatically).
    public let parsed: ParsedFilename

    enum CodingKeys: String, CodingKey {
        case driveID, relativePath, fileName, size, modified, addedAt, matchState, matchScore, tmdb, candidates, lastError
        case ratings, reception, infoVersion, lastLookup, ratingsDue, ratingsTriedAt, funFacts, checkedStills, extras
        case infoUpdatedAt, checkedStillsVersion
    }

    /// Bump when Reel starts storing more film info, so existing entries get refreshed.
    /// 5: trailers are kept even when a film has many other videos.
    public static let currentInfoVersion = 5

    public init(
        driveID: String, relativePath: String, fileName: String, size: Int64, modified: Date?,
        addedAt: Date, matchState: MatchState = .pending, tmdb: TMDBMovieDetails? = nil, extras: [FilmExtra] = []
    ) {
        self.id = FilmEntry.makeID(driveID: driveID, relativePath: relativePath)
        self.driveID = driveID
        self.relativePath = relativePath
        self.fileName = fileName
        self.size = size
        self.modified = modified
        self.addedAt = addedAt
        self.matchState = matchState
        self.matchScore = nil
        self.tmdb = tmdb
        self.candidates = []
        self.lastError = nil
        self.ratings = nil
        self.reception = nil
        self.infoVersion = 0
        self.lastLookup = nil
        self.ratingsDue = false
        self.ratingsTriedAt = nil
        self.funFacts = nil
        self.checkedStills = nil
        self.infoUpdatedAt = nil
        self.checkedStillsVersion = nil
        self.extras = extras
        self.parsed = FilenameParser.parse(fileName)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        driveID = try c.decode(String.self, forKey: .driveID)
        relativePath = try c.decode(String.self, forKey: .relativePath)
        fileName = try c.decode(String.self, forKey: .fileName)
        size = try c.decode(Int64.self, forKey: .size)
        modified = try c.decodeIfPresent(Date.self, forKey: .modified)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        matchState = try c.decode(MatchState.self, forKey: .matchState)
        matchScore = try c.decodeIfPresent(Double.self, forKey: .matchScore)
        tmdb = try c.decodeIfPresent(TMDBMovieDetails.self, forKey: .tmdb)
        candidates = try c.decodeIfPresent([ScoredCandidate].self, forKey: .candidates) ?? []
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        ratings = try c.decodeIfPresent(ExternalRatings.self, forKey: .ratings)
        reception = try c.decodeIfPresent(ReceptionSummary.self, forKey: .reception)
        infoVersion = try c.decodeIfPresent(Int.self, forKey: .infoVersion) ?? 1
        lastLookup = try c.decodeIfPresent(Date.self, forKey: .lastLookup)
        ratingsDue = try c.decodeIfPresent(Bool.self, forKey: .ratingsDue) ?? false
        ratingsTriedAt = try c.decodeIfPresent(Date.self, forKey: .ratingsTriedAt)
        funFacts = try c.decodeIfPresent(FunFacts.self, forKey: .funFacts)
        checkedStills = try c.decodeIfPresent([String].self, forKey: .checkedStills)
        extras = try c.decodeIfPresent([FilmExtra].self, forKey: .extras) ?? []
        infoUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .infoUpdatedAt)
        checkedStillsVersion = try c.decodeIfPresent(Int.self, forKey: .checkedStillsVersion)
        if checkedStillsVersion != FilmEntry.currentStillsCheck { checkedStills = nil }
        if infoUpdatedAt == nil, let id = tmdb?.id {
            // Saved before Reel kept this date: spread the first refresh over the coming month
            // instead of refreshing every film at once.
            infoUpdatedAt = Date().addingTimeInterval(-Double(id % 30) * 86_400)
        }
        id = FilmEntry.makeID(driveID: driveID, relativePath: relativePath)
        parsed = FilenameParser.parse(fileName)
    }

    public static func makeID(driveID: String, relativePath: String) -> String {
        driveID + "|" + relativePath
    }

    /// The file moved to another folder on the same drive.
    public mutating func relocate(to newRelativePath: String) {
        relativePath = newRelativePath
        id = FilmEntry.makeID(driveID: driveID, relativePath: newRelativePath)
    }

    public var displayTitle: String { tmdb?.title ?? parsed.title }

    /// Best single score out of 10 for sorting and the grid: IMDb, else TMDB.
    public var score: Double? {
        if let imdb = ratings?.imdb { return imdb }
        if let vote = tmdb?.voteAverage, vote > 0 { return vote }
        return nil
    }

    /// Stores freshly fetched film info. When the ratings couldn't be fetched, the old ones are
    /// kept and only the ratings are tried again later (see `ratingsDue`).
    public mutating func apply(_ details: TMDBMovieDetails, ratings: ExternalRatings?, ratingsFailed: Bool = false,
                               reception: ReceptionSummary?, now: Date = Date()) {
        applyDetails(details, reception: reception)
        applyRatings(ratings, failed: ratingsFailed, now: now)
    }

    /// New TMDB info only; ratings stay as they are.
    public mutating func applyDetails(_ details: TMDBMovieDetails, reception: ReceptionSummary?) {
        if tmdb?.id != details.id { funFacts = nil }
        if tmdb?.stillPaths != details.stillPaths { checkedStills = nil }
        tmdb = details
        self.reception = reception
        infoVersion = FilmEntry.currentInfoVersion
        infoUpdatedAt = Date()
    }

    /// How long fetched film info is kept before it's fetched again (ratings change, Wikipedia
    /// articles grow, new stills and trailers appear).
    public static let infoMaxAge: TimeInterval = 30 * 86_400

    /// The info is from an older version of Reel, or more than a month old.
    public func infoStale(now: Date = Date()) -> Bool {
        infoVersion < FilmEntry.currentInfoVersion
            || (infoUpdatedAt ?? .distantPast) < now.addingTimeInterval(-FilmEntry.infoMaxAge)
    }

    /// When the ratings are worth fetching again (missing, or older than a month).
    public func ratingsStale(now: Date = Date()) -> Bool {
        guard ratings != nil else { return true }
        // Ratings saved before Reel recorded the date count as fresh (saves the OMDb daily quota).
        guard let tried = ratingsTriedAt else { return false }
        return tried < now.addingTimeInterval(-30 * 86_400)
    }

    public mutating func applyRatings(_ ratings: ExternalRatings?, failed: Bool, now: Date = Date()) {
        ratingsTriedAt = now
        if failed {
            ratingsDue = self.ratings == nil
        } else {
            self.ratings = ratings
            ratingsDue = false
        }
    }
    public var displayYear: Int? { tmdb?.year ?? parsed.year }

    // MARK: Looking the film up

    /// Folder names that say nothing about the film inside.
    static let genericFolders: Set<String> = [
        "films", "film", "movies", "movie", "filmid", "kino", "video", "videos", "downloads", "download",
        "collection", "new", "misc", "other", "4k", "uhd", "hd", "bluray", "complete",
    ]

    /// What the folder holding the file says, e.g. "Rosetta" for "Rosetta/Rosetta, Dardenne, 1999.avi".
    var folderParsed: ParsedFilename? {
        let parts = relativePath.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        let folder = FilenameParser.parse(String(parts[parts.count - 2]))
        let normalized = TitleSimilarity.normalize(folder.title)
        guard normalized.count >= 2, !FilmEntry.genericFolders.contains(normalized) else { return nil }
        return folder
    }

    /// Titles to search TMDB with, best first: the file name, the folder name, then the parts of a
    /// name like "Rosetta, Dardenne" or "Luc et Jean-Pierre Dardenne - Rosetta".
    public var lookupTitles: [String] {
        var titles = [parsed.title]
        if let folder = folderParsed?.title { titles.append(folder) }
        for separator in [", ", " - "] where parsed.title.contains(separator) {
            titles += parsed.title.components(separatedBy: separator)
        }
        var seen = Set<String>()
        return titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { TitleSimilarity.normalize($0).count >= 2 && seen.insert(TitleSimilarity.normalize($0)).inserted }
            .prefix(3)
            .map { $0 }
    }

    /// The year from the file name, else from the folder name.
    public var lookupYear: Int? { parsed.year ?? folderParsed?.year }

    /// Key for personal data. Uses the TMDB id, so notes survive renames, moves and rescans.
    public var personalKey: String {
        if let id = tmdb?.id { return "tmdb:\(id)" }
        return "file:\(fileName)"
    }
}

public struct LibraryFile: Codable, Equatable, Sendable {
    public var version: Int
    public var films: [FilmEntry]
    /// Only present in files written by Reel 0.3. Drives now live in Settings.json.
    public var drives: [Drive]?

    public init(films: [FilmEntry] = []) {
        self.version = 3
        self.films = films
        self.drives = nil
    }
}

public enum LibraryMerge {
    /// Applies a fresh scan of one drive to the library.
    /// - Known files keep their match.
    /// - A file moved to another folder (same name and size) keeps its match.
    /// - New files are added as pending.
    /// - Files no longer on the scanned drive are dropped. Other drives are untouched.
    public static func apply(scan: [ScannedFile], driveID: String, to existing: [FilmEntry], now: Date) -> [FilmEntry] {
        let others = existing.filter { $0.driveID != driveID }
        let mine = existing.filter { $0.driveID == driveID }

        var byPath: [String: FilmEntry] = [:]
        for e in mine { byPath[e.relativePath] = e }
        let scannedPaths = Set(scan.map { $0.relativePath })
        var missing = mine.filter { !scannedPaths.contains($0.relativePath) }

        var result: [FilmEntry] = []
        result.reserveCapacity(scan.count)
        for file in scan {
            if var known = byPath[file.relativePath] {
                known.size = file.size
                known.modified = file.modified
                known.extras = file.extras
                result.append(known)
            } else if let i = missing.firstIndex(where: { $0.fileName == file.fileName && $0.size == file.size }) {
                var moved = missing.remove(at: i)
                moved.relocate(to: file.relativePath)
                moved.modified = file.modified
                moved.extras = file.extras
                result.append(moved)
            } else {
                result.append(FilmEntry(
                    driveID: driveID, relativePath: file.relativePath, fileName: file.fileName,
                    size: file.size, modified: file.modified, addedAt: now, extras: file.extras
                ))
            }
        }
        return others + result
    }
}

// MARK: - Personal data

public struct PersonalRecord: Codable, Equatable, Sendable {
    public var watched: Bool
    public var favorite: Bool
    public var watchlist: Bool
    public var rating: Int?
    public var note: String
    public var watchedOn: Date?

    public init(watched: Bool = false, favorite: Bool = false, watchlist: Bool = false,
                rating: Int? = nil, note: String = "", watchedOn: Date? = nil) {
        self.watched = watched
        self.favorite = favorite
        self.watchlist = watchlist
        self.rating = rating
        self.note = note
        self.watchedOn = watchedOn
    }

    public var isEmpty: Bool { self == PersonalRecord() }

    /// Combines two records for the same film without losing anything.
    public func merged(with other: PersonalRecord) -> PersonalRecord {
        var result = self
        result.watched = watched || other.watched
        result.favorite = favorite || other.favorite
        result.watchlist = (watchlist || other.watchlist) && !result.watched
        result.rating = rating ?? other.rating
        result.watchedOn = watchedOn ?? other.watchedOn
        let notes = [note, other.note].filter { !$0.isEmpty }
        result.note = notes.count == 2 && notes[0] == notes[1] ? notes[0] : notes.joined(separator: "\n\n")
        return result
    }
}

public struct PersonalFile: Codable, Equatable, Sendable {
    public var version: Int
    public var records: [String: PersonalRecord]
    /// Matches the user picked or confirmed: file name → TMDB id. They always win over automatic
    /// matching and survive a lost or rebuilt Library.json.
    public var corrections: [String: Int]
    /// Films you don't own yet but want to see.
    public var wishlist: [WishlistFilm]
    /// Wishlist films that turned up in the library (shown with a tag on New Arrivals).
    public var wishlistArrivals: [WishlistArrival]
    /// Files the user regrouped by hand (an extra that is a film, a film that is an extra).
    public var groupingFixes: GroupingFixes

    enum CodingKeys: String, CodingKey {
        case version, records, corrections, wishlist, wishlistArrivals, groupingFixes
    }

    public init(records: [String: PersonalRecord] = [:], corrections: [String: Int] = [:], wishlist: [WishlistFilm] = [],
                wishlistArrivals: [WishlistArrival] = [], groupingFixes: GroupingFixes = GroupingFixes()) {
        self.version = 4
        self.records = records
        self.corrections = corrections
        self.wishlist = wishlist
        self.wishlistArrivals = wishlistArrivals
        self.groupingFixes = groupingFixes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        records = try c.decodeIfPresent([String: PersonalRecord].self, forKey: .records) ?? [:]
        corrections = try c.decodeIfPresent([String: Int].self, forKey: .corrections) ?? [:]
        wishlist = try c.decodeIfPresent([WishlistFilm].self, forKey: .wishlist) ?? []
        wishlistArrivals = try c.decodeIfPresent([WishlistArrival].self, forKey: .wishlistArrivals) ?? []
        groupingFixes = try c.decodeIfPresent(GroupingFixes.self, forKey: .groupingFixes) ?? GroupingFixes()
    }
}
