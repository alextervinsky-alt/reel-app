#if os(macOS)
import Foundation
import ReelCore

extension AppModel {
    /// Ratings come from OMDb with the key pasted in Settings; without one they're skipped.
    var omdbClient: OMDbClient? {
        omdbKey.isEmpty ? nil : OMDbClient(key: omdbKey)
    }

    static let offlineMessage = "Reel is offline. Film info will be fetched next time Reel opens or when you press ⌘R."
    static let tokenMessage = "TMDB didn't accept the token. You can replace it in Settings (⌘,)."

    /// Looks up every pending film, six at a time (each file name once, even when it is on two
    /// drives), then refreshes films whose stored info is from an older version of Reel.
    /// Called again while running, it finishes the current run and then goes round once more.
    func lookUpPending() async {
        guard hasToken else { return }
        guard !lookupRunning else {
            rerunRequested = true
            return
        }
        lookupRunning = true
        let started = ContinuousClock.now
        defer {
            timings["Finding and updating film info"] = ContinuousClock.now - started
            lookupRunning = false
            endWork()
            if candidatesDirty { scheduleRebuild() }
        }

        let client = TMDBClient(token: token)
        var omdb = omdbClient
        let ratingsWanted = omdb != nil
        var stopMessage: String?
        var work = 0
        let runStart = Date()

        repeat {
            rerunRequested = false
            var done = 0

            // 1. New and pending files.
            while stopMessage == nil {
                reuseTwins()
                var seen = Set<String>()
                let unique = films.filter { $0.matchState == .pending && seen.insert($0.fileName).inserted }
                guard !unique.isEmpty else { break }

                let lookedUp = beginWork("Finding film info", done: done, total: done + unique.count)
                let jobs = unique.prefix(6).map {
                    LookupJob(id: $0.id, fileName: $0.fileName, titles: $0.lookupTitles, year: $0.lookupYear,
                              correctedID: corrections[$0.fileName])
                }
                let ratingsClient = omdb
                let outcomes = await withTaskGroup(of: (LookupJob, LookupOutcome).self, returning: [(LookupJob, LookupOutcome)].self) { group in
                    for job in jobs {
                        group.addTask {
                            let outcome = await AppModel.lookUp(job, client: client, omdb: ratingsClient, ratingsWanted: ratingsWanted)
                            lookedUp()
                            return (job, outcome)
                        }
                    }
                    var all: [(LookupJob, LookupOutcome)] = []
                    for await outcome in group { all.append(outcome) }
                    return all
                }

                var newKeys: [(String, String)] = []
                let now = Date()
                mutateFilms { list in
                    for (job, outcome) in outcomes {
                        // Skip films the user identified by hand while the lookup was running.
                        guard let i = list.firstIndex(where: { $0.id == job.id }), list[i].matchState == .pending else { continue }
                        switch outcome {
                        case .matched(let result, let info):
                            if let info {
                                info.store(in: &list[i])
                                if info.ratingsRefused { omdb = nil }
                            }
                            list[i].matchScore = result.best?.score
                            list[i].lastError = nil
                            list[i].lastLookup = now
                            switch result.confidence {
                            case .auto: list[i].matchState = .auto
                            case .review: list[i].matchState = .review
                            case .manual: list[i].matchState = .manual
                            }
                            // Alternatives are only kept while the user may still need them.
                            list[i].candidates = result.confidence == .auto ? [] : result.candidates
                        case .corrected(let info):
                            info.store(in: &list[i])
                            if info.ratingsRefused { omdb = nil }
                            list[i].matchState = .confirmed
                            list[i].matchScore = 1
                            list[i].candidates = []
                            list[i].lastError = nil
                            list[i].lastLookup = now
                        case .failed(let message):
                            list[i].matchState = .failed
                            list[i].lastError = message
                        case .offline:
                            stopMessage = AppModel.offlineMessage
                        case .unauthorized:
                            stopMessage = AppModel.tokenMessage
                        }
                        if let id = list[i].tmdb?.id { newKeys.append(("file:\(job.fileName)", "tmdb:\(id)")) }
                    }
                }
                for (old, new) in newKeys { migratePersonal(from: old, to: new) }
                done += outcomes.count
            }
            work += done

            // Films just looked up already have fresh ratings (or none to be had today).
            let justRated = Set(films.filter { $0.lastLookup.map { $0 >= runStart } ?? false }.compactMap { $0.tmdb?.id })

            // 2. Films whose info is from an older version of Reel or more than a month old get
            // fresh info from the web without changing the match. Each film is tried once per pass.
            var attempted = Set<Int>()
            var refreshed = 0
            while stopMessage == nil {
                var seenIDs = Set<Int>()
                let stale: [Int] = films.compactMap { film in
                    guard let id = film.tmdb?.id, film.infoStale(),
                          !attempted.contains(id), seenIDs.insert(id).inserted else { return nil }
                    return id
                }
                guard !stale.isEmpty else { break }

                let refreshedOne = beginWork("Adding reviews and fun facts", done: refreshed, total: refreshed + stale.count)
                // Twelve at a time: fewer library rebuilds while a big refresh runs.
                let ids = Array(stale.prefix(12))
                // Ratings are only asked for again when missing or older than a month.
                let staleRatings = Set(films.filter { $0.ratingsStale() }.compactMap { $0.tmdb?.id }).subtracting(justRated)
                let ratingsClient = omdb
                let results = await withTaskGroup(of: (Int, Result<FilmInfo, Error>).self, returning: [(Int, Result<FilmInfo, Error>)].self) { group in
                    for id in ids {
                        group.addTask {
                            defer { refreshedOne() }
                            do {
                                let info = try await AppModel.fetchInfo(id: id, client: client, omdb: ratingsClient,
                                                                        ratingsWanted: ratingsWanted && staleRatings.contains(id))
                                return (id, .success(info))
                            } catch {
                                return (id, .failure(error))
                            }
                        }
                    }
                    var all: [(Int, Result<FilmInfo, Error>)] = []
                    for await result in group { all.append(result) }
                    return all
                }
                mutateFilms { list in
                    for (id, result) in results {
                        attempted.insert(id)
                        switch result {
                        case .success(let info):
                            if info.ratingsRefused { omdb = nil }
                            for i in list.indices where list[i].tmdb?.id == id {
                                info.store(in: &list[i])
                            }
                        case .failure(let error):
                            if let tmdbError = error as? TMDBError, case .unauthorized = tmdbError {
                                stopMessage = AppModel.tokenMessage
                            } else if let urlError = error as? URLError, AppModel.isOffline(urlError) {
                                stopMessage = AppModel.offlineMessage
                            }
                        }
                    }
                }
                refreshed += ids.count
            }
            work += refreshed

            // 3. Ratings that couldn't be fetched before: OMDb only, at most once a day per film.
            let dayAgo = Date().addingTimeInterval(-86_400)
            var ratingsAttempted = justRated
            var ratedSoFar = 0
            while stopMessage == nil, let ratingsClient = omdb {
                var seenIDs = Set<Int>()
                let due: [(Int, String)] = films.compactMap { film in
                    guard film.ratingsDue, let d = film.tmdb, let imdbID = d.imdbID, !imdbID.isEmpty,
                          (film.ratingsTriedAt ?? .distantPast) < dayAgo,
                          !ratingsAttempted.contains(d.id), seenIDs.insert(d.id).inserted else { return nil }
                    return (d.id, imdbID)
                }
                guard !due.isEmpty else { break }
                let batch = Array(due.prefix(6))
                let rated = beginWork("Fetching ratings", done: ratedSoFar, total: ratedSoFar + due.count)
                ratedSoFar += batch.count
                let results = await withTaskGroup(of: (Int, ExternalRatings?, Bool, Bool).self,
                                                  returning: [(Int, ExternalRatings?, Bool, Bool)].self) { group in
                    for (id, imdbID) in batch {
                        group.addTask {
                            defer { rated() }
                            do { return (id, try await ratingsClient.ratings(imdbID: imdbID), false, false) }
                            catch OMDbError.unauthorized { return (id, nil, true, true) }
                            catch { return (id, nil, true, false) }
                        }
                    }
                    var all: [(Int, ExternalRatings?, Bool, Bool)] = []
                    for await result in group { all.append(result) }
                    return all
                }
                let now = Date()
                mutateFilms { list in
                    for (id, ratings, failed, refused) in results {
                        ratingsAttempted.insert(id)
                        if refused { omdb = nil }
                        for i in list.indices where list[i].tmdb?.id == id {
                            list[i].applyRatings(ratings, failed: failed, now: now)
                        }
                    }
                }
                work += batch.count
            }
        } while rerunRequested && stopMessage == nil

        if ratingsWanted && omdb == nil && stopMessage == nil {
            notice = "OMDb didn't accept the ratings key, or today's limit is used up. Ratings will be fetched again tomorrow."
        }

        if let stopMessage { notice = stopMessage }
        if work > 0 { ImageStore.shared.maintain(keeping: []) }
    }

