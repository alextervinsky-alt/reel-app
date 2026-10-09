#if os(macOS)
import AppKit
import ReelCore

extension AppModel {
    // MARK: - Lists and sets

    /// A TMDB client, when a token is set.
    var tmdb: TMDBClient? { hasToken ? TMDBClient(token: token) : nil }

    /// The library copy of a list film, by IMDb or TMDB id.
    func libraryItem(_ film: ListFilm) -> LibraryItem? {
        if let imdb = film.imdbID, let item = itemsByIMDb[imdb] { return item }
        return lists.tmdbID(film).flatMap { itemsByTMDB[$0] }
    }

    func progress(of films: [ListFilm]) -> ListProgress {
        var progress = ListProgress(total: films.count)
        for film in films {
            let item = libraryItem(film)
            let id = item?.main.tmdb?.id ?? lists.tmdbID(film)
            if item != nil { progress.owned += 1 } else if isWishlisted(id) { progress.wishlisted += 1 }
            if isSeen(id) { progress.seen += 1 }
        }
        return progress
    }

    func progress(of set: FilmSet) -> ListProgress {
        let films = set.films(owned: ownedIDs)
        var progress = ListProgress(total: films.count)
        for film in films {
            if itemsByTMDB[film.id] != nil { progress.owned += 1 } else if wishlistIDs.contains(film.id) { progress.wishlisted += 1 }
            if isSeen(film.id) { progress.seen += 1 }
        }
        return progress
    }

    /// Brings the Lists hub's sets up to date (only missing or old ones are fetched).
    func refreshSets() async {
        guard let client = tmdb else { return }
        await lists.refreshSets(setCandidates, using: client)
    }

    // MARK: - Stills

    /// Remembers which stills passed the on-device check, so it runs once per film.
    func setCheckedStills(_ paths: [String], forTMDB id: Int) {
        mutateFilms { list in
            for i in list.indices where list[i].tmdb?.id == id {
                list[i].checkedStills = paths
                list[i].checkedStillsVersion = FilmEntry.currentStillsCheck
            }
        }
    }

    /// "Not a frame from the film": removed from the film's stills for good.
    func hideStill(_ path: String, forTMDB id: Int) {
        guard let current = films.first(where: { $0.tmdb?.id == id })?.checkedStills else { return }
        setCheckedStills(current.filter { $0 != path }, forTMDB: id)
    }

    // MARK: - Explore

    /// Loads an Explore list (kept for six hours).
    func loadDiscover(_ list: DiscoverList, force: Bool = false) async {
        guard hasToken, !discoverLoading.contains(list) else { return }
        if !force, discover[list] != nil, let loaded = discoverLoadedAt[list], loaded > Date().addingTimeInterval(-6 * 3600) { return }
        discoverLoading.insert(list)
        defer { discoverLoading.remove(list) }
        let request = list.request()
        if let films = try? await TMDBClient(token: token).movies(request.path, request.query, pages: request.pages) {
            discover[list] = films
            discoverLoadedAt[list] = Date()
        }
    }

