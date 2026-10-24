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
        /// The address read: HTTPS, even when it was cited as plain HTTP (see `cited`).
        public let url: URL
        public let paragraphs: [String]
        /// The address as cited, when it wasn't the one read ("http://…" read as "https://…").
        public var cited: URL? = nil
        /// Where the site sent Reel, when it redirected.
        public var landed: URL? = nil
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

    /// A page found but not read, and why (for the reading log).
    public struct Skipped: Equatable, Sendable {
        public let source: Source
        public let reason: String
        /// Why it couldn't be examined, when that's what kept it from being read (not when it was
        /// another film's, about another craft, or one more than was read).
        public var limit: CraftIndex.SourceLimit.Kind? = nil

        public init(source: Source, reason: String, limit: CraftIndex.SourceLimit.Kind? = nil) {
            self.source = source
            self.reason = reason
            self.limit = limit
        }
    }

    public var skipped: [Skipped] = []

    public init(sources: [Source], more: [Source], cinematographer: Cinematographer?, unanswered: [String] = [], skipped: [Skipped] = []) {
        self.sources = sources
        self.more = more
        self.cinematographer = cinematographer
        self.unanswered = unanswered
        self.skipped = skipped
    }

    /// Everything to read for `TechSpecs`, interviews first (the filmmakers' own words).
    public func texts(hiding spoilers: Bool) -> [TechSpecs.Text] {
        func safe(_ paragraphs: [String]) -> [String] {
            spoilers ? paragraphs.filter { !Spoilers.mentionsPlot($0) } : paragraphs
        }
        var texts = sources.map {
            TechSpecs.Text(source: $0.site, paragraphs: safe($0.paragraphs), isList: CameraSources.isListPage(title: $0.title, url: $0.url))
        }
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

/// Requests to each site start a second apart (at most three at once in all), and a site that
/// asked Reel to wait is left alone for twenty minutes: magazines answer a library read slowly.
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

/// Why a page or a search wasn't read. Only `unanswered` and `wait` leave the film's reading
/// incomplete (read again automatically, see `CraftIndex.merge`): a page that's gone, or that the
/// site refuses to Reel (a paywall, a sign-in, "access denied"), is read again only when the film is
/// (new rules, or half a year on).
public enum SourceFailure: Equatable, Sendable {
    /// Not there: 404, 410, another 4xx, a bad address, or moved to the site's front page.
    case gone(String)
    /// There, but not for Reel: 401, 402, 403 without a challenge, 451, too large, or only over
    /// plain HTTP.
    case restricted(String)
    /// Didn't come: timed out, the connection dropped, the address not found, a failed secure
    /// connection, a server error, or an answer in place of a search's: nothing is known.
    case unanswered(String)
    /// Asked Reel to wait: "too many requests", a captcha or a challenge page. The site is left
    /// alone for a while (see `HostPacer`).
    case wait(String)

    public var retried: Bool {
        switch self {
        case .unanswered, .wait: true
        case .gone, .restricted: false
        }
    }

    /// As kept with the reading.
    public var limit: CraftIndex.SourceLimit.Kind {
        switch self {
        case .gone: .gone
        case .restricted: .restricted
        case .unanswered, .wait: .unanswered
        }
    }

    /// For the reading log.
    public var reason: String {
        switch self {
        case .gone(let why): "gone: \(why)"
        case .restricted(let why): "not open to Reel: \(why)"
        case .unanswered(let why): "didn't answer: \(why) (read again later)"
        case .wait(let why): "asked Reel to wait: \(why) (read again later)"
        }
    }

    /// What an HTTP answer means. `requested` and `landed`: the address asked for and where the
    /// site's redirects ended. `page`: a web page asked for (a search answered by the site's front
    /// page isn't "gone": it fails as a search, and the site counts as not answering).
    public static func of(status: Int, data: Data, requested: URL, landed: URL?, page: Bool = true) -> SourceFailure? {
        if status == 429 { return .wait("too many requests (429)") }
        if status == 202 || ([403, 503].contains(status) && CameraSources.isChallenge(data)) { return .wait("a challenge page in place of the page") }
        if status >= 500 { return .unanswered("the server failed (\(status))") }
        // A request that took too long, came too early, or a proxy on Reel's own side.
        if [407, 408, 425].contains(status) { return .unanswered("not answered in time (\(status))") }
        if [401, 402, 403, 451].contains(status) { return .restricted("refused (\(status)): a sign-in, a paywall or access denied") }
        // Said as seen: not found where Reel asked (over HTTPS), not that it's nowhere.
        if [404, 410].contains(status) { return .gone("not found\(requested.scheme == "https" ? " over HTTPS" : "") (\(status))") }
        if (400..<500).contains(status) { return .gone("not available (\(status))") }
        guard (200..<300).contains(status) else { return .unanswered("an unexpected answer (\(status))") }
        if data.count >= 6_000_000 { return .restricted("too large to read") }
        if page, let landed, CameraSources.isFrontPage(landed, for: requested) { return .gone("moved to the site's front page") }
        return nil
    }

    /// What a request that didn't get an answer means (`URLError` codes, the same on Linux).
    /// `upgraded`: asked for over HTTPS though cited as plain HTTP, when a failed secure connection
    /// or no connection means the site has no HTTPS.
    public static func of(error: Error, upgraded: Bool = false) -> SourceFailure {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return .unanswered("no answer") }
        switch error.code {
        case -1022: return .restricted("only over plain HTTP, which Reel doesn't load")
        case -1000, -1002, -1010: return .gone("not a web address Reel can read")
        case -1013: return .restricted("a sign-in")
        case -1007: return .restricted("its redirects go round in a loop")
        case -1201, -1202, -1203, -1204: return .restricted("its certificate isn't valid")
        case -1004 where upgraded, -1200 where upgraded, -1205 where upgraded, -1206 where upgraded:
            return .restricted("only over plain HTTP, which Reel doesn't load")
        case -1001: return .unanswered("timed out")
        case -1003, -1006: return .unanswered("the site's address wasn't found")
        case -1004: return .unanswered("couldn't connect")
        case -1005: return .unanswered("the connection dropped")
        case -1009: return .unanswered("offline")
        case -1200, -1205, -1206: return .unanswered("the secure connection failed")
        default: return .unanswered("no answer")
        }
    }
}

