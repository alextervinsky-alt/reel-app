import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where the Cinematography tab reads beyond the film's Wikipedia article: the interviews and craft
/// articles the article cites (American Cinematographer, British Cinematographer, IndieWire's
/// craft pieces, Kodak, ARRI…), American Cinematographer's and British Cinematographer's own
/// articles about the film, Kodak's and No Film School's stories of it, and the cinematographer's
/// Wikipedia article. All free to read; only paragraphs are kept, in memory.
public struct CameraReading: Equatable, Sendable {
    public struct Source: Equatable, Sendable, Identifiable {
        /// The article's title ("Universal Translator: Arrival").
        public let title: String
        /// "American Cinematographer".
        public let site: String
        public let url: URL
        public let paragraphs: [String]
        public var id: URL { url }
    }

    /// Read in full, best first.
    public let sources: [Source]
    /// Cited too, but not readable here (a paywall, or a page Reel can't read): linked only.
    public let more: [Source]
    /// The cinematographer's Wikipedia article: its opening, and what it says about this film.
    public let cinematographer: Cinematographer?

    public struct Cinematographer: Equatable, Sendable {
        public let name: String
        public let lead: String
        /// Paragraphs of their article that name this film.
        public let aboutThisFilm: [String]
        public let url: URL
    }

    /// Sites that didn't answer, or asked Reel to wait (a captcha, "too many requests"): what was
    /// read is kept, and the film is read again later.
    public var unanswered: [String] = []

    public init(sources: [Source], more: [Source], cinematographer: Cinematographer?, unanswered: [String] = []) {
        self.sources = sources
        self.more = more
        self.cinematographer = cinematographer
        self.unanswered = unanswered
    }

    /// Everything to read for `TechSpecs`, interviews first (the filmmakers' own words).
    public func texts(hiding spoilers: Bool) -> [TechSpecs.Text] {
        func safe(_ paragraphs: [String]) -> [String] {
            spoilers ? paragraphs.filter { !Spoilers.mentionsPlot($0) } : paragraphs
        }
        var texts = sources.map { TechSpecs.Text(source: $0.site, paragraphs: safe($0.paragraphs)) }
        if let cinematographer, !cinematographer.aboutThisFilm.isEmpty {
            texts.append(TechSpecs.Text(source: "Wikipedia: \(cinematographer.name)", paragraphs: safe(cinematographer.aboutThisFilm),
                                        isInterview: false))
        }
        return texts
    }
}

/// The sites that didn't answer while one film was read.
public actor UnansweredSites {
    private var sites: [String] = []

    public init() {}

    func add(_ site: String) {
        if !site.isEmpty, !sites.contains(site) { sites.append(site) }
    }

    public func all() -> [String] { sites }
}

/// One request at a time to each site, a second apart, and a site that asked Reel to wait left
/// alone for twenty minutes: magazines answer a library being read slowly, not all at once.
public actor HostPacer {
    private var next: [String: Date] = [:]
    private var pausedUntil: [String: Date] = [:]
    static let spacing: TimeInterval = 1.0
    static let pause: TimeInterval = 20 * 60

    func isPaused(_ host: String) -> Bool { (pausedUntil[host] ?? .distantPast) > Date() }

    func pause(_ host: String) { pausedUntil[host] = Date().addingTimeInterval(Self.pause) }

    /// Waits for this site's next turn (taken before waiting, so turns stay a second apart).
    func turn(_ host: String) async {
        let now = Date()
        let at = max(now, next[host] ?? now)
        next[host] = at.addingTimeInterval(Self.spacing)
        let wait = at.timeIntervalSince(now)
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
    }
}

public enum CameraSources {
    /// A page asking for proof that a person is reading (SiteGround's "sgcaptcha", Cloudflare's
    /// challenge), not the page.
    public static func isChallenge(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
        return ["sgcaptcha", "cf-chl", "challenge-platform", "<title>just a moment", "attention required"].contains { head.contains($0) }
    }

