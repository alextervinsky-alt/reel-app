#if os(macOS)
import Foundation
import Observation
import ReelCore

/// The Lists hub's data: IMDb rankings, award lists, posters for list films, and the sets you're
/// collecting. Kept in ~/Documents/Reel/List Data.nosync and refreshed from the web on its own
/// when due: award lists weekly, sets every two weeks, IMDb ratings and posters monthly.
@MainActor
@Observable
final class ListsStore {
    enum IMDbState: Equatable {
        case notDownloaded
        case downloading(Double)
        case preparing
        case ready(Date)
        case failed(String)
    }

    private(set) var imdbState: IMDbState = .notDownloaded
    private(set) var awards: [AwardList: [ListFilm]] = [:]
    private(set) var awardsLoading: Set<AwardList> = []
    private(set) var awardsFailed: Set<AwardList> = []
    /// List film key (IMDb id or "tmdb:id") → its TMDB poster and id.
    private(set) var art: [String: ResolvedFilm] = [:]
    private(set) var sets: [String: FilmSet] = [:]
    private(set) var setsLoading = false
    private(set) var imdbFilmsLoading = false
    /// Fresh IMDb files are being fetched while the current ones stay in use.
    private(set) var imdbUpdating = false
    /// A few facts about films outside the library (TMDB id → title, year, running time, genres,
    /// directors, pictures): for films you saw elsewhere and for Start Here. Downloaded once.
    private(set) var briefs: [Int: FilmBrief] = [:]

    @ObservationIgnored private var imdbFilms: [IMDbFilm] = []
    @ObservationIgnored private var imdbLists: [FilmListKind: [ListFilm]] = [:]
    @ObservationIgnored private var awardsFetchedAt: [String: Date] = [:]
    @ObservationIgnored private var resolving: Set<String> = []
    @ObservationIgnored private var unresolvable: Set<String> = []
    @ObservationIgnored private var preparing: Task<Void, Never>?
    @ObservationIgnored private var saveTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let writer = FileWriter()
    /// Rows waiting for their posters (see `want`).
    @ObservationIgnored private var queued: [ListFilm] = []
    @ObservationIgnored private var queueDrain: Task<Void, Never>?
    @ObservationIgnored private var fetchingBriefs: Set<Int> = []

    private let folder: URL
    private var imdbFile: URL { folder.appendingPathComponent("IMDb Ratings.json") }
    private var awardsFile: URL { folder.appendingPathComponent("Award Lists.json") }
    private var artFile: URL { folder.appendingPathComponent("Film Art.json") }
    private var setsFile: URL { folder.appendingPathComponent("Sets.json") }
    private var briefsFile: URL { folder.appendingPathComponent("Film Briefs.json") }

    static let awardsMaxAge: TimeInterval = 7 * 86_400
    static let setsMaxAge: TimeInterval = 14 * 86_400
    static let imdbMaxAge: TimeInterval = 30 * 86_400
    static let artMaxAge: TimeInterval = 30 * 86_400

    init(folder: URL) {
        self.folder = folder
    }

    // MARK: Loading saved data

    /// Reads the saved lists once, in the background, the first time the hub opens.
    func prepare() async {
        if preparing == nil { preparing = Task { await readSavedFiles() } }
        await preparing?.value
    }