public enum CameraSources {
    /// The same page over HTTPS: a link cited as "http://…" (as Wikipedia keeps older references) is
    /// read as "https://…", the same host, path and query. macOS doesn't load plain HTTP, and Reel
    /// doesn't ask it to. Already HTTPS, or not a web address: as it is.
    public static func secure(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.scheme = "https"
        if parts.port == 80 { parts.port = nil }
        return parts.url ?? url
    }

    /// What makes two addresses the same page: the host without "www.", the path without its
    /// trailing "/" and the query without tracking tags, whatever the scheme.
    public static func identity(_ url: URL) -> String {
        var host = (url.host ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let query = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .filter { item in
                let name = item.name.lowercased()
                return !trackingTags.contains(name) && !["utm_", "mc_", "_ga"].contains(where: name.hasPrefix)
            }
            .map { $0.name + "=" + ($0.value ?? "") }
            .sorted()
        return host + "/" + path + (query.isEmpty ? "" : "?" + query.joined(separator: "&"))
    }

    /// Query items that only say where a link was shared from.
    static let trackingTags: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "ref", "src", "amp", "igshid", "cmpid", "ito"]

    /// Why a page found and not read wasn't examined, when that's why: it didn't load (`failure`), or
    /// it loaded with too little text to read (fewer than three paragraphs: a teaser, a page built by
    /// script, a sign-in wall). That page is kept as a limit, not retried: reading it again soon would
    /// bring the same page. A page that was read, another film's, or one more than was read: nil.
    public static func limit(page: CameraReading.Source?, failure: SourceFailure?, otherFilm: Bool) -> CraftIndex.SourceLimit.Kind? {
        guard let page else { return failure?.limit ?? .unknown }
        return !otherFilm && page.paragraphs.count < 3 ? .thin : nil
    }

