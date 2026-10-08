import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where the Camera tab reads beyond the film's Wikipedia article: the interviews and craft
/// articles the article cites (American Cinematographer, British Cinematographer, IndieWire's
/// craft pieces, Kodak, ARRI…), American Cinematographer's own articles about the film, and the
/// cinematographer's Wikipedia article. All free to read; only paragraphs are kept, in memory.
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

    public init(sources: [Source], more: [Source], cinematographer: Cinematographer?) {
        self.sources = sources
        self.more = more
        self.cinematographer = cinematographer
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

public enum CameraSources {
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
    /// News sites cited for many things: only their pieces about the shooting count.
    static let newsSites: [(host: String, name: String)] = [
        ("indiewire.com", "IndieWire"), ("variety.com", "Variety"), ("hollywoodreporter.com", "The Hollywood Reporter"),
        ("deadline.com", "Deadline"), ("vanityfair.com", "Vanity Fair"), ("vulture.com", "Vulture"),
        ("theguardian.com", "The Guardian"), ("nytimes.com", "The New York Times"), ("collider.com", "Collider"),
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
        for tag in ["script", "style", "noscript", "nav", "footer", "header", "aside", "form", "figcaption"] {
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

/// Fetches what the Camera tab reads. Each part may fail on its own (a site down, a paywall):
/// whatever was read is kept.
public struct CameraSourcesClient: Sendable {
    let session: URLSession

    public init(session: URLSession = TMDBClient.sharedSession) {
        self.session = session
    }

    /// At most three pages at a time, so a film page never floods anyone.
    static let gate = RequestGate(limit: 3)

    public func read(articleTitle: String?, filmTitle: String, cinematographers: [String]) async -> CameraReading {
        async let cited = citedLinks(articleTitle: articleTitle, cinematographers: cinematographers)
        async let asc = ascArticles(filmTitle: filmTitle)
        async let person = cinematographer(cinematographers.first, filmTitle: filmTitle)
        // American Cinematographer's own search first (its articles are the deepest), then what
        // Wikipedia cites; each page once.
        var links = await asc
        for link in await cited where !links.contains(where: { $0.url.path == link.url.path && $0.url.host == link.url.host }) {
            links.append(link)
        }
        let pages = await withTaskGroup(of: (Int, CameraReading.Source?, CameraReading.Source).self) { group in
            for (index, link) in links.prefix(8).enumerated() {
                group.addTask {
                    let fallback = CameraReading.Source(title: link.title ?? link.site, site: link.site, url: link.url, paragraphs: [])
                    return (index, await page(link.url, site: link.site, title: link.title), fallback)
                }
            }
            var results: [(Int, CameraReading.Source?, CameraReading.Source)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }
        }
        let read = pages.compactMap { $0.1 }.filter { $0.paragraphs.count >= 3 }
        let more = pages.filter { page in !read.contains { $0.url == page.2.url } }.map { $0.1 ?? $0.2 }
        return CameraReading(sources: Array(read.prefix(5)), more: more, cinematographer: await person)
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
    func ascArticles(filmTitle: String) async -> [(url: URL, site: String, title: String?)] {
        struct Hit: Decodable {
            struct Rendered: Decodable { let rendered: String }
            let title: Rendered
            let link: String
        }
        var found: [(url: URL, site: String, title: String?)] = []
        // Magazine articles only: the site's blog posts are about the society, not the films.
        for kind in ["article"] {
            var components = URLComponents(string: "https://theasc.com/wp-json/wp/v2/\(kind)")!
            components.queryItems = [URLQueryItem(name: "search", value: filmTitle), URLQueryItem(name: "per_page", value: "20"),
                                     URLQueryItem(name: "_fields", value: "title,link")]
            guard let url = components.url, let data = await fetch(url, accept: "application/json"),
                  let hits = try? JSONDecoder().decode([Hit].self, from: data) else { continue }
            for hit in hits where CameraSources.isAbout(title: filmTitle, articleTitle: hit.title.rendered, url: hit.link) {
                guard let link = URL(string: hit.link), !found.contains(where: { $0.url == link }) else { continue }
                found.append((link, "American Cinematographer", HTMLText.plain(hit.title.rendered)))
            }
        }
        return Array(found.prefix(3))
    }

    /// One page's title and paragraphs; nil when it can't be read.
    func page(_ url: URL, site: String, title: String?) async -> CameraReading.Source? {
        guard let data = await fetch(url, accept: "text/html"),
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

    private func fetch(_ url: URL, accept: String) async -> Data? {
        var request = URLRequest(url: url)
        // As a browser asks: many magazine sites turn away anything else.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15
        await Self.gate.acquire()
        let result: (Data, Int)? = await withCheckedContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                guard error == nil, let data else { return continuation.resume(returning: nil) }
                continuation.resume(returning: (data, (response as? HTTPURLResponse)?.statusCode ?? 0))
            }.resume()
        }
        await Self.gate.release()
        guard let (data, status) = result, (200..<300).contains(status), data.count < 6_000_000 else { return nil }
        return data
    }
}