    private func readSavedFiles() async {
        let files = (awards: awardsFile, art: artFile, sets: setsFile, imdb: imdbFile, briefs: briefsFile)
        let loaded = await Task.detached(priority: .userInitiated) {
            ListsStore.removeLeftoverDownloads()
            return (JSONStore.load(AwardListsFile.self, from: files.awards),
             JSONStore.load([String: ResolvedFilm].self, from: files.art),
             JSONStore.load(FilmSetsFile.self, from: files.sets),
             (try? FileManager.default.attributesOfItem(atPath: files.imdb.path))?[.modificationDate] as? Date,
             JSONStore.load([Int: FilmBrief].self, from: files.briefs))
        }.value
        // Lists saved before they had nominees are fetched again.
        if let saved = loaded.0, saved.version == AwardListsFile.currentVersion {
            for (key, films) in saved.lists {
                if let list = AwardList(rawValue: key) { awards[list] = films }
            }
            awardsFetchedAt = saved.fetchedAt
        }
        if let saved = loaded.1 { art = saved.merging(art) { _, new in new } }
        if let saved = loaded.2 { sets = Dictionary(saved.sets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
        if let built = loaded.3 { imdbState = .ready(built) }
        if let saved = loaded.4 { briefs = saved.merging(briefs) { _, new in new } }
    }

    // MARK: Films outside the library

    /// Fetches the briefs not fetched yet, eight at a time. One that fails (offline) is tried
    /// again next time.
    func fetchBriefs(_ ids: [Int], using client: TMDBClient) async {
        await prepare()
        let wanted = Array(Set(ids).subtracting(briefs.keys).subtracting(fetchingBriefs))
        guard !wanted.isEmpty else { return }
        fetchingBriefs.formUnion(wanted)
        defer { fetchingBriefs.subtract(wanted) }
        var start = 0
        while start < wanted.count, !Task.isCancelled {
            let batch = wanted[start..<min(start + 8, wanted.count)]
            start += 8
            let found = await withTaskGroup(of: (Int, FilmBrief?).self, returning: [(Int, FilmBrief)].self) { group in
                for id in batch {
                    group.addTask { (id, (try? await client.briefDetails(id: id)).map(FilmBrief.init)) }
                }
                var all: [(Int, FilmBrief)] = []
                for await result in group { if let film = result.1 { all.append((result.0, film)) } }
                return all
            }
            guard !found.isEmpty else { continue }
            var updated = briefs
            for (id, film) in found { updated[id] = film }
            briefs = updated
            scheduleSave("briefs")
        }
    }

    /// When a film came out, from its brief, fetching the brief again when it was kept without
    /// one (before Reel 1.7) or never fetched.
    func releaseDate(of id: Int, using client: TMDBClient?) async -> String? {
        await prepare()
        // "" once looked up and TMDB has none (not asked again).
        if let released = briefs[id]?.released { return released.isEmpty ? nil : released }
        guard let client, let details = try? await client.briefDetails(id: id) else { return nil }
        var brief = FilmBrief(details)
        brief.released = details.releaseDate ?? ""
        briefs[id] = brief
        scheduleSave("briefs")
        return brief.released?.isEmpty == false ? brief.released : nil
    }

    // MARK: Lists

    func films(for kind: FilmListKind) -> [ListFilm] {
        switch kind {
        case .award(let award):
            return awards[award] ?? []
        case .sightAndSound:
            return SightAndSound.films
        case .imdbYear, .imdbAllTime:
            guard case .ready = imdbState, !imdbFilms.isEmpty else { return [] }
            if let cached = imdbLists[kind] { return cached }
            let ranked: [IMDbFilm]
            if case .imdbYear(let year) = kind {
                ranked = IMDbDataset.top(imdbFilms, year: year)
            } else {
                ranked = IMDbDataset.topAllTime(imdbFilms)
            }
            let list = ranked.map(ListFilm.init)
            imdbLists[kind] = list
            return list
        }
    }

    /// IMDb's ratings are downloaded and ready for rankings.
    var imdbIsReady: Bool {
        if case .ready = imdbState { return true }
        return false
    }

    func isLoading(_ kind: FilmListKind) -> Bool {
        switch kind {
        case .award(let award): awardsLoading.contains(award)
        case .sightAndSound: false
        default: imdbState == .preparing || imdbFilmsLoading
        }
    }

    /// Makes a list ready to show: award lists are fetched when missing or a week old; IMDb
    /// rankings need the downloaded ratings (fetched on their own the first time), read from disk once.
    func load(_ kind: FilmListKind) async {
        await prepare()
        switch kind {
        case .award(let award):
            await loadAward(award)
        case .sightAndSound:
            break
        case .imdbYear, .imdbAllTime:
            await loadIMDbFilms()
            startIMDbIfNeeded()
        }
    }

    /// The first time an IMDb ranking is wanted (or the saved copy is gone), its data is fetched
    /// without asking.
    func startIMDbIfNeeded() {
        if case .notDownloaded = imdbState { Task { await downloadIMDb() } }
    }

    /// Everything that's due, fetched in the background (at launch and every few hours).
    func refreshStale(sets wanted: [SetCandidate], using client: TMDBClient?) async {
        await prepare()
        await loadAllAwards()
        switch imdbState {
        case .ready(let built) where built < Date().addingTimeInterval(-Self.imdbMaxAge):
            await downloadIMDb()
        case .failed:
            // A first download that failed is tried again on its own.
            await downloadIMDb()
        default:
            break
        }
        if let client { await refreshSets(wanted, using: client) }
    }

    private func loadAward(_ award: AwardList) async {
        let fresh = (awardsFetchedAt[award.rawValue] ?? .distantPast) > Date().addingTimeInterval(-Self.awardsMaxAge)
        guard awards[award] == nil || !fresh, !awardsLoading.contains(award) else { return }
        awardsLoading.insert(award)
        defer { awardsLoading.remove(award) }
        do {
            let films = try await WikidataLists().films(award)
            guard !films.isEmpty else { throw URLError(.zeroByteResource) }
            awards[award] = films
            awardsFailed.remove(award)
            awardsFetchedAt[award.rawValue] = Date()
            scheduleSave("awards")
        } catch {
            // Keep the older copy if there is one.
            if awards[award] == nil { awardsFailed.insert(award) }
        }
    }

    func loadAllAwards() async {
        await prepare()
        await withTaskGroup(of: Void.self) { group in
            for award in AwardList.allCases {
                group.addTask { await self.loadAward(award) }
            }
        }
    }

    private func loadIMDbFilms() async {
        guard case .ready = imdbState, imdbFilms.isEmpty, !imdbFilmsLoading else { return }
        imdbFilmsLoading = true
        defer { imdbFilmsLoading = false }
        let file = imdbFile
        let saved = await Task.detached(priority: .userInitiated) { JSONStore.load(IMDbRatingsFile.self, from: file) }.value
        if let saved, !saved.films.isEmpty {
            imdbFilms = saved.films
            imdbLists = [:]
            imdbState = .ready(saved.builtAt)
        } else {
            imdbState = .notDownloaded
        }
    }

    // MARK: IMDb download

    var imdbIsBusy: Bool {
        switch imdbState {
        case .downloading, .preparing: true
        default: false
        }
    }

    /// Downloads IMDb's two ratings files (about 200 MB, to the system's temporary folder), keeps
    /// a compact copy of the feature films (a few MB) and deletes the downloads. When a copy
    /// already exists it stays in use until the new one is ready.
    func downloadIMDb() async {
        guard !imdbIsBusy, !imdbUpdating else { return }
        var quiet = false
        if case .ready = imdbState { quiet = true }
        if quiet {
            imdbUpdating = true
        } else {
            imdbState = .downloading(0)
        }
        defer { imdbUpdating = false }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(Self.downloadFolderPrefix + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let ratings = temp.appendingPathComponent("ratings.tsv.gz")
            let basics = temp.appendingPathComponent("basics.tsv.gz")
            try await Self.download(IMDbDataset.ratingsURL, to: ratings) { [weak self] p in
                Task { @MainActor in self?.report(p * 0.04) }
            }
            try await Self.download(IMDbDataset.basicsURL, to: basics) { [weak self] p in
                Task { @MainActor in self?.report(0.04 + p * 0.96) }
            }
            if !quiet { imdbState = .preparing }
            let target = imdbFile
            let films = try await Task.detached(priority: .utility) { () throws -> [IMDbFilm] in
                let films = try IMDbDataset.build(ratingsFile: ratings, basicsFile: basics)
                guard films.count > 1_000 else { throw CocoaError(.fileReadCorruptFile) }
                try JSONStore.save(IMDbRatingsFile(builtAt: Date(), films: films), to: target)
                return films
            }.value
            imdbFilms = films
            imdbLists = [:]
            imdbState = .ready(Date())
        } catch {
            // A failed update keeps the current copy; either way it's tried again later.
            if !quiet { imdbState = .failed("Couldn't get IMDb's files. Reel will try again later, or press Try Again.") }
        }
    }

    private func report(_ progress: Double) {
        guard case .downloading = imdbState else { return }
        imdbState = .downloading(progress)
    }

    nonisolated static let downloadFolderPrefix = "Reel IMDb "

    /// No cookies, no cache, nothing left behind in ~/Library; generous time for 200 MB.
    nonisolated private static let downloadSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3_600
        return URLSession(configuration: config)
    }()

    nonisolated private static func download(_ url: URL, to destination: URL,
                                             progress: @escaping @Sendable (Double) -> Void) async throws {
        let observer = DownloadObserver(report: progress)
        let (file, response) = try await downloadSession.download(from: url, delegate: observer)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try FileManager.default.moveItem(at: file, to: destination)
    }

    /// Downloads left over from a quit in the middle of one.
    nonisolated static func removeLeftoverDownloads() {
        let temp = FileManager.default.temporaryDirectory
        let items = (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []
        for item in items where item.hasPrefix(downloadFolderPrefix) {
            try? FileManager.default.removeItem(at: temp.appendingPathComponent(item))
        }
    }

    // MARK: Posters and TMDB ids for list films

    func resolved(_ film: ListFilm) -> ResolvedFilm? {
        art[film.id]
    }

    func tmdbID(_ film: ListFilm) -> Int? {
        film.tmdbID ?? resolved(film)?.tmdbID
    }

    /// A row came into view: its poster is looked up with the next batch.
    func want(_ film: ListFilm, using client: TMDBClient) {
        guard needsLookup(film) != nil else { return }
        queued.append(film)
        guard queueDrain == nil else { return }
        queueDrain = Task { [weak self] in
            // Collect the rows that appear together, then look them up in one go.
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else { return }
            while !self.queued.isEmpty {
                let batch = self.queued
                self.queued = []
                await self.resolve(batch, using: client)
            }
            self.queueDrain = nil
        }
    }

    private func needsLookup(_ film: ListFilm) -> String? {
        let key = film.id
        // Old enough to refresh, or saved before genres were kept.
        let saved = art[key]
        guard (saved?.fetchedAt ?? .distantPast) < Date().addingTimeInterval(-Self.artMaxAge) || saved?.genres == nil,
              !resolving.contains(key), !unresolvable.contains(key) else { return nil }
        return key
    }

    /// Finds the TMDB poster (and id) of each film not looked up yet or looked up over a month
    /// ago, eight at a time. Stops when the page closes; what was found is kept. A film TMDB
    /// doesn't know is skipped for the rest of the session; one that failed (offline) is tried again.
    func resolve(_ films: [ListFilm], using client: TMDBClient) async {
        await prepare()
        var keys = Set<String>()
        let wanted = films.compactMap { film -> (String, ListFilm)? in
            guard let key = needsLookup(film), keys.insert(key).inserted else { return nil }
            return (key, film)
        }
        guard !wanted.isEmpty else { return }
        resolving.formUnion(keys)
        defer { resolving.subtract(keys) }

        var start = 0
        while start < wanted.count, !Task.isCancelled {
            let batch = wanted[start..<min(start + 8, wanted.count)]
            start += 8
            let found = await withTaskGroup(of: (String, Lookup).self, returning: [(String, Lookup)].self) { group in
                for (key, film) in batch {
                    group.addTask { (key, await Self.lookUp(film, client: client)) }
                }
                var all: [(String, Lookup)] = []
                for await result in group { all.append(result) }
                return all
            }
            var updated = art
            for (key, result) in found {
                switch result {
                case .found(let value): updated[key] = value
                case .unknown: unresolvable.insert(key)
                case .failed: break
                }
            }
            if updated != art { art = updated }
            scheduleSave("art")
        }
    }

    private enum Lookup: Sendable {
        case found(ResolvedFilm), unknown, failed
    }

    nonisolated private static func lookUp(_ film: ListFilm, client: TMDBClient) async -> Lookup {
        do {
            if let id = film.tmdbID {
                return .found(ResolvedFilm(try await client.movieSummary(id: id)))
            }
            if let imdb = film.imdbID {
                return try await client.find(imdbID: imdb).map { Lookup.found(ResolvedFilm($0)) } ?? .unknown
            }
            // Lists that only know the title and year (Sight and Sound): the best TMDB match.
            let results = try await client.searchMovies(query: film.title, year: nil)
            let best = FilmMatcher.rank(results, title: film.title, year: film.year).best
            guard let best, best.score >= 0.6 else { return .unknown }
            return .found(ResolvedFilm(best.movie))
        } catch TMDBError.badStatus(404) {
            return .unknown
        } catch {
            return .failed
        }
    }

    // MARK: Sets

    func set(_ id: String) -> FilmSet? { sets[id] }

    /// Fetches the filmographies and franchises worth showing (missing or two weeks old), four at a time.
    func refreshSets(_ wanted: [SetCandidate], using client: TMDBClient) async {
        await prepare()
        let cutoff = Date().addingTimeInterval(-Self.setsMaxAge)
        let stale = wanted.filter { (sets[FilmSet.id($0.kind, $0.id)]?.fetchedAt ?? .distantPast) < cutoff }
        guard !stale.isEmpty, !setsLoading else { return }
        setsLoading = true
        defer { setsLoading = false }
        var start = 0
        while start < stale.count, !Task.isCancelled {
            let batch = stale[start..<min(start + 4, stale.count)]
            start += 4
            let fetched = await withTaskGroup(of: FilmSet?.self, returning: [FilmSet].self) { group in
                for entry in batch {
                    group.addTask { await Self.fetchSet(entry.kind, id: entry.id, client: client) }
                }
                var all: [FilmSet] = []
                for await set in group { if let set { all.append(set) } }
                return all
            }
            var updated = sets
            for set in fetched { updated[set.id] = set }
            sets = updated
            scheduleSave("sets")
        }
    }

    /// A franchise page opened from a film: fetched when missing or two weeks old, then kept
    /// like the other sets. False when it couldn't be loaded.
    func loadFranchise(_ id: Int, using client: TMDBClient) async -> Bool {
        await prepare()
        let key = FilmSet.id(.franchise, id)
        guard (sets[key]?.fetchedAt ?? .distantPast) < Date().addingTimeInterval(-Self.setsMaxAge) else { return true }
        guard let set = await Self.fetchSet(.franchise, id: id, client: client) else { return sets[key] != nil }
        sets[key] = set
        scheduleSave("sets")
        return true
    }

    nonisolated private static func fetchSet(_ kind: FilmSet.Kind, id: Int, client: TMDBClient) async -> FilmSet? {
        switch kind {
        case .franchise:
            return (try? await client.collection(id: id)).map { FilmSets.collection($0) }
        case .director, .cinematographer:
            return (try? await client.person(id: id)).map { FilmSets.person($0, kind: kind) }
        }
    }

    // MARK: Saving

    private func scheduleSave(_ name: String) {
        saveTasks[name]?.cancel()
        saveTasks[name] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.saveTasks[name] = nil
            self.save(name)
        }
    }

    /// Takes a copy of the data here and turns it into JSON on the writer's background queue.
    private func save(_ name: String) {
        let url: URL
        let encode: @Sendable () -> Data?
        switch name {
        case "awards":
            url = awardsFile
            let file = AwardListsFile(lists: Dictionary(uniqueKeysWithValues: awards.map { ($0.key.rawValue, $0.value) }),
                                      fetchedAt: awardsFetchedAt)
            encode = { try? JSONStore.encode(file) }
        case "art":
            url = artFile
            let art = self.art
            encode = { try? JSONStore.encode(art) }
        case "briefs":
            url = briefsFile
            let briefs = self.briefs
            encode = { try? JSONStore.encode(briefs) }
        default:
            url = setsFile
            let all = Array(sets.values)
            encode = { try? JSONStore.encode(FilmSetsFile(sets: all.sorted { $0.id < $1.id })) }
        }
        writer.enqueue {
            guard let data = encode() else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Writes anything still waiting (when the app quits).
    func flush() {
        for (name, task) in saveTasks {
            task.cancel()
            save(name)
        }
        saveTasks = [:]
        writer.flush()
    }
}

/// A director, cinematographer or franchise worth showing, with how many of its films you own.
typealias SetCandidate = (kind: FilmSet.Kind, id: Int, name: String, owned: Int)

/// Passes a download's progress on, at most once per percent.
private final class DownloadObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?
    private var lastReported = -1.0
    private let lock = NSLock()

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            self?.forward(progress.fractionCompleted)
        }
    }

    private func forward(_ fraction: Double) {
        lock.lock()
        let due = fraction - lastReported >= 0.01 || fraction >= 1
        if due { lastReported = fraction }
        lock.unlock()
        if due { report(fraction) }
    }
}
#endif