    /// A page asked for by its own address that ends on the site's front page: what it was is gone.
    public static func isFrontPage(_ landed: URL, for requested: URL) -> Bool {
        let asked = requested.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let ended = landed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return !asked.isEmpty && (ended.isEmpty || ["index.php", "index.html", "index.htm", "home", "en"].contains(ended))
            && (landed.query ?? "").isEmpty
    }

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
    /// Each is read over HTTPS (see `secure`), and the same page cited twice ("http://www…" and
    /// "https://…") once; `cited` is the address as cited when it isn't the one read.
    public static func pick(_ links: [String], cinematographers: [String], limit: Int = 8) -> [(url: URL, site: String, cited: URL?)] {
        let surnames = cinematographers.compactMap { $0.split(separator: " ").last.map { $0.lowercased() } }
            .filter { $0.count >= 3 }
        var seen = Set<String>()
        var picked: [(url: URL, site: String, cited: URL?, rank: Int)] = []
        for (index, link) in links.enumerated() {
            guard let given = URL(string: link), let scheme = given.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = given.host?.lowercased() else { continue }
            let url = secure(given)
            let path = url.path.lowercased()
            // Front pages, tags and searches aren't articles.
            guard path.count > 8, !path.contains("/tag/"), !path.contains("/search"), !path.contains("/category/") else { continue }
            guard seen.insert(identity(url)).inserted else { continue }
            let cited = url == given ? nil : given
            let namesThem = surnames.contains { path.contains($0) }
            if let site = craftSites.first(where: { host == $0.host || host.hasSuffix("." + $0.host) }) {
                picked.append((url, site.name, cited, (namesThem ? 0 : 100) + index))
            } else if let site = newsSites.first(where: { host == $0.host || host.hasSuffix("." + $0.host) }),
                      namesThem || craftWords.contains(where: { path.contains($0) }) {
                picked.append((url, site.name, cited, (namesThem ? 200 : 300) + index))
            }
        }
        return picked.sorted { $0.rank < $1.rank }.prefix(limit).map { ($0.url, $0.site, $0.cited) }
    }

