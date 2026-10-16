#if os(macOS)
import Foundation
import ReelCore

/// Searching by craft: each film's Wikipedia article and the interviews and craft articles about
/// it are read in the background, one film at a time, and only the names of the gear and
/// techniques are kept (see `CraftIndex`).
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
            mutateFilms { list in
                for i in list.indices { if let id = list[i].tmdb?.id, let index = batch[id] { list[i].craft = index } }
            }
        }
        defer { write() }
        while !Task.isCancelled {
            // Films whose info and Wikipedia facts are in (the article's title comes with the facts).
            var seen = Set<Int>()
            let due = films.filter { film in
                guard let id = film.tmdb?.id, !attempted.contains(id), film.funFacts != nil, seen.insert(id).inserted else { return false }
                return film.craft?.isStale() ?? true
            }
            if craftPending != due.count + read.count { craftPending = due.count + read.count }
            // Three films at a time (each reads several pages, at most three at once overall).
            let batch = Array(due.prefix(3))
            guard !batch.isEmpty else { return }
            for film in batch { if let id = film.tmdb?.id { attempted.insert(id) } }
            let results = await withTaskGroup(of: (Int, CraftIndex?).self) { group in
                for film in batch {
                    guard let details = film.tmdb else { continue }
                    let title = film.funFacts?.articleTitle
                    let colour = film.funFacts?.quick?.colour
                    group.addTask { (details.id, await Self.readCraft(of: details, articleTitle: title, colour: colour)) }
                }
                var all: [(Int, CraftIndex?)] = []
                for await result in group { all.append(result) }
                return all
            }
            for (id, index) in results {
                if let index {
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
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Nil when nothing could be reached (offline): tried again later.
    nonisolated static func readCraft(of details: TMDBMovieDetails, articleTitle: String?, colour: [String]?) async -> CraftIndex? {
        async let reading = CameraSourcesClient().read(articleTitle: articleTitle, filmTitle: details.title,
                                                       cinematographers: details.cinematographers)
        var reached = articleTitle == nil
        var texts: [TechSpecs.Text] = []
        if let articleTitle {
            do {
                if let article = try await WikipediaClient().article(title: articleTitle) {
                    texts.append(TechSpecs.Text(source: nil, sections: article.before + article.after, isInterview: false))
                }
                reached = true
            } catch {}
        }
        let read = await reading
        texts += read.texts(hiding: false)
        guard reached || !read.sources.isEmpty || read.cinematographer != nil else { return nil }
        let specs = TechSpecs.read(texts: texts, cinematographers: details.cinematographers, directors: details.directors)
        return CraftIndex.make(from: specs, colour: colour, keywords: details.keywordNames)
    }
}
#endif