    /// Sites that write about how films are shot, and their names.
    static let craftSites: [(host: String, name: String)] = [
        ("theasc.com", "American Cinematographer"), ("ascmag.com", "American Cinematographer"),
        ("britishcinematographer.co.uk", "British Cinematographer"), ("kodak.com", "Kodak"), ("arri.com", "ARRI"),
        ("panavision.com", "Panavision"), ("cookeoptics.com", "Cooke Optics"), ("zeiss.com", "ZEISS"),
        ("fdtimes.com", "Film and Digital Times"), ("nofilmschool.com", "No Film School"),
        ("filmmakermagazine.com", "Filmmaker"), ("ymcinema.com", "Y.M.Cinema"), ("newsshooter.com", "Newsshooter"),
        ("postperspective.com", "postPerspective"), ("provideocoalition.com", "ProVideo Coalition"),
        ("studiodaily.com", "StudioDaily"), ("motionpictures.org", "The Credits"), ("cined.com", "CineD"),
        ("cinematography.world", "Cinematography World"), ("britishcinematographer.com", "British Cinematographer"),
        ("icgmagazine.com", "ICG Magazine"), ("definitionmagazine.com", "Definition"), ("redsharknews.com", "RedShark News"),
        ("thefilmstage.com", "The Film Stage"),
    ]
    /// News sites cited for many things, free to read: only their pieces about the shooting count.
    /// (Sites behind a paywall aren't read.)
    static let newsSites: [(host: String, name: String)] = [
        ("indiewire.com", "IndieWire"), ("variety.com", "Variety"),
        ("deadline.com", "Deadline"), ("theguardian.com", "The Guardian"), ("collider.com", "Collider"),
        ("slashfilm.com", "/Film"), ("polygon.com", "Polygon"), ("theplaylist.net", "The Playlist"),
        ("thewrap.com", "TheWrap"), ("rogerebert.com", "RogerEbert.com"), ("befilmtv.com", "Be Film"),
    ]
    /// Words in a news article's address that say it's about the camera work.
    static let craftWords = ["cinematograph", "camera", "lens", "lighting", "-dp-", "dp-interview", "director-of-photography",
                             "craft", "film-stock", "35mm", "65mm", "16mm", "anamorphic", "colorist", "color-grade", "framing"]

    /// The cited links worth reading, best first: craft sites, then news pieces about the shooting;
    /// those naming the cinematographer before the rest. At most `limit`.
    public static func pick(_ links: [String], cinematographers: [String], limit: Int = 8) -> [(url: URL, site: String)] {
        let surnames = cinematographers.compactMap { $0.split(separator: " ").last.map { $0.lowercased() } }
            .filter { $0.count >= 3 }
        var seen = Set<String>()
        var picked: [(url: URL, site: String, rank: Int)] = []
        for (index, link) in links.enumerated() {
            guard let url = URL(string: link), let scheme = url.scheme, scheme.hasPrefix("http"),
                  let host = url.host?.lowercased() else { continue }
            let path = url.path.lowercased()
            // Front pages, tags and searches aren't articles.
            guard path.count > 8, !path.contains("/tag/"), !path.contains("/search"), !path.contains("/category/") else { continue }
            let key = host + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard seen.insert(key).inserted else { continue }
            let namesThem = surnames.contains { path.contains($0) }
            if let site = craftSites.first(where: { host == $0.host || host.hasSuffix("." + $0.host) }) {
                picked.append((url, site.name, (namesThem ? 0 : 100) + index))
            } else if let site = newsSites.first(where: { host == $0.host || host.hasSuffix("." + $0.host) }),
                      namesThem || craftWords.contains(where: { path.contains($0) }) {
                picked.append((url, site.name, (namesThem ? 200 : 300) + index))
            }
        }
        return picked.sorted { $0.rank < $1.rank }.prefix(limit).map { ($0.url, $0.site) }
    }