    /// A title as sites write it in their addresses: "The Brutalist" → "the-brutalist",
    /// "Amélie" → "amelie".
    /// A page about many films, by its title or address: "The Best Films of 2024", "Top 10 …",
    /// "Our favourite films of the year", "Sundance round-up", a critics' poll.
    public static func isListPage(title: String, url: URL) -> Bool {
        let slug = url.path.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return [title, slug].contains { listWords.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
    }

    static let listWords = try! NSRegularExpression(
        pattern: #"\b(?:(?:best|favou?rite|greatest|top)\s+(?:\d+\s+)?(?:films|movies|features|documentaries|of\s+(?:the\s+year|20\d\d|19\d\d|the\s+decade))|(?:top|best)\s+\d+|\d+\s+(?:best|greatest|favou?rite)|films\s+of\s+(?:the\s+year|20\d\d|19\d\d)|year[\s-]end|year\s+in\s+review|round[\s-]?up|critics['’]?\s+poll)\b"#,
        options: [.caseInsensitive])

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
            guard let link = URL(string: hit.link).map(secure), !found.contains(where: { identity($0.url) == identity(link) }) else { continue }
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
        // then what Wikipedia cites; each page once, however its address is written.
        var links = (await asc).map { (url: $0.url, site: $0.site, title: $0.title, cited: URL?.none) }
        let fromSites = (await british).map { (url: $0.url, site: $0.site, title: $0.title, cited: URL?.none) }
        let fromArticle = await cited
        // Found by searching the magazines for the title (not cited by the film's own article):
        // read only when the page names the film's people or year.
        let searched = Set((links + fromSites).map { CameraSources.identity($0.url) })
            .subtracting(fromArticle.map { CameraSources.identity($0.url) })
        for link in fromSites + fromArticle where !links.contains(where: { CameraSources.identity($0.url) == CameraSources.identity(link.url) }) {
            links.append(link)
        }
        let pages = await withTaskGroup(of: (Int, CameraReading.Source?, CameraReading.Source, SourceFailure?).self) { group in
            for (index, link) in links.prefix(8).enumerated() {
                group.addTask {
                    var fallback = CameraReading.Source(title: link.title ?? link.site, site: link.site, url: link.url, paragraphs: [])
                    fallback.cited = link.cited
                    var got = await page(link.url, site: link.site, title: link.title, noting: unanswered)
                    got.source?.cited = link.cited
                    return (index, got.source, fallback, got.failure)
                }
            }
            var results: [(Int, CameraReading.Source?, CameraReading.Source, SourceFailure?)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }
        }
        // An interview with the editor or the composer isn't read for the camera (still listed).
        // Kodak's and No Film School's stories come after the magazines.
        let storiesRead = await stories
        // Another film's article (same title) isn't read, nor offered as a link.
        let otherFilm = Set(pages.compactMap { $0.1 }.filter {
            searched.contains(CameraSources.identity($0.url)) && !CameraSources.namesFilm($0.paragraphs, cinematographers: cinematographers,
                                                                                          directors: directors, year: year)
        }.map(\.url))
        let found = pages.compactMap { $0.1 }.filter { !otherFilm.contains($0.url) }
            + storiesRead.filter { story in !pages.contains { CameraSources.identity($0.2.url) == CameraSources.identity(story.url) } }
        let readable = found.filter { $0.paragraphs.count >= 3 && !CameraSources.isOtherCraft(title: $0.title, cinematographers: cinematographers) }
        let read = Array(readable.prefix(6))
        let more = pages.filter { page in !read.contains { $0.url == page.2.url } && !otherFilm.contains(page.2.url) }.map { $0.1 ?? $0.2 }
        // Why each page found wasn't read.
        func reason(_ page: CameraReading.Source) -> String {
            if otherFilm.contains(page.url) { return "another film of that title: it doesn't name the film's cinematographer, director or year" }
            if page.paragraphs.count < 3 { return "too little text to read" }
            if CameraSources.isOtherCraft(title: page.title, cinematographers: cinematographers) {
                return "an interview about another craft (editing, music, design)"
            }
            return "six sources were already read"
        }
        var skipped: [CameraReading.Skipped] = []
        for (_, page, fallback, failure) in pages where !read.contains(where: { $0.url == fallback.url }) {
            let limit = CameraSources.limit(page: page, failure: failure, otherFilm: page.map { otherFilm.contains($0.url) } ?? false)
            skipped.append(CameraReading.Skipped(source: page ?? fallback,
                                                 reason: page.map(reason) ?? failure?.reason ?? "couldn't be read", limit: limit))
        }
        for story in storiesRead where !read.contains(where: { $0.url == story.url })
            && !pages.contains(where: { CameraSources.identity($0.2.url) == CameraSources.identity(story.url) }) {
            skipped.append(CameraReading.Skipped(source: story, reason: found.contains { $0.url == story.url } ? reason(story) : "the same page as one already found"))
        }
        return CameraReading(sources: read, more: more, cinematographer: await person, unanswered: await unanswered.all(), skipped: skipped)
    }