    /// "More Like This" for a film page.
    func loadSimilar(for film: FilmEntry) async {
        guard hasToken, let details = film.tmdb,
              similar[details.id] == nil || (similarLoadedAt[details.id] ?? .distantPast) < Date().addingTimeInterval(-6 * 3600)
        else { return }
        let client = TMDBClient(token: token)
        async let recommendations = client.movies("/movie/\(details.id)/recommendations", pages: 2)
        async let alike = client.movies("/movie/\(details.id)/similar")
        let recs = try? await recommendations
        let sims = try? await alike
        // Nothing stored on a network error, so it's tried again next time.
        guard recs != nil || sims != nil else { return }
        similarLoadedAt[details.id] = Date()
        if let recs {
            let ranks = Dictionary(recs.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
            if ranks != recommendationRanks[details.id] { recommendationRanks[details.id] = ranks }
        }
        similar[details.id] = SimilarFilms.rank(recommendations: recs ?? [], similar: sims ?? [],
                                                genres: Set(details.genreNames), excluding: details.id)
    }

    /// Trailer and IMDb / Rotten Tomatoes / Metacritic for a film you don't own.
    func previewInfo(for id: Int) async -> (details: TMDBMovieDetails?, ratings: ExternalRatings?) {
        if let cached = previewCache[id] { return cached }
        if let running = previewTasks[id] { return await running.value }
        guard hasToken else { return (nil, nil) }
        let client = TMDBClient(token: token)
        let omdb = omdbClient
        let task = Task { () -> (details: TMDBMovieDetails?, ratings: ExternalRatings?) in
            let details = try? await client.previewDetails(id: id)
            var ratings: ExternalRatings?
            if let imdbID = details?.imdbID, let omdb { ratings = try? await omdb.ratings(imdbID: imdbID) }
            return (details, ratings)
        }
        previewTasks[id] = task
        let result = await task.value
        previewTasks[id] = nil
        previewCache[id] = result
        return result
    }

    // MARK: - Playing and Finder (read only: files are never changed)

    /// A connected copy of the film: the main drive's when it's there, else the Backup's.
    func onlineCopy(of film: FilmEntry) -> FilmEntry? {
        copies(of: film).first { fileURL($0) != nil }
    }

    /// The copy whose extras are shown: a connected one, else any copy that has extras.
    func extrasSource(for film: FilmEntry) -> FilmEntry? {
        let withExtras = copies(of: film).filter { !$0.extras.isEmpty }
        return withExtras.first { fileURL($0) != nil } ?? withExtras.first
    }

    func url(of extra: FilmExtra, in copy: FilmEntry) -> URL? {
        mounted[copy.driveID]?.appendingPathComponent(extra.relativePath)
    }

    /// Plays a bonus video or opens a file with its default app.
    func open(_ extra: FilmExtra, in copy: FilmEntry) {
        guard let url = self.url(of: extra, in: copy) else { return }
        NSWorkspace.shared.open(url)
    }

    func showInFinder(_ extra: FilmExtra, in copy: FilmEntry) {
        guard let url = self.url(of: extra, in: copy) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showInFinder(_ film: FilmEntry) {
        guard let url = fileURL(film) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ film: FilmEntry) {
        let path = fileURL(film)?.path
            ?? URL(fileURLWithPath: drive(film.driveID)?.lastKnownPath ?? "/").appendingPathComponent(film.relativePath).path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func showReelFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([folder.root])
    }

    // MARK: - Keys

    /// Checks the token with TMDB before saving it. Returns a problem to show, or nil when connected.
    func connect(token newToken: String) async -> String? {
        let candidate = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return "Paste the token first." }
        do {
            _ = try await TMDBClient(token: candidate).searchMovies(query: "Dredd", year: 2012)
        } catch TMDBError.unauthorized {
            return "TMDB didn't accept this token. Use the long “API Read Access Token”."
        } catch {
            return "Couldn't reach TMDB. Check the internet connection and try again."
        }
        token = candidate
        hasToken = true
        save(.settings)
        askForOMDbKey()
        Task { await lookUpPending() }
        if !settingsWritable {
            return "Connected for now, but Settings.json couldn't be opened, so the token isn't saved. Quit and reopen Reel to try again."
        }
        return nil
    }

    /// Saves the OMDb key pasted in Settings; films without ratings fetch them again.
    func setOMDbKey(_ key: String) {
        omdbKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if notice == Self.omdbNotice { notice = nil }
        save(.settings)
        mutateFilms { list in
            for i in list.indices where list[i].tmdb != nil && list[i].ratings == nil {
                list[i].infoVersion = 0
            }
        }
        Task { await lookUpPending() }
    }

    // MARK: - Image cache

    func imageCacheSize() async -> Int64 {
        await ImageStore.shared.diskSize()
    }

    func clearImageCache() {
        ImageStore.shared.clear()
    }

    /// Cache files still in use: posters, backdrops and cast photos of films in the library.
    func referencedImageKeys() -> Set<String> {
        var keys = Set<String>()
        for film in films {
            if let d = film.tmdb {
                if let p = d.posterPath {
                    keys.insert(ImageStore.key(p, .poster))
                    keys.insert(ImageStore.key(p, .thumbnail))
                }
                if let b = d.backdropPath { keys.insert(ImageStore.key(b, .backdrop)) }
                if let l = d.logoPath { keys.insert(ImageStore.key(l, .logo)) }
                for person in d.topCast {
                    if let p = person.profilePath { keys.insert(ImageStore.key(p, .profile)) }
                }
            }
            for candidate in film.candidates {
                if let p = candidate.movie.posterPath { keys.insert(ImageStore.key(p, .thumbnail)) }
            }
        }
        return keys
    }
}
#endif
