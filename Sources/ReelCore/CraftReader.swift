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
                         otherTitles: [String], articleFailed: Bool = false, previous: CraftIndex? = nil, now: Date) -> (index: CraftIndex, specs: TechSpecs) {
        let texts = texts(article: article, reading: reading, hiding: false)
        let people = reading?.research?.contributors ?? Self.crew(of: details, article: article, reading: reading)
        let specs = TechSpecs.read(texts: texts, cinematographers: details.cinematographers, directors: details.directors,
                                   year: details.year, title: details.title, otherTitles: otherTitles, crew: people)
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
        // Where its research stands, dimension by dimension (1.10.7).
        let skipped = reading?.skipped ?? []
        index.research = ResearchCoverage.entries(
            context: ResearchContext(crew: people, specs: specs, texts: texts), run: reading?.research, readSomething: !texts.isEmpty,
            languageLimited: skipped.contains { $0.limit == .language },
            extractionLimited: skipped.contains { $0.limit == .thin || $0.limit == .restricted },
            // A site that didn't answer, the film's own article included (1.10.8): not a verdict on what
            // it might have said, for the dimensions this reading's searches didn't settle.
            unavailable: !index.unanswered.isEmpty || articleFailed, now: now)
        // Every finding with its passage, and the reading before's reconciled with this one (1.10.9).
        index.claims = SourceReconciliation.reconcile(previous: previous, with: reconciliationInput(specs: specs, index: index, texts: texts,
                                                                                                   reading: reading, articleFailed: articleFailed),
                                                      now: now)
        // A gear name carried while its source can't be read is still shown (as a carried tag is).
        for claim in index.claimsKnown where claim.status == .carried && claim.kind != "shotOn"
            && !index.names.contains(where: { SourceReconciliation.sameName($0, claim.name) }) && index.names.count < 30 {
            index.names.append(claim.name)
        }
        return (index, specs)
    }

    /// What reconciling the reading before needs: what was accepted, set aside and mentioned, the text
    /// of each source read, the pages fetched and set aside, and the sites that didn't answer or came
    /// incomplete.
    static func reconciliationInput(specs: TechSpecs, index: CraftIndex, texts: [TechSpecs.Text], reading: CameraReading?,
                                    articleFailed: Bool) -> SourceReconciliation.Input {
        var read: [String: [String]] = [:]
        for text in texts { read[text.source ?? "Wikipedia", default: []] += text.sections.flatMap(\.paragraphs) }
        var fetched: [String: [[String]]] = [:]
        for skipped in reading?.skipped ?? [] where !skipped.source.paragraphs.isEmpty && skipped.limit == nil {
            fetched[skipped.source.site, default: []].append(skipped.source.paragraphs)
        }
        let incomplete = Set(index.limits.filter { $0.detail.contains(CameraSources.incompletePage) || $0.detail.contains(CameraSources.unboundedArticle)
            || $0.kind == .thin }.map(\.site))
        var shotOn: [ShotOn: CraftIndex.Evidence] = [:]
        for evidence in index.evidence { shotOn[evidence.shotOn] = evidence }
        var input = SourceReconciliation.Input(accepted: specs.accepted, judged: specs.judged, mentioned: specs.mentioned, shotOn: shotOn, read: read,
                                               fetched: fetched, unanswered: Set(index.unanswered + (articleFailed ? ["Wikipedia"] : [])),
                                               incomplete: incomplete, rules: index.version)
        input.articles = Set(texts.compactMap(\.article) + (reading?.skipped ?? []).filter { !$0.source.paragraphs.isEmpty && $0.limit == nil }
            .map { CraftIndex.articleIdentity($0.source.url) })
        return input
    }

    /// The film's camera, lighting, colour and VFX people: credited on TMDB, and directors of
    /// photography named only in what was read ("Robert Richardson was originally…").
    public static func crew(of details: TMDBMovieDetails, article: FilmArticle?, reading: CameraReading?) -> [CraftCrew.Contributor] {
        let credited = CraftCrew.credited(details)
        let own = article.map { ($0.before + $0.after).flatMap(\.paragraphs) } ?? []
        return credited + CraftCrew.named(article: own, sources: reading?.sources.flatMap(\.paragraphs) ?? [], title: details.title,
                                          besides: credited)
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
    /// `previous`: the film's reading before, so a search that found nothing isn't repeated within
    /// a year (see `ResearchPlan`).
    public static func read(_ details: TMDBMovieDetails, articleTitle: String?, colour: [String]?,
                            otherTitles: [String] = [], previous: CraftIndex? = nil) async -> Reading? {
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
        let first = await fetched
        guard reached || !first.sources.isEmpty || first.cinematographer != nil else { return nil }
        // What the first pass is missing, looked for (discovery 6).
        let reading = await CameraSourcesClient().researched(first, article: article, filmTitle: details.title,
                                                             cinematographers: details.cinematographers, directors: details.directors,
                                                             year: details.year, otherTitles: otherTitles,
                                                             crew: Self.crew(of: details, article: article, reading: first), previous: previous)
        let now = Date()
        let evaluated = evaluate(details, article: article, reading: reading, colour: colour, otherTitles: otherTitles, articleFailed: articleFailed,
                                 previous: previous, now: now)
        var read = evaluated.index
        noteArticle(&read, articleTitle: articleTitle, article: article, failed: articleFailed)
        return Reading(index: read, log: CraftLog.text(details: details, articleTitle: articleTitle, articleRead: article != nil,
                                                       articleMissing: articleTitle != nil && article == nil && !articleFailed,
                                                       reading: reading, specs: evaluated.specs, index: read, now: now))
    }

    /// The film's own article, when it didn't come: Wikipedia didn't answer (`failed`: read again
    /// later), or answered that there's no such article now. Kept with the reading either way, the
    /// same from the background and the Cinematography tab.
    static func noteArticle(_ index: inout CraftIndex, articleTitle: String?, article: FilmArticle?, failed: Bool) {
        guard let articleTitle, article == nil else { return }
        if failed, !index.unanswered.contains("Wikipedia") { index.unanswered.append("Wikipedia") }
        guard !index.limits.contains(where: { $0.site == "Wikipedia" }) else { return }
        index.limits.append(CraftIndex.SourceLimit(site: "Wikipedia", url: "https://en.wikipedia.org/wiki/" + articleTitle.replacingOccurrences(of: " ", with: "_"),
                                                   kind: failed ? .unanswered : .gone,
                                                   detail: failed ? "didn't answer (read again later)" : "no such article now"))
    }

    /// What the Cinematography tab read (its article and sources, already fetched), as the summary
    /// and its log: the same rules and the same log as the background reading.
    /// `articleFailed`: the article was asked for and Wikipedia didn't answer (not: there's no such article).
    public static func reading(of details: TMDBMovieDetails, articleTitle: String?, article: FilmArticle?, reading: CameraReading?,
                               colour: [String]?, otherTitles: [String] = [], articleFailed: Bool = false, previous: CraftIndex? = nil,
                               now: Date = Date()) -> Reading {
        let evaluated = evaluate(details, article: article, reading: reading, colour: colour, otherTitles: otherTitles, articleFailed: articleFailed,
                                 previous: previous, now: now)
        let sources = reading ?? CameraReading(sources: [], more: [], cinematographer: nil)
        var index = evaluated.index
        noteArticle(&index, articleTitle: articleTitle, article: article, failed: articleFailed)
        return Reading(index: index, log: CraftLog.text(details: details, articleTitle: articleTitle, articleRead: article != nil,
                                                        articleMissing: articleTitle != nil && article == nil && !articleFailed,
                                                        reading: sources, specs: evaluated.specs, index: index, now: now))
    }
}