    /// The external links of the film's Wikipedia article (its references), picked for the craft.
    func citedLinks(articleTitle: String?, cinematographers: [String]) async -> [(url: URL, site: String, title: String?, cited: URL?)] {
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
        return CameraSources.pick(links, cinematographers: cinematographers).map { ($0.url, $0.site, nil, $0.cited) }
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
              case .page(let data, _) = await fetch(url, accept: "application/json", site: "American Cinematographer", noting: noting)
        else { return [] }
        // An answer that isn't the search's (a page in its place): not "nothing written", read again later.
        guard let hits = try? JSONDecoder().decode([Hit].self, from: data) else {
            await noting?.add("American Cinematographer")
            return []
        }
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
              case .page(let data, _) = await fetch(url, accept: "application/json", site: "British Cinematographer", noting: noting)
        else { return [] }
        guard let hits = try? JSONDecoder().decode([Hit].self, from: data) else {
            await noting?.add("British Cinematographer")
            return []
        }
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
                    guard let url = URL(string: guess.0), let found = await page(url, site: guess.1, title: nil).source,
                          found.paragraphs.contains(where: { paragraph in surnames.contains { paragraph.contains($0) } }) else { return (index, nil) }
                    return (index, found)
                }
            }
            var results: [(Int, CameraReading.Source?)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
        }
    }

    /// One page's title and paragraphs, or why it couldn't be read. Asked for over HTTPS.
    func page(_ url: URL, site: String, title: String?, noting: UnansweredSites? = nil) async
        -> (source: CameraReading.Source?, failure: SourceFailure?) {
        switch await fetch(CameraSources.secure(url), accept: "text/html", site: site, noting: noting, upgraded: url.scheme == "http") {
        case .failed(let failure):
            return (nil, failure)
        case .page(let data, let landed):
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return (nil, .gone("not a readable page"))
            }
            var source = CameraReading.Source(title: title ?? HTMLText.title(html) ?? site, site: site, url: CameraSources.secure(url),
                                              paragraphs: HTMLText.paragraphs(html))
            source.landed = landed
            return (source, nil)
        }
    }

    /// What a request brought: the page (and where a redirect ended, when it did), or why not.
    enum Fetched: Sendable {
        case page(Data, landed: URL?)
        case failed(SourceFailure)
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

    /// The page, or why not (see `SourceFailure`). A site that asks Reel to wait (a captcha page,
    /// "too many requests", "accepted" with nothing in it) is paused for a while; it, and a site that
    /// didn't answer (offline, timed out, failing), is noted, so the film is read again later rather
    /// than kept as if nothing were written about it. A page that's gone, or refused to Reel, is just
    /// not read.
    func fetch(_ url: URL, accept: String, site: String = "", noting: UnansweredSites? = nil, upgraded: Bool = false) async -> Fetched {
        let host = url.host ?? ""
        var request = URLRequest(url: url)
        // Reel says who it is; a site that turns it away is only linked.
        request.setValue(Wikimedia.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        await Self.gate.acquire()
        // Checked once it's this request's turn: a pause that came while it waited holds it too.
        if await Self.pacer.isPaused(host) {
            await Self.gate.release()
            await noting?.add(site)
            return .failed(.wait("asked Reel to wait a little earlier"))
        }
        await Self.pacer.turn(host)
        let result: Result<(Data, Int, URL?), Error> = await withCheckedContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error { return continuation.resume(returning: .failure(error)) }
                let http = response as? HTTPURLResponse
                continuation.resume(returning: .success((data ?? Data(), http?.statusCode ?? 0, http?.url)))
            }.resume()
        }
        await Self.gate.release()
        let why: SourceFailure
        switch result {
        case .failure(let error):
            why = .of(error: error, upgraded: upgraded)
        case .success(let (data, status, final)):
            // Where the site's redirects ended, when that isn't where Reel asked.
            let landed = final.flatMap { CameraSources.identity($0) == CameraSources.identity(url) ? nil : $0 }
            guard let failure = SourceFailure.of(status: status, data: data, requested: url, landed: landed,
                                                 page: accept.hasPrefix("text/html")) else {
                return .page(data, landed: landed)
            }
            why = failure
        }
        if case .wait = why { await Self.pacer.pause(host) }
        if why.retried { await noting?.add(site) }
        return .failed(why)
    }
}