    nonisolated static func lookUp(_ job: LookupJob, client: TMDBClient, omdb: OMDbClient?, ratingsWanted: Bool) async -> LookupOutcome {
        do {
            if let id = job.correctedID {
                return .corrected(try await fetchInfo(id: id, client: client, omdb: omdb, ratingsWanted: ratingsWanted,
                                                      withFindings: false))
            }
            let result = try await FilmMatcher(database: client).match(titles: job.titles, year: job.year)
            var info: FilmInfo?
            if let best = result.best, result.confidence != .manual {
                // Poster, details and ratings now; Wikipedia's fun facts and critics right after
                // (the film is then refreshed), so new films show up quickly.
                info = try await fetchInfo(id: best.movie.id, client: client, omdb: omdb, ratingsWanted: ratingsWanted,
                                           withFindings: false)
            }
            return .matched(result, info)
        } catch TMDBError.unauthorized {
            return .unauthorized
        } catch let error as URLError where isOffline(error) {
            return .offline
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Everything Reel stores about one film: TMDB details (trimmed), outside ratings, and a
    /// summary of what reviewers like and dislike (worked out on this Mac, then the reviews are dropped).
    /// - Parameters:
    ///   - omdb: nil when no key is set, or when OMDb refused earlier in this run.
    ///   - ratingsWanted: a key is set, so missing ratings count as a failure to retry later.
    ///   - withFindings: false skips Wikipedia; the film then counts as not fully looked up and is
    ///     refreshed with it later in the same run.
    nonisolated static func fetchInfo(id: Int, client: TMDBClient, omdb: OMDbClient?, ratingsWanted: Bool,
                                      withFindings: Bool = true) async throws -> FilmInfo {
        let full = try await client.movieDetails(id: id)
        // Wikipedia gives the fun facts and what critics wrote; it's a bonus, never a reason to fail.
        let findings = withFindings ? try? await WikipediaClient().findings(imdbID: full.imdbID, title: full.title, year: full.year) : nil
        // (A film without an article gives empty findings; nil means Wikipedia couldn't be reached.)
        var reviews = (full.reviews?.results ?? []).map { ReviewText(text: $0.content, rating: $0.authorDetails?.rating) }
        reviews += (findings?.criticSentences ?? []).map { ReviewText(text: $0, rating: nil, isCritic: true) }
        let reception = Sentiment.summarize(reviews)

        var ratings: ExternalRatings?
        var failed = false
        var refused = false
        if let imdbID = full.imdbID, !imdbID.isEmpty, ratingsWanted {
            if let omdb {
                do {
                    ratings = try await omdb.ratings(imdbID: imdbID)
                } catch OMDbError.unauthorized {
                    failed = true
                    refused = true
                } catch {
                    failed = true
                }
            } else {
                failed = true
            }
        }
        return FilmInfo(details: full.trimmed(), ratings: ratings, reception: reception, funFacts: findings?.funFacts,
                        findingsFailed: findings == nil,
                        ratingsFailed: failed, ratingsRefused: refused, ratingsSkipped: !ratingsWanted)
    }

    nonisolated static func isOffline(_ error: URLError) -> Bool {
        let offlineCodes: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
            .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed,
        ]
        return offlineCodes.contains(error.code)
    }

    /// The same file on the other drive was already looked up: reuse it instead of asking TMDB again.
    private func reuseTwins() {
        var resolved: [String: FilmEntry] = [:]
        for film in films where film.matchState != .pending && film.matchState != .failed {
            resolved[film.fileName] = film
        }
        guard films.contains(where: { $0.matchState == .pending && resolved[$0.fileName] != nil }) else { return }
        var newKeys: [(String, String)] = []
        mutateFilms { list in
            for i in list.indices where list[i].matchState == .pending {
                guard let twin = resolved[list[i].fileName] else { continue }
                list[i].tmdb = twin.tmdb
                list[i].ratings = twin.ratings
                list[i].reception = twin.reception
                list[i].infoVersion = twin.infoVersion
                list[i].infoUpdatedAt = twin.infoUpdatedAt
                list[i].funFacts = twin.funFacts
                list[i].candidates = twin.candidates
                list[i].matchScore = twin.matchScore
                list[i].matchState = twin.matchState
                newKeys.append(("file:\(list[i].fileName)", twin.personalKey))
            }
        }
        for (old, new) in newKeys { migratePersonal(from: old, to: new) }
    }

    /// Manual search. "Dune 2021" searches for Dune from 2021.
    func search(_ query: String) async -> [TMDBMovieSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasToken, !trimmed.isEmpty else { return [] }
        let parsed = FilenameParser.parse(trimmed)
        let client = TMDBClient(token: token)
        if let results = try? await client.searchMovies(query: parsed.title, year: parsed.year), !results.isEmpty {
            return results
        }
        return (try? await client.searchMovies(query: trimmed, year: nil)) ?? []
    }

    /// The user picked the right film for this file (all its copies). Stored in Your Notes, so it
    /// always wins over automatic matching and survives a rebuilt library.
    func choose(_ movie: TMDBMovieSummary, for film: FilmEntry) async {
        guard hasToken else { return }
        let oldKey = film.personalKey
        do {
            let ratingsClient = omdbClient
            let info = try await AppModel.fetchInfo(id: movie.id, client: TMDBClient(token: token), omdb: ratingsClient,
                                                    ratingsWanted: ratingsClient != nil)
            mutateFilms(urgent: true) { list in
                for i in list.indices where list[i].fileName == film.fileName {
                    info.store(in: &list[i])
                    list[i].matchState = .confirmed
                    list[i].matchScore = 1
                    list[i].candidates = []
                    list[i].lastError = nil
                }
            }
            corrections[film.fileName] = info.details.id
            scheduleSave(.notes)
            migratePersonal(from: oldKey, to: "tmdb:\(info.details.id)")
        } catch {
            notice = "Couldn't load that film: \(error.localizedDescription)"
        }
    }

    func confirm(_ film: FilmEntry) {
        let key = film.personalKey
        mutateFilms(urgent: true) { list in
            for i in list.indices where list[i].personalKey == key {
                list[i].matchState = .confirmed
                list[i].candidates = []
            }
        }
        if let id = film.tmdb?.id {
            for copy in films where copy.personalKey == key { corrections[copy.fileName] = id }
            scheduleSave(.notes)
        }
    }

    // MARK: - People

    /// A person and their films, from memory or TMDB.
    func person(id: Int) async -> TMDBPerson? {
        if let cached = personCache[id] { return cached }
        guard hasToken else { return nil }
        guard let person = try? await TMDBClient(token: token).person(id: id) else { return nil }
        personCache[id] = person
        return person
    }

    // MARK: - Fun facts

    /// Fetches behind-the-scenes facts the first time they are wanted, then keeps them for a month
    /// (a week when nothing was found).
    func loadFunFacts(for film: FilmEntry) async {
        guard let details = film.tmdb, !funFactsLoading.contains(details.id) else { return }
        if let existing = film.funFacts {
            let maxAge: TimeInterval = existing.isEmpty ? 7 * 86_400 : FilmEntry.infoMaxAge
            // Facts from before Reel 1.7 lack the aspect ratio and colour the Camera tab shows.
            let lacksCamera = existing.quick != nil && existing.quick?.aspectRatios == nil
            if existing.fetchedAt > Date().addingTimeInterval(-maxAge), !lacksCamera { return }
        }
        funFactsLoading.insert(details.id)
        defer { funFactsLoading.remove(details.id) }
        guard let facts = try? await WikipediaClient().findings(imdbID: details.imdbID, title: details.title, year: details.year).funFacts else {
            return
        }
        mutateFilms { list in
            for i in list.indices where list[i].tmdb?.id == details.id { list[i].funFacts = facts }
        }
    }
}
#endif
