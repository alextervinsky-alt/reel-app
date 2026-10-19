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

/// What one scan of a drive found, and whether it saw everything there.
public struct DriveScan: Equatable, Sendable {
    public var files: [ScannedFile]
    /// Folders and files that couldn't be read (paths relative to the drive's folder).
    public var unreadable: [String]
    /// Stopped before the end (Reel quitting, the drive removed from Reel during the scan).
    public var cancelled: Bool

    public init(files: [ScannedFile], unreadable: [String] = [], cancelled: Bool = false) {
        self.files = files
        self.unreadable = unreadable
        self.cancelled = cancelled
    }

    /// Everything on the drive was read: only then can a film that wasn't seen count as gone.
    public var isComplete: Bool { unreadable.isEmpty && !cancelled }
}

public enum DriveScanner {
    /// System folders of Mac and Windows drives.
    public static let ignoredFolders: Set<String> = [
        "$recycle.bin", "recycler", "system volume information", "lost+found", "backups.backupdb",
    ]

    /// Smaller video files are trailers, samples or leftovers, not films.
    public static let defaultMinimumSize: Int64 = 30_000_000

    /// One thing the folder listing met: a file, or a folder or file it couldn't read.
    enum Entry {
        case file(FilmGrouping.File)
        /// Path relative to the drive's folder ("" for the folder itself).
        case unreadable(String)
    }

    /// Lists the films under `root`, each with its extras (see `FilmGrouping`), with the user's
    /// grouping fixes applied, and says what it couldn't read. Reads names, sizes and dates from
    /// the folder listing only: no file is ever opened, read or changed, and nothing is written to
    /// the drive.
    /// - Parameters:
    ///   - progress: told how many files have been read so far (every 250 files).
    ///   - isCancelled: asked as the listing goes; true stops it (the result is then cancelled).
    public static func scan(root: URL, fixes: GroupingFixes = GroupingFixes(),
                            minimumSize: Int64 = defaultMinimumSize, progress: ((Int) -> Void)? = nil,
                            isCancelled: () -> Bool = { false }) -> DriveScan {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let rootPrefix = folderPrefix(root.standardizedFileURL.path)
        let resolvedPrefix = folderPrefix(root.resolvingSymlinksInPath().path)
        // The enumerator builds paths from `root`, so a plain prefix check works; resolving
        // links (a disk access) is only the fallback.
        func relative(_ url: URL) -> String {
            let path = url.standardizedFileURL.path
            if path.hasPrefix(rootPrefix) { return String(path.dropFirst(rootPrefix.count)) }
            let resolved = url.resolvingSymlinksInPath().path
            if resolved.hasPrefix(resolvedPrefix) { return String(resolved.dropFirst(resolvedPrefix.count)) }
            return path == root.standardizedFileURL.path ? "" : url.lastPathComponent
        }
        // Folders the listing couldn't open are reported here as it goes, instead of being skipped
        // without a word (their films would then look deleted).
        let failures = Failures()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, _ in
                failures.add(relative(url))
                return true
            }
        ) else {
            return DriveScan(files: [], unreadable: [""], cancelled: false)
        }

        let keySet = Set(keys)
        let entries = AnySequence<Entry> {
            AnyIterator {
                while true {
                    if let path = failures.next() { return .unreadable(path) }
                    guard let url = enumerator.nextObject() as? URL else { return failures.next().map { .unreadable($0) } }
                    guard let values = try? url.resourceValues(forKeys: keySet) else { return .unreadable(relative(url)) }
                    if values.isDirectory == true {
                        if ignoredFolders.contains(url.lastPathComponent.lowercased()) { enumerator.skipDescendants() }
                        continue
                    }
                    guard values.isRegularFile == true else { continue }
                    return .file(FilmGrouping.File(relativePath: relative(url), size: Int64(values.fileSize ?? 0),
                                                   modified: values.contentModificationDate))
                }
            }
        }
        return collect(entries, fixes: fixes, minimumSize: minimumSize, progress: progress, isCancelled: isCancelled)
    }

    /// Turns what the listing met into the scan's result: the films with their extras, what
    /// couldn't be read, and whether it was stopped.
    static func collect(_ entries: some Sequence<Entry>, fixes: GroupingFixes = GroupingFixes(),
                        minimumSize: Int64 = defaultMinimumSize, progress: ((Int) -> Void)? = nil,
                        isCancelled: () -> Bool = { false }) -> DriveScan {
        var files: [FilmGrouping.File] = []
        var unreadable: [String] = []
        var cancelled = false
        for entry in entries {
            if isCancelled() {
                cancelled = true
                break
            }
            switch entry {
            case .file(let file):
                files.append(file)
                if files.count % 250 == 0 { progress?(files.count) }
            case .unreadable(let path):
                unreadable.append(path)
            }
        }
        return DriveScan(files: fixes.apply(to: FilmGrouping.group(files, minimumSize: minimumSize)),
                         unreadable: unreadable, cancelled: cancelled)
    }

    /// Paths the listing couldn't open, handed over in order (the enumerator reports them from
    /// its own calls, so they're collected here first).
    private final class Failures {
        private var paths: [String] = []
        private var read = 0
        func add(_ path: String) { paths.append(path) }
        func next() -> String? {
            guard read < paths.count else { return nil }
            defer { read += 1 }
            return paths[read]
        }
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
    /// The gear and techniques read about the film, for searching by craft (see `CraftIndex`).
    public var craft: CraftIndex?
    /// Read from the file name once, not stored on disk (so parser improvements apply automatically).
    public let parsed: ParsedFilename

    enum CodingKeys: String, CodingKey {
        case driveID, relativePath, fileName, size, modified, addedAt, matchState, matchScore, tmdb, candidates, lastError
        case ratings, reception, infoVersion, lastLookup, ratingsDue, ratingsTriedAt, funFacts, checkedStills, extras
        case infoUpdatedAt, checkedStillsVersion, craft
    }

    /// Bump when Reel starts storing more film info, so existing entries get refreshed.
    /// 5: trailers are kept even when a film has many other videos.
    /// 6: trailers without a language and in the film's own language, others' uploads as a fallback.
    /// 7: trailer sizes, so HD uploads are played first.
    /// (Reel 1.8.3 saved 8 for a while: the next bump is to 9.)
    /// 9: likes and dislikes read again (critics by what they did, figures and prizes left out).
    public static let currentInfoVersion = 9

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
        self.craft = nil
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
        craft = try? c.decodeIfPresent(CraftIndex.self, forKey: .craft)
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
        if tmdb?.id != details.id {
            funFacts = nil
            craft = nil
        }
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

    /// Key for personal data. Uses the TMDB id, so notes survive renames, moves and rescans; a
    /// file not identified yet is known by its name and size (see `FileIdentity`).
    public var personalKey: String {
        if let id = tmdb?.id { return "tmdb:\(id)" }
        return FileIdentity.unidentifiedPrefix + fileKey
    }

    /// The file's identity: its name and size. The same name and size is the same file (a copy on
    /// the Backup, or moved); the same name with another size is a different file.
    public var fileKey: String { FileIdentity.key(name: fileName, size: size) }
}

