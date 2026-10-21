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
        let texts = texts(article: article, reading: reading, hiding: false)
        let specs = TechSpecs.read(texts: texts, cinematographers: details.cinematographers, directors: details.directors,
                                   year: details.year, title: details.title, otherTitles: otherTitles)
        var index = CraftIndex.make(from: specs, colour: colour, keywords: details.keywordNames, sources: texts.count, now: now)
        index.unanswered = reading?.unanswered ?? []
        return index
    }

    /// Fetches the film's article and what's written about how it was shot, and reads them. Nil when
    /// nothing could be reached (offline): tried again later.
    /// `otherTitles`: the other films of its collection, so their articles aren't read for it.
    public static func read(_ details: TMDBMovieDetails, articleTitle: String?, colour: [String]?,
                            otherTitles: [String] = []) async -> CraftIndex? {
        async let fetched = CameraSourcesClient().read(articleTitle: articleTitle, filmTitle: details.title,
                                                       cinematographers: details.cinematographers,
                                                       directors: details.directors, year: details.year, otherTitles: otherTitles)
        var reached = articleTitle == nil
        var article: FilmArticle?
        if let articleTitle {
            do {
                article = try await WikipediaClient().article(title: articleTitle)
                reached = true
            } catch {}
        }
        let reading = await fetched
        guard reached || !reading.sources.isEmpty || reading.cinematographer != nil else { return nil }
        var read = index(of: details, article: article, reading: reading, colour: colour, otherTitles: otherTitles)
        // The film's own article didn't come: read again later too.
        if articleTitle != nil, article == nil, !read.unanswered.contains("Wikipedia") { read.unanswered.append("Wikipedia") }
        return read
    }
}
