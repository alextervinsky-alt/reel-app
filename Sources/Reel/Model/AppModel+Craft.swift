#if os(macOS)
import Foundation
import ReelCore

/// Searching by craft: each film's Wikipedia article and the interviews and craft articles about
/// it are read in the background, two films at a time (see `CraftReader`), and the names of the
/// gear and techniques are kept, with the sentence behind each Shot on (see `CraftIndex`).
extension AppModel {
    /// Reads the films not read yet (or read long ago). Runs after film info is looked up; stops
    /// when offline, and carries on next time.
    func readCraft() async {
        guard !craftRunning else { return }
        craftRunning = true
        defer {
            craftRunning = false
            if craftPending != 0 { craftPending = 0 }
        }
        var attempted = Set<Int>()
        var failedInARow = 0
        // Kept and written in batches: the library is rebuilt once per batch, not per film.
        var read: [Int: CraftIndex] = [:]
        var lastWrite = Date()
        func write() {
            guard !read.isEmpty else { return }
            let batch = read
            read = [:]
            lastWrite = Date()
            storeCraft(batch)
        }
        defer { write() }
        while !Task.isCancelled {
            // Films whose info and Wikipedia facts are in (the article's title comes with the facts).
            var seen = Set<Int>()
            let due = films.filter { film in
                guard let id = film.tmdb?.id, !attempted.contains(id), film.funFacts != nil, needsReading(film) else { return false }
                return seen.insert(id).inserted
            }
            if craftPending != due.count + read.count { craftPending = due.count + read.count }
            // Two films at a time (each reads its article and camera sources side by side).
            let batch = Array(due.prefix(2))
            guard !batch.isEmpty else { return }
            for film in batch { if let id = film.tmdb?.id { attempted.insert(id) } }
            // Their collections first (cached for two weeks), so a sequel's articles aren't read.
            for film in batch { if let details = film.tmdb { await loadCollection(of: details) } }
            let results = await withTaskGroup(of: (Int, CraftIndex?).self) { group in
                for film in batch {
                    guard let details = film.tmdb else { continue }
                    let title = film.funFacts?.articleTitle
                    let colour = film.funFacts?.quick?.colour
                    let others = otherTitles(of: details)
                    group.addTask { (details.id, await CraftReader.read(details, articleTitle: title, colour: colour, otherTitles: others)) }
                }
                var all: [(Int, CraftIndex?)] = []
                for await result in group { all.append(result) }
                return all
            }
            for (id, index) in results {
                if let index, let old = films.first(where: { $0.tmdb?.id == id })?.craft, old.keeps(over: index) {
                    // Read from fewer texts than last time (a site down): kept as it was, and tried
                    // again in a week rather than in half a year.
                    read[id] = CraftIndex(version: old.version, readAt: Date().addingTimeInterval(7 * 86_400 - CraftIndex.maxAge),
                                          shotOn: old.shotOn, names: old.names, evidence: old.evidence, sources: old.sources,
                                          discovery: CraftIndex.currentDiscovery)
                    failedInARow = 0
                } else if let index {
                    read[id] = index
                    failedInARow = 0
                } else {
                    // One film that can't be read is tried again next time; several in a row: offline.
                    failedInARow += 1
                }
            }
            if failedInARow >= 6 { return }
            if read.count >= 9 || Date().timeIntervalSince(lastWrite) > 30 { write() }
            // A short pause between batches, whatever the size of the library.
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Not read yet, read long ago or by older rules, or read before a sequel's articles were told
    /// apart from its own (a film of a collection, read before discovery 2).
    func needsReading(_ film: FilmEntry) -> Bool {
        guard let craft = film.craft else { return true }
        return craft.isStale() || (craft.discovery < CraftIndex.currentDiscovery && film.tmdb?.collection != nil)
    }

    /// Fetches the film's collection from TMDB when it isn't kept yet (two weeks; see `ListsStore`).
    func loadCollection(of details: TMDBMovieDetails) async {
        guard let collection = details.collection, hasToken else { return }
        _ = await lists.loadFranchise(collection.id, using: TMDBClient(token: token))
    }

    /// The other films of its collection, whose articles aren't read for it: The Matrix
    /// Resurrections' for The Matrix.
    func otherTitles(of details: TMDBMovieDetails) -> [String] {
        guard let collection = details.collection, let set = lists.sets[FilmSet.id(.franchise, collection.id)] else { return [] }
        return set.films.filter { $0.id != details.id }.map(\.title)
    }

    /// How much of the library Shot on covers (Settings › Performance): live-action films, each
    /// once, tagged out of those read; those read from their Wikipedia article alone; and how many
    /// are still to be read. Animated films aren't counted: they weren't shot on anything.
    func craftCoverage() -> (tagged: Int, read: Int, articleOnly: Int, waiting: Int) {
        var seen = Set<Int>()
        var tagged = 0, read = 0, articleOnly = 0, waiting = 0
        for film in films {
            guard let details = film.tmdb, seen.insert(details.id).inserted, !details.genreNames.contains("Animation") else { continue }
            guard let craft = film.craft, !craft.isStale() else {
                waiting += 1
                continue
            }
            read += 1
            if !craft.shotOn.isEmpty { tagged += 1 }
            if craft.sources <= 1 { articleOnly += 1 }
        }
        return (tagged, read, articleOnly, waiting)
    }

    /// Puts new readings in the library, noting each film whose Shot on changed (Settings ›
    /// Performance lists them, so a change can be checked).
    func storeCraft(_ batch: [Int: CraftIndex]) {
        guard !batch.isEmpty else { return }
        var changes: [CraftChange] = []
        var noted = Set<Int>()
        mutateFilms { list in
            for i in list.indices {
                guard let id = list[i].tmdb?.id, let index = batch[id] else { continue }
                let before = list[i].craft?.shotOn
                if let before, before != index.shotOn, noted.insert(id).inserted {
                    changes.append(CraftChange(title: list[i].displayTitle, before: before, after: index.shotOn))
                }
                list[i].craft = index
            }
        }
        if !changes.isEmpty { craftChanges = Array((changes + craftChanges).prefix(200)) }
    }

    /// What the Cinematography tab just read becomes the film's summary too, so the Shot on filter
    /// and search say what the tab shows (unless it read fewer texts than the summary had).
    func craftRead(for film: FilmEntry, article: FilmArticle?, reading: CameraReading?) {
        guard let details = film.tmdb, article != nil || reading != nil else { return }
        let index = CraftReader.index(of: details, article: article, reading: reading, colour: film.funFacts?.quick?.colour)
        let current = films.first { $0.tmdb?.id == details.id }?.craft
        if let current, current.keeps(over: index) { return }
        // The same as already kept: nothing to write.
        if let current, current.version == index.version, current.shotOn == index.shotOn, current.names == index.names,
           current.evidence == index.evidence, !current.isStale() { return }
        storeCraft([details.id: index])
    }
}

/// A film whose Shot on changed when it was read again.
struct CraftChange: Identifiable {
    let id = UUID()
    let title: String
    let before: [ShotOn]
    let after: [ShotOn]
}
#endif
