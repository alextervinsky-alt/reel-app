import Foundation

/// One way of reading how a film was shot, for everything that shows it: the Cinematography tab,
/// the Shot on filter, search by craft and the cinematographers' pages read the same texts in the
/// same order, by the same rules.
public enum CraftReader {
    /// What's read, in order: the interviews and craft articles (the filmmakers' own words lead),
    /// the film's Wikipedia article, then what the cinematographer's article says about the film.
    /// `hiding` leaves out the story (spoiler-safe) for what's shown.
    public static func texts(article: FilmArticle?, reading: CameraReading?, hiding: Bool) -> [TechSpecs.Text] {
        var texts = reading?.texts(hiding: hiding) ?? []
        if let article {
            let sections = article.before + (hiding ? [] : article.after)
            texts.insert(TechSpecs.Text(source: nil, sections: sections, isInterview: false),
                         at: min(texts.count, reading?.sources.count ?? 0))
        }
        return texts
    }

    /// The search and Shot on summary of what was read (the whole of it: nothing is shown from it
    /// but its "why" sentences, which are checked for the story when shown).
    /// `otherTitles`: the other films of its collection, so what's said of them isn't this one's.
    public static func index(of details: TMDBMovieDetails, article: FilmArticle?, reading: CameraReading?,
                             colour: [String]?, otherTitles: [String] = [], now: Date = Date()) -> CraftIndex {
        evaluate(details, article: article, reading: reading, colour: colour, otherTitles: otherTitles, now: now).index
    }

    /// The summary and the reading it came from.
    static func evaluate(_ details: TMDBMovieDetails, article: FilmArticle?, reading: CameraReading?, colour: [String]?,
                         otherTitles: [String], now: Date) -> (index: CraftIndex, specs: TechSpecs) {
        let texts = texts(article: article, reading: reading, hiding: false)
        let specs = TechSpecs.read(texts: texts, cinematographers: details.cinematographers, directors: details.directors,
                                   year: details.year, title: details.title, otherTitles: otherTitles)
        var index = CraftIndex.make(from: specs, colour: colour, keywords: details.keywordNames, sources: texts.count, now: now)
        index.unanswered = reading?.unanswered ?? []
        // What was found and couldn't be examined, kept with the reading (not only in the log).
        index.limits = (reading?.skipped ?? []).compactMap { skipped in
            skipped.limit.map { CraftIndex.SourceLimit(site: skipped.source.site, url: skipped.source.url.absoluteString, kind: $0,
                                                       detail: skipped.reason) }
        }
        // Where it was read, as its sentences' sources say it (what `CraftIndex.merge` compares).
        var read: [String] = []
        for text in texts where !read.contains(text.source ?? "Wikipedia") { read.append(text.source ?? "Wikipedia") }
        index.read = read
        return (index, specs)
    }

    /// A film read: the summary, and the log of what was read for it (see `CraftLog`).
    public struct Reading: Sendable {
        public let index: CraftIndex
        public let log: String

        public init(index: CraftIndex, log: String) {
            self.index = index
            self.log = log
        }
    }

    /// Fetches the film's article and what's written about how it was shot, and reads them. Nil when
    /// nothing could be reached (offline): tried again later.
    /// `otherTitles`: the other films of its collection, so their articles aren't read for it.
    public static func read(_ details: TMDBMovieDetails, articleTitle: String?, colour: [String]?,
                            otherTitles: [String] = []) async -> Reading? {
        async let fetched = CameraSourcesClient().read(articleTitle: articleTitle, filmTitle: details.title,
                                                       cinematographers: details.cinematographers,
                                                       directors: details.directors, year: details.year, otherTitles: otherTitles)
        var reached = articleTitle == nil
        var article: FilmArticle?
        // Wikipedia didn't answer (not: answered that there's no such page, which is read).
        var articleFailed = false
        if let articleTitle {
            do {
                article = try await WikipediaClient().article(title: articleTitle)
                reached = true
            } catch {
                articleFailed = true
            }
        }
        let reading = await fetched
        guard reached || !reading.sources.isEmpty || reading.cinematographer != nil else { return nil }
        let now = Date()
        let evaluated = evaluate(details, article: article, reading: reading, colour: colour, otherTitles: otherTitles, now: now)
        var read = evaluated.index
        // The film's own article didn't come: read again later too.
        if articleFailed, !read.unanswered.contains("Wikipedia") { read.unanswered.append("Wikipedia") }
        if let articleTitle, article == nil {
            read.limits.append(CraftIndex.SourceLimit(site: "Wikipedia", url: "https://en.wikipedia.org/wiki/" + articleTitle.replacingOccurrences(of: " ", with: "_"),
                                                      kind: articleFailed ? .unanswered : .gone,
                                                      detail: articleFailed ? "didn't answer (read again later)" : "no such article now"))
        }
        return Reading(index: read, log: CraftLog.text(details: details, articleTitle: articleTitle, articleRead: article != nil,
                                                       articleMissing: articleTitle != nil && article == nil && !articleFailed,
                                                       reading: reading, specs: evaluated.specs, index: read, now: now))
    }

    /// What the Cinematography tab read (its article and sources, already fetched), as the summary
    /// and its log: the same rules and the same log as the background reading.
    public static func reading(of details: TMDBMovieDetails, articleTitle: String?, article: FilmArticle?, reading: CameraReading?,
                               colour: [String]?, otherTitles: [String] = [], now: Date = Date()) -> Reading {
        let evaluated = evaluate(details, article: article, reading: reading, colour: colour, otherTitles: otherTitles, now: now)
        let sources = reading ?? CameraReading(sources: [], more: [], cinematographer: nil)
        return Reading(index: evaluated.index, log: CraftLog.text(details: details, articleTitle: articleTitle, articleRead: article != nil,
                                                                  reading: sources, specs: evaluated.specs, index: evaluated.index, now: now))
    }
}
