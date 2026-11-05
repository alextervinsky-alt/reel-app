import Foundation

/// Reel's research loop for one film (1.10.8, discovery 7), the same for every film: what it
/// already knows (the first pass and the film's article, read by the usual rules), which questions
/// are open (`ResearchPlan.open`), who can answer them (the film's crew, by role), which providers
/// can speak to them (`ResearchProvider`), a bounded plan of searches, then for each result three
/// separate decisions: is the candidate worth asking for (it names the film, or is found by the
/// person searched for), what is the page (`PageContext`: about the film, or something else that
/// mentions it), and what on it is anchored to the film (only that is read). What's read joins the
/// reading's sources; the coverage is decided afterwards from everything the reading attempted.
/// Nothing here knows a film, a person or a page: only the film's title, its people and its
/// collection's other titles.
public enum ResearchEngine {
    public static func run(_ base: CameraReading, article: FilmArticle?, filmTitle: String, cinematographers: [String],
                           directors: [String], year: Int?, otherTitles: [String], crew: [CraftCrew.Contributor],
                           previous: CraftIndex?, providers: [ResearchProvider] = ResearchProvider.all,
                           transport: ResearchTransport, now: Date = Date()) async -> CameraReading {
        // 1. What's known.
        var texts = base.texts(hiding: false)
        if let article { texts.append(TechSpecs.Text(source: nil, sections: article.before + article.after, isInterview: false)) }
        let specs = TechSpecs.read(texts: texts, cinematographers: cinematographers, directors: directors, year: year,
                                   title: filmTitle, otherTitles: otherTitles, crew: crew)
        let context = ResearchContext(crew: crew, specs: specs, texts: texts)
        // 2. What's open, and where to look.
        let open = ResearchPlan.open(context)
        let missing = ResearchDimension.allCases.filter { dimension in open.contains { $0.dimension == dimension } }
        let quiet = ResearchPlan.quiet(previous?.research, discovery: CraftIndex.currentDiscovery, readAt: previous?.readAt, now: now)
        var run = ResearchRun(contributors: crew, missing: missing, quiet: quiet.filter { missing.contains($0.dimension) },
                              open: open.map(\.id))
        let queries = ResearchPlan.plan(open: open, crew: crew, title: filmTitle, providers: providers, previous: previous?.research,
                                        discovery: CraftIndex.currentDiscovery, readAt: previous?.readAt, now: now)
        // 3. The budget left by the first pass: every page it asked for (those assembled, the further
        // result when asked, and at least every page read or set aside after loading).
        var asked = base.discovery?.assembly.asked.count ?? 0
        if let fallback = base.discovery?.fallback {
            if case .notTried = fallback.result {} else { asked += 1 }
        }
        asked = max(asked, Set((base.sources + base.skipped.map(\.source)).map { CameraSources.identity($0.url) }).count)
        var pagesLeft = min(ResearchPlan.maxPages, max(0, CameraSources.askLimit - asked))
        var readLeft = max(0, CameraSources.readLimit - base.sources.count)
        var known = Set((base.sources + base.more + base.skipped.map(\.source)).map { CameraSources.identity($0.url) })
        let unanswered = UnansweredSites()
        var sources = base.sources
        var skipped = base.skipped
        let people = cinematographers + directors + crew.map(\.name)
        for query in queries {
            guard pagesLeft > 0, readLeft > 0 else {
                run.outcomes.append(ResearchOutcome(query: query, result: .notTried("no page left to ask for or read")))
                continue
            }
            guard let provider = providers.first(where: { $0.name == query.site }) else {
                run.outcomes.append(ResearchOutcome(query: query, result: .notTried("no search on \(query.site)")))
                continue
            }
            let answer = await transport.researchSearch(provider, query: query.text, noting: unanswered)
            if let failure = answer.failure {
                run.outcomes.append(ResearchOutcome(query: query, result: .unavailable(failure)))
                continue
            }
            // 4. Candidates: not already known, not another film of the collection; found by a
            // person's name, the result names the film or the person; the film named first.
            let candidates = answer.hits.filter { hit in
                guard let url = URL(string: hit.url), !known.contains(CameraSources.identity(CameraSources.secure(url))),
                      !CameraSources.namesOtherFilm(hit.title, link: hit.url, film: filmTitle, otherTitles: otherTitles) else { return false }
                let aboutFilm = CameraSources.isAbout(title: filmTitle, articleTitle: hit.title, url: hit.url)
                if let person = query.contributor {
                    return aboutFilm || CameraSources.namesCinematographer(title: hit.title, link: hit.url, cinematographers: [person]) == 2
                }
                // Found by the film's title: only a result that names it.
                return aboutFilm
            }.sorted { a, b in
                CameraSources.isAbout(title: filmTitle, articleTitle: a.title, url: a.url)
                    && !CameraSources.isAbout(title: filmTitle, articleTitle: b.title, url: b.url)
            }
            guard !candidates.isEmpty else {
                run.outcomes.append(ResearchOutcome(query: query, result: .noCandidate(answer.hits.count)))
                continue
            }
            var read: [String] = [], passed: [String] = []
            var unavailable = false, foreign = false, unreadable = false, overLimit = false
            for hit in candidates.prefix(min(2, pagesLeft)) {
                guard let url = URL(string: hit.url).map(CameraSources.secure) else { continue }
                known.insert(CameraSources.identity(url))
                pagesLeft -= 1
                let site = SourceRegistry.entry(host: url.host ?? "")?.name ?? query.site
                let got = await transport.researchPage(url, site: site, title: hit.title.isEmpty ? nil : hit.title, noting: unanswered)
                guard var fetched = got.source else {
                    let stand = CameraReading.Source(title: hit.title.isEmpty ? site : hit.title, site: site, url: url, paragraphs: [])
                    let failure = got.failure
                    skipped.append(CameraReading.Skipped(source: stand, reason: (failure?.reason ?? "couldn't be read") + " (found searching for \(query.text))",
                                                         limit: CameraSources.limit(page: nil, failure: failure, otherFilm: false)))
                    passed.append(url.absoluteString)
                    switch failure {
                    case .unanswered?, .wait?: unavailable = true
                    case .language?: foreign = true
                    case .restricted?: unreadable = true
                    case .gone?, nil: break
                    }
                    if pagesLeft <= 0 { break }
                    continue
                }
                // The same article as one already read or set aside, at another address (1.10.9): once.
                if let same = (base.sources + sources + skipped.map(\.source)).first(where: { CameraSources.sameArticle($0, fetched) }) {
                    skipped.append(CameraReading.Skipped(source: fetched, reason: "the same article as \(same.url.absoluteString) (found searching for \(query.text))"))
                    passed.append(url.absoluteString)
                    if pagesLeft <= 0 { break }
                    continue
                }
                // 5. The page's context, and what on it is anchored to the film.
                fetched = CameraSources.judged(fetched, filmTitle: filmTitle, otherTitles: otherTitles, people: people, year: year)
                let judged = fetched.context ?? PageContext(kind: .targetFilm, anchored: 0)
                let namesPerson = query.contributor.map { person in
                    CameraSources.fold(fetched.paragraphs.joined(separator: " ")).contains(CameraSources.fold(person))
                } ?? true
                if !judged.aboutFilm && judged.anchored == 0 || !confirmed(fetched, title: filmTitle, year: year, people: people) {
                    let why = CameraSources.passingMention + " (\(judged.kind.label); found searching for \(query.text))"
                    skipped.append(CameraReading.Skipped(source: fetched, reason: why))
                    run.passed.append((url: url.absoluteString, why: judged.kind.label))
                    passed.append(url.absoluteString)
                } else if !namesPerson {
                    skipped.append(CameraReading.Skipped(source: fetched, reason: "found searching for \(query.text), but it doesn't name \(query.text)"))
                    passed.append(url.absoluteString)
                } else if fetched.paragraphs.count < 3 {
                    skipped.append(CameraReading.Skipped(source: fetched, reason: "too little text to read", limit: .thin))
                    passed.append(url.absoluteString)
                    unreadable = true
                } else if readLeft <= 0 {
                    skipped.append(CameraReading.Skipped(source: fetched, reason: "six sources were already read"))
                    overLimit = true
                } else {
                    sources.append(fetched)
                    readLeft -= 1
                    read.append(url.absoluteString)
                }
                if pagesLeft <= 0 { break }
            }
            let result: ResearchOutcome.Result = !read.isEmpty ? .read(read)
                : unavailable ? .pageUnavailable(passed)
                : foreign ? .pageLanguage(passed)
                : unreadable ? .pageUnreadable(passed)
                : overLimit ? .notTried("six sources were already read")
                : .nothingUsable(passed)
            run.outcomes.append(ResearchOutcome(query: query, result: result))
        }
        var result = base
        if !queries.isEmpty {
            var reading = CameraReading(sources: sources, more: base.more, cinematographer: base.cinematographer,
                                        unanswered: base.unanswered + (await unanswered.all()).filter { !base.unanswered.contains($0) },
                                        skipped: skipped)
            reading.discovery = base.discovery
            result = reading
        }
        result.research = run
        return result
    }

    /// A short or common title ("Her", "Heat", "Joker") names nearly any page: the page must also
    /// give the film's year or one of its people (surnames of four letters or more). A distinctive
    /// title (two words or more, eight letters or more) is enough by itself.
    static func confirmed(_ page: CameraReading.Source, title: String, year: Int?, people: [String]) -> Bool {
        let short = (title.split(separator: ":").first.map(String.init) ?? title).trimmingCharacters(in: .whitespaces)
        if short.split(separator: " ").count >= 2 && short.filter(\.isLetter).count >= 8 { return true }
        let raw = page.paragraphs.joined(separator: " ")
        if let year, raw.contains(String(year)) { return true }
        return people.compactMap { $0.split(separator: " ").last.map(String.init) }.filter { $0.count >= 4 }.contains { surname in
            raw.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: surname) + #"\b"#, options: .regularExpression) != nil
        }
    }
}
