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
        defer { craftRunning = false }
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
            guard let film = films.first(where: { film in
                guard let id = film.tmdb?.id, !attempted.contains(id), film.funFacts != nil else { return false }
                return film.craft?.isStale() ?? true
            }), let details = film.tmdb else { return }
            attempted.insert(details.id)
            if let index = await Self.readCraft(of: details, articleTitle: film.funFacts?.articleTitle,
                                                colour: film.funFacts?.quick?.colour) {
                read[details.id] = index
                failedInARow = 0
            } else {
                // One film that can't be read is tried again next time; several in a row: offline.
                failedInARow += 1
                if failedInARow >= 3 { return }
            }
            if read.count >= 8 || Date().timeIntervalSince(lastWrite) > 60 { write() }
            // Gently: one film every few seconds, whatever the size of the library.
            try? await Task.sleep(for: .seconds(3))
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