    /// A title as sites write it in their addresses: "The Brutalist" → "the-brutalist",
    /// "Amélie" → "amelie".
    public static func slug(_ title: String) -> String {
        let folded = title.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "&", with: " and ").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        return folded.split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
    }

    /// Whether a page is about another craft (the editor, composer, costumes, sound…) and not the
    /// camera: its title names that craft and neither the cinematographer nor the cinematography.
    public static func isOtherCraft(title: String, cinematographers: [String]) -> Bool {
        let heading = title.lowercased()
        let others = ["editor", "editing", "composer", "score", "costume", "production design", "sound design",
                      "makeup", "make-up", "casting", "screenwriter", "visual effects", "vfx"]
        // Whole words ("score", not "underscore"; "casting", not "broadcasting").
        let padded = " " + String(heading.map { $0.isLetter || $0 == "-" ? $0 : " " }) + " "
        guard others.contains(where: { padded.contains(" " + $0 + " ") || padded.contains(" " + $0 + "s ") }) else { return false }
        let camera = ["cinematograph", "director of photography", " dp ", "camera", "lens", "lighting", "shot on"]
        if camera.contains(where: { padded.contains($0) }) { return false }
        let surnames = cinematographers.compactMap { $0.split(separator: " ").last.map { $0.lowercased() } }.filter { $0.count >= 3 }
        return !surnames.contains { heading.contains($0) }
    }

    /// Search results whose title (or address) names the film, and no other film of its collection,
    /// each once, at most `limit`.
    static func about(_ filmTitle: String, in hits: [(title: String, link: String)], site: String,
                      limit: Int, otherTitles: [String] = []) -> [(url: URL, site: String, title: String?)] {
        var found: [(url: URL, site: String, title: String?)] = []
        for hit in hits where isAbout(title: filmTitle, articleTitle: hit.title, url: hit.link)
            && !namesOtherFilm(hit.title, link: hit.link, film: filmTitle, otherTitles: otherTitles) {
            guard let link = URL(string: hit.link), !found.contains(where: { $0.url == link }) else { continue }
            found.append((link, site, HTMLText.plain(hit.title)))
        }
        return Array(found.prefix(limit))
    }

    /// Whether a search result is about another film of the collection, by its title or its
    /// address ("The Matrix Resurrections" when reading about The Matrix, ".../blade-runner-2049-…"
    /// when reading about Blade Runner). Another title that this film's own continues ("The Matrix
    /// Resurrections") always counts; one that doesn't (the franchise's first title, "Star Wars: The
    /// Empire Strikes Back") counts only when this film isn't named too. A title that's part of
    /// this film's own ("Sicario" for "Sicario: Day of the Soldado") never counts.
    public static func namesOtherFilm(_ heading: String, link: String = "", film: String, otherTitles: [String]) -> Bool {
        let own = TitleSimilarity.normalize(film)
        let padded = " " + TitleSimilarity.normalize(HTMLText.plain(heading)) + " "
        let ownNamed = padded.contains(" " + own + " ")
        let path = "/" + (URL(string: link)?.path ?? "").lowercased().split(separator: "/").joined(separator: "/") + "/"
        return otherTitles.contains { other in
            let name = TitleSimilarity.normalize(other)
            guard !name.isEmpty, !(" " + own + " ").contains(" " + name + " ") else { return false }
            let otherSlug = slug(other)
            let named = padded.contains(" " + name + " ")
                || (!otherSlug.isEmpty && (path.contains("/" + otherSlug + "-") || path.contains("/" + otherSlug + "/")
                                           || path.contains("-" + otherSlug + "-") || path.contains("-" + otherSlug + "/")))
            guard named else { return false }
            let continuesOwn = (" " + name + " ").contains(" " + own + " ")
            return continuesOwn || !ownNamed
        }
    }

    /// Whether a page found by searching for the title is about this film and not another of the
    /// same name: it names the film's cinematographer. Not the director, or the year alone: a
    /// sequel's article names both ("The Matrix Resurrections" names the Wachowskis and 1999).
    /// Only when the cinematographer isn't known do the director and the year (or one either side)
    /// together do. Names are matched without regard to case, accents or hyphens ("Erdély",
    /// "Kyung-pyo"), by surname ("Deakins"), or by the first name too when it comes first in the
    /// family-name-first way ("Hong Kyung-pyo").
    public static func namesFilm(_ paragraphs: [String], cinematographers: [String], directors: [String] = [], year: Int?) -> Bool {
        let text = " " + fold(paragraphs.joined(separator: " ")) + " "
        func named(_ people: [String]) -> Bool {
            people.contains { person in
                // Each written word of the name, folded ("Kyung-pyo" → "kyung pyo"), without "Jr.".
                let words = person.split(separator: " ").map { fold(String($0)) }
                    .filter { !$0.isEmpty && !["jr", "sr", "ii", "iii", "iv"].contains($0) }
                guard let last = words.last else { return false }
                var names = [words.joined(separator: " "), last]
                // "Hong Kyung-pyo": the family name first.
                if words.count == 2, last.contains(" ") { names.append(words[0]) }
                return names.contains { $0.count >= 3 && text.contains(" " + $0 + " ") }
            }
        }
        if !cinematographers.isEmpty { return named(cinematographers) }
        guard let year, named(directors) else { return false }
        // Its year, or the one either side (a festival the year before, a release the year after).
        return ((year - 1)...(year + 1)).contains { text.contains(" \($0) ") }
    }

    /// Lowercase, no accents, words only: "Łukasz Żal" → "lukasz zal", "Kyung-Pyo" → "kyung pyo".
    static func fold(_ text: String) -> String {
        let plain = text.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "ø", with: "o").replacingOccurrences(of: "ß", with: "ss")
        return plain.split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    /// Whether an American Cinematographer search result is about this film: its title names the
    /// film ("Universal Translator: Arrival"), or its address does ("arrival-cinematography-…").
    public static func isAbout(title: String, articleTitle: String, url: String) -> Bool {
        let film = TitleSimilarity.normalize(title)
        guard !film.isEmpty else { return false }
        let heading = " " + TitleSimilarity.normalize(HTMLText.plain(articleTitle)) + " "
        if heading.contains(" " + film + " ") { return true }
        let slug = film.replacingOccurrences(of: " ", with: "-")
        let path = (URL(string: url)?.path ?? "").lowercased()
        // A one-word title must lead the address ("/article/arrival-…"), not just appear in it.
        if !film.contains(" ") { return path.range(of: "/" + slug + "-", options: .literal) != nil }
        return path.contains(slug)
    }
}