/// Which files are the same file, and the fixes and notes Reel keeps for one. A file is its name
/// plus its size: generic names ("title_t00.mkv", "movie.mkv") then never pass one film's match,
/// fix or notes to another. Fixes and notes saved before Reel 1.8.8 are keyed by the name alone;
/// they're used, and moved to the new key, only when every file with that name has one size.
public enum FileIdentity {
    /// Personal notes of a file that isn't identified yet: "file:" and its file key.
    public static let unidentifiedPrefix = "file:"

    public static func key(name: String, size: Int64) -> String { "\(name)|\(size)" }

    /// A key that already has the size ("name|1234"); anything else is from before 1.8.8.
    public static func hasSize(_ key: String) -> Bool {
        guard let bar = key.lastIndex(of: "|") else { return false }
        let digits = key[key.index(after: bar)...]
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    /// The fix you made for a file.
    public enum Fix: Equatable, Sendable {
        case none
        /// The film you chose for this file (or one saved under its name alone, when that can only
        /// mean this file).
        case film(Int)
        /// Saved under its name alone, which now names files of different sizes: not applied to
        /// any of them (each is matched and marked to check instead).
        case ambiguous
    }

    public static func fix(for file: FilmEntry, corrections: [String: Int], library films: [FilmEntry]) -> Fix {
        if let id = corrections[file.fileKey] { return .film(id) }
        guard let id = corrections[file.fileName] else { return .none }
        return sizes(of: file.fileName, in: films).count <= 1 ? .film(id) : .ambiguous
    }

    /// What `upgrade` changed and left alone.
    public struct Upgrade: Equatable, Sendable {
        public var corrections: [String: Int]
        /// Old note keys and their new ones, to move.
        public var notes: [(from: String, to: String)]
        /// Names whose fixes or notes were left as they are: files of different sizes share them.
        public var ambiguous: [String]

        public static func == (a: Upgrade, b: Upgrade) -> Bool {
            a.corrections == b.corrections && a.ambiguous == b.ambiguous
                && a.notes.map { [$0.from, $0.to] } == b.notes.map { [$0.from, $0.to] }
        }
    }

    /// Moves fixes and notes saved under a name alone to "name|size", when the library has files
    /// of that name in exactly one size. Names with no file now are left alone (the file may come
    /// back); names with files of several sizes too (it can't be known which one was meant).
    /// Running it again changes nothing.
    public static func upgrade(corrections: [String: Int], noteKeys: [String], library films: [FilmEntry]) -> Upgrade {
        var result = corrections
        var ambiguous = Set<String>()
        for (name, id) in corrections where !hasSize(name) {
            let found = sizes(of: name, in: films)
            if found.count > 1 { ambiguous.insert(name) }
            guard found.count == 1, let size = found.first else { continue }
            let newKey = key(name: name, size: size)
            // A fix already saved with the size is newer and wins.
            if result[newKey] == nil { result[newKey] = id }
            result[name] = nil
        }
        var notes: [(from: String, to: String)] = []
        for old in noteKeys where old.hasPrefix(unidentifiedPrefix) {
            let name = String(old.dropFirst(unidentifiedPrefix.count))
            guard !hasSize(name) else { continue }
            let found = sizes(of: name, in: films)
            if found.count > 1 { ambiguous.insert(name) }
            guard found.count == 1, let size = found.first else { continue }
            notes.append((old, unidentifiedPrefix + key(name: name, size: size)))
        }
        return Upgrade(corrections: result, notes: notes.sorted { $0.from < $1.from }, ambiguous: ambiguous.sorted())
    }

    private static func sizes(of name: String, in films: [FilmEntry]) -> Set<Int64> {
        Set(films.filter { $0.fileName == name }.map(\.size))
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
    /// - Files no longer on the scanned drive are dropped, unless `keepingUnseen` (a scan that
    ///   didn't read everything): then they stay exactly as they were. Other drives are untouched.
    public static func apply(scan: [ScannedFile], driveID: String, to existing: [FilmEntry], now: Date,
                             keepingUnseen: Bool = false) -> [FilmEntry] {
        let merged = merge(scan: scan, driveID: driveID, to: existing, now: now)
        return keepingUnseen ? merged.films + merged.unseen : merged.films
    }

    /// The films of the scanned drive that a complete scan would drop (not seen, and not found
    /// moved to another folder).
    public static func unseen(scan: [ScannedFile], driveID: String, in existing: [FilmEntry]) -> [FilmEntry] {
        merge(scan: scan, driveID: driveID, to: existing, now: Date()).unseen
    }

    private static func merge(scan: [ScannedFile], driveID: String, to existing: [FilmEntry], now: Date)
        -> (films: [FilmEntry], unseen: [FilmEntry]) {
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
        return (others + result, missing)
    }
}

/// What a finished scan may change in the library. Only a scan that read the whole drive, while
/// the drive stayed connected, can remove films; one that would remove a large share of a drive
/// asks first.
public enum ScanVerdict: Equatable, Sendable {
    /// Everything: new, moved, updated and removed films.
    case apply
    /// New, moved and updated films; nothing removed (some of the drive couldn't be read).
    case keepUnseen(unreadable: [String])
    /// A complete read that would remove many films: they're kept until you confirm.
    case confirmRemovals(count: Int)
    /// Nothing is used.
    case discard(Reason)

    public enum Reason: Equatable, Sendable {
        /// The drive was disconnected (or remounted) during the scan.
        case driveGone
        /// The scan was stopped before the end.
        case cancelled
        /// No films at all where there were some (a permission prompt, a drive still waking).
        case nothingSeen
    }

    /// Removing at least this many films, and at least this share of the drive's films, asks first.
    public static let askAtCount = 10
    public static let askAtShare = 0.25

    public static func of(_ scan: DriveScan, driveID: String, known films: [FilmEntry], driveStillThere: Bool) -> ScanVerdict {
        guard driveStillThere else { return .discard(.driveGone) }
        guard !scan.cancelled else { return .discard(.cancelled) }
        let known = films.filter { $0.driveID == driveID }
        if scan.files.isEmpty && !known.isEmpty { return .discard(.nothingSeen) }
        guard scan.unreadable.isEmpty else { return .keepUnseen(unreadable: scan.unreadable) }
        let removed = LibraryMerge.unseen(scan: scan.files, driveID: driveID, in: films).count
        if removed >= askAtCount && Double(removed) >= Double(known.count) * askAtShare {
            return .confirmRemovals(count: removed)
        }
        return .apply
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