/// Plain text from a web page: its title and paragraphs, no markup.
public enum HTMLText {
    /// The page's own title (the Open Graph one when there is one, without the site's name).
    public static func title(_ html: String) -> String? {
        let candidates = [
            #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']"#,
            #"<title[^>]*>([\s\S]*?)</title>"#,
        ]
        for pattern in candidates {
            if let found = first(pattern, in: html) {
                var text = plain(found)
                // "The Look of Arrival | American Cinematographer" → "The Look of Arrival"
                if let cut = text.range(of: #"\s+[|–—]\s+[^|–—]+$"#, options: .regularExpression) { text = String(text[..<cut.lowerBound]) }
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    /// The page's paragraphs (`<p>`), long enough to be prose, with no markup.
    public static func paragraphs(_ html: String) -> [String] {
        // Scripts, styles, menus and footers hold no article text.
        var body = html
        for tag in ["script", "style", "noscript", "nav", "footer", "aside", "figcaption"] {
            body = body.replacingOccurrences(of: "<\(tag)\\b[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        guard let regex = try? NSRegularExpression(pattern: #"<p\b[^>]*>([\s\S]*?)</p>"#, options: [.caseInsensitive]) else { return [] }
        var seen = Set<String>()
        return regex.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: body) else { return nil }
            let text = plain(String(body[range]))
            guard text.count >= 60, text.contains(" "), seen.insert(text).inserted else { return nil }
            // Newsletter boxes, credits lines and cookie notices.
            let lower = text.lowercased()
            if ["subscribe", "newsletter", "cookie", "all rights reserved", "sign up", "log in", "advertisement"].contains(where: lower.contains),
               text.count < 220 { return nil }
            return text
        }
    }

    /// Markup taken out, entities decoded, spaces tidied.
    public static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = decodeEntities(text)
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static let named: [String: String] = [
        "amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " ", "rsquo": "’", "lsquo": "‘",
        "rdquo": "”", "ldquo": "“", "ndash": "–", "mdash": "—", "hellip": "…", "eacute": "é", "egrave": "è",
        "aacute": "á", "iacute": "í", "oacute": "ó", "uacute": "ú", "ntilde": "ñ", "ouml": "ö", "uuml": "ü", "auml": "ä",
        "ccedil": "ç", "times": "×", "frac12": "½", "frac14": "¼", "deg": "°", "prime": "′", "Prime": "″",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"), let regex = try? NSRegularExpression(pattern: #"&(#x?[0-9a-fA-F]+|[a-zA-Z]+\d*);"#) else { return text }
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let name = Range(match.range(at: 1), in: text) else { continue }
            result += text[last..<whole.lowerBound]
            let entity = String(text[name])
            if entity.hasPrefix("#") {
                let digits = entity.dropFirst()
                let value = digits.hasPrefix("x") || digits.hasPrefix("X") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                result += value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(text[whole])
            } else {
                result += named[entity] ?? String(text[whole])
            }
            last = whole.upperBound
        }
        result += text[last...]
        return result
    }

    private static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

/// Fetches what the Cinematography tab reads. Each part may fail on its own (a site down, a paywall):
/// whatever was read is kept.
public struct CameraSourcesClient: Sendable {
    let session: URLSession

    public init(session: URLSession = CameraSourcesClient.session) {
        self.session = session
    }

    /// Its own connections: a slow magazine site never holds up TMDB or Wikipedia.
    public static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// At most three pages at a time, so a film page never floods anyone.
    static let gate = RequestGate(limit: 3)

    /// - Parameters: `year` and `otherTitles` (the other films of its collection) tell a magazine's
    ///   article about this film from one about another (a remake, a sequel, "Heat" and "Heat Wave"):
    ///   see `CameraSources.namesFilm` and `CameraSources.namesOtherFilm`.
    public func read(articleTitle: String?, filmTitle: String, cinematographers: [String], directors: [String] = [],
                     year: Int? = nil, otherTitles: [String] = []) async -> CameraReading {
        let unanswered = UnansweredSites()
        async let cited = citedLinks(articleTitle: articleTitle, cinematographers: cinematographers)
        async let asc = ascArticles(filmTitle: filmTitle, otherTitles: otherTitles, noting: unanswered)
        async let british = britishCinematographer(filmTitle: filmTitle, otherTitles: otherTitles, noting: unanswered)
        async let stories = storyPages(filmTitle: filmTitle, cinematographers: cinematographers)
        async let person = cinematographer(cinematographers.first, filmTitle: filmTitle)
        // The magazines' own searches first (American Cinematographer's articles are the deepest),
        // then what Wikipedia cites; each page once.
        var links = await asc
        let fromSites = await british
        let fromArticle = await cited
        // Found by searching the magazines for the title (not cited by the film's own article):
        // read only when the page names the film's people or year.
        let searched = Set((links + fromSites).map(\.url)).subtracting(fromArticle.map(\.url))
        for link in fromSites + fromArticle where !links.contains(where: { $0.url.path == link.url.path && $0.url.host == link.url.host }) {
            links.append(link)
        }
        let pages = await withTaskGroup(of: (Int, CameraReading.Source?, CameraReading.Source).self) { group in
            for (index, link) in links.prefix(8).enumerated() {
                group.addTask {
                    let fallback = CameraReading.Source(title: link.title ?? link.site, site: link.site, url: link.url, paragraphs: [])
                    return (index, await page(link.url, site: link.site, title: link.title, noting: unanswered), fallback)
                }
            }
            var results: [(Int, CameraReading.Source?, CameraReading.Source)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }
        }
        // An interview with the editor or the composer isn't read for the camera (still listed).
        // Kodak's and No Film School's stories come after the magazines.
        let storiesRead = await stories
        // Another film's article (same title) isn't read, nor offered as a link.
        let otherFilm = Set(pages.compactMap { $0.1 }.filter {
            searched.contains($0.url) && !CameraSources.namesFilm($0.paragraphs, cinematographers: cinematographers,
                                                                  directors: directors, year: year)
        }.map(\.url))
        let found = pages.compactMap { $0.1 }.filter { !otherFilm.contains($0.url) }
            + storiesRead.filter { story in !pages.contains { $0.2.url.path == story.url.path && $0.2.url.host == story.url.host } }
        let read = Array(found
            .filter { $0.paragraphs.count >= 3 && !CameraSources.isOtherCraft(title: $0.title, cinematographers: cinematographers) }
            .prefix(6))
        let more = pages.filter { page in !read.contains { $0.url == page.2.url } && !otherFilm.contains(page.2.url) }.map { $0.1 ?? $0.2 }
        return CameraReading(sources: read, more: more, cinematographer: await person, unanswered: await unanswered.all())
    }

    /// The external links of the film's Wikipedia article (its references), picked for the craft.
    func citedLinks(articleTitle: String?, cinematographers: [String]) async -> [(url: URL, site: String, title: String?)] {
        struct Response: Decodable {
            struct Query: Decodable {
                struct Page: Decodable {
                    struct Link: Decodable {
                        let url: String?
                        let star: String?
                        enum CodingKeys: String, CodingKey {
                            case url
                            case star = "*"
                        }
                    }
                    let extlinks: [Link]?
                }
                let pages: [String: Page]?
            }
            let query: Query?
        }
        guard let articleTitle, let response: Response = try? await Wikimedia.get("https://en.wikipedia.org/w/api.php", [
            "action": "query", "prop": "extlinks", "titles": articleTitle, "ellimit": "500", "redirects": "1", "format": "json",
        ], session: session) else { return [] }
        let links = (response.query?.pages?.values.first?.extlinks ?? []).compactMap { $0.url ?? $0.star }
        return CameraSources.pick(links, cinematographers: cinematographers).map { ($0.url, $0.site, nil) }
    }

    /// American Cinematographer's articles about the film (its site has a free WordPress API).
    func ascArticles(filmTitle: String, otherTitles: [String] = [], noting: UnansweredSites? = nil) async -> [(url: URL, site: String, title: String?)] {
        struct Hit: Decodable {
            let title: String
            let url: String
            let subtype: String?
        }
        // The site's own search, most relevant first, over everything it publishes: the magazine's
        // articles, and the posts and news where its interviews also appear ("Roger Deakins, ASC,
        // BSC: Lighting Sicario" is a post). Not its pages or videos, which have little to read.
        var components = URLComponents(string: "https://theasc.com/wp-json/wp/v2/search")!
        components.queryItems = [URLQueryItem(name: "search", value: filmTitle), URLQueryItem(name: "per_page", value: "20")]
        guard let url = components.url,
              let data = await fetch(url, accept: "application/json", site: "American Cinematographer", noting: noting, search: true),
              let hits = try? JSONDecoder().decode([Hit].self, from: data) else { return [] }
        return CameraSources.about(filmTitle, in: hits.filter { ["article", "post", "news"].contains($0.subtype ?? "") }
            .map { (title: $0.title, link: $0.url) }, site: "American Cinematographer", limit: 3, otherTitles: otherTitles)
    }

    /// British Cinematographer's articles about the film (its site has a free WordPress API).
    func britishCinematographer(filmTitle: String, otherTitles: [String] = [], noting: UnansweredSites? = nil) async -> [(url: URL, site: String, title: String?)] {
        struct Hit: Decodable {
            struct Rendered: Decodable { let rendered: String }
            let title: Rendered
            let link: String
        }
        // Most relevant first (by date, the newest posts that merely mention the title came first).
        var components = URLComponents(string: "https://britishcinematographer.co.uk/wp-json/wp/v2/posts")!
        components.queryItems = [URLQueryItem(name: "search", value: filmTitle), URLQueryItem(name: "per_page", value: "20"),
                                 URLQueryItem(name: "orderby", value: "relevance"), URLQueryItem(name: "_fields", value: "title,link")]
        guard let url = components.url,
              let data = await fetch(url, accept: "application/json", site: "British Cinematographer", noting: noting, search: true),
              let hits = try? JSONDecoder().decode([Hit].self, from: data) else { return [] }
        return CameraSources.about(filmTitle, in: hits.map { (title: $0.title.rendered, link: $0.link) },
                                   site: "British Cinematographer", limit: 2, otherTitles: otherTitles)
    }

    /// Kodak's stories of films shot on its stock and No Film School's pieces on a film's
    /// cinematography, at the addresses those sites give them ("kodak.com/en/motion/blog-post/
    /// the-brutalist", "nofilmschool.com/dune-cinematography"). A page is kept only when it names
    /// the cinematographer (the same title may be another film).
    func storyPages(filmTitle: String, cinematographers: [String]) async -> [CameraReading.Source] {
        let surnames = cinematographers.compactMap { $0.split(separator: " ").last.map(String.init) }.filter { $0.count >= 3 }
        let slug = CameraSources.slug(filmTitle)
        guard !slug.isEmpty, !surnames.isEmpty else { return [] }
        let guesses: [(String, String)] = [
            ("https://www.kodak.com/en/motion/blog-post/\(slug)/", "Kodak"),
            ("https://www.kodak.com/en/motion/page/\(slug)/", "Kodak"),
            ("https://nofilmschool.com/\(slug)-cinematography", "No Film School"),
        ]
        return await withTaskGroup(of: (Int, CameraReading.Source?).self) { group in
            for (index, guess) in guesses.enumerated() {
                group.addTask {
                    guard let url = URL(string: guess.0), let found = await page(url, site: guess.1, title: nil),
                          found.paragraphs.contains(where: { paragraph in surnames.contains { paragraph.contains($0) } }) else { return (index, nil) }
                    return (index, found)
                }
            }
            var results: [(Int, CameraReading.Source?)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
        }
    }

    /// One page's title and paragraphs; nil when it can't be read.
    func page(_ url: URL, site: String, title: String?, noting: UnansweredSites? = nil) async -> CameraReading.Source? {
        guard let data = await fetch(url, accept: "text/html", site: site, noting: noting),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let paragraphs = HTMLText.paragraphs(html)
        return CameraReading.Source(title: title ?? HTMLText.title(html) ?? site, site: site, url: url, paragraphs: paragraphs)
    }

    /// The cinematographer's Wikipedia article: its opening and the paragraphs naming the film.
    func cinematographer(_ name: String?, filmTitle: String) async -> CameraReading.Cinematographer? {
        guard let name, let text = try? await WikipediaClient(session: session).extract(title: name), !text.isEmpty else { return nil }
        let paragraphs = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 40 && !$0.hasPrefix("=") }
        guard let lead = paragraphs.first else { return nil }
        // The right person: a cinematographer, not someone else of the same name.
        let opening = lead.lowercased()
        guard ["cinematographer", "director of photography", "photographer", "filmmaker"].contains(where: opening.contains) else { return nil }
        let about = paragraphs.dropFirst().filter { $0.localizedCaseInsensitiveContains(filmTitle) }
        let encoded = name.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "https://en.wikipedia.org/wiki/\(encoded)") else { return nil }
        return CameraReading.Cinematographer(name: name, lead: Digest.lead(of: [lead], limit: 360), aboutThisFilm: Array(about.prefix(4)), url: url)
    }

    /// Spaces the requests to each site and pauses a site that asks Reel to wait.
    static let pacer = HostPacer()

    /// The page, or nil. A site that asks Reel to wait (a captcha page, "too many requests",
    /// "accepted" with nothing in it) is paused for a while and noted, so the film is read again
    /// later rather than kept as if nothing were written about it; so is a magazine's search that
    /// doesn't answer (`search`). A page that's gone or paywalled is just not read.
    private func fetch(_ url: URL, accept: String, site: String = "", noting: UnansweredSites? = nil, search: Bool = false) async -> Data? {
        let host = url.host ?? ""
        if await Self.pacer.isPaused(host) {
            await noting?.add(site)
            return nil
        }
        await Self.pacer.turn(host)
        var request = URLRequest(url: url)
        // Reel says who it is; a site that turns it away is only linked.
        request.setValue(Wikimedia.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        await Self.gate.acquire()
        let result: (Data, Int)? = await withCheckedContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                guard error == nil, let data else { return continuation.resume(returning: nil) }
                continuation.resume(returning: (data, (response as? HTTPURLResponse)?.statusCode ?? 0))
            }.resume()
        }
        await Self.gate.release()
        guard let (data, status) = result else {
            if search { await noting?.add(site) }
            return nil
        }
        if status == 429 || status == 202 || CameraSources.isChallenge(data) {
            await Self.pacer.pause(host)
            await noting?.add(site)
            return nil
        }
        if status >= 500 {
            if search { await noting?.add(site) }
            return nil
        }
        guard (200..<300).contains(status), data.count < 6_000_000 else { return nil }
        return data
    }
}
