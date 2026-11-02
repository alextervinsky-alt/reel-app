import Foundation

/// The article on a web page, told apart from everything else on it (Reel 1.10.5).
///
/// A magazine page holds much more than its article: the site's menus and footer, a news ticker,
/// "You might also like" cards (each a whole `<article>` with its own excerpt), product teasers,
/// newsletter boxes. Reading every `<p>` on the page (what Reel did up to 1.10.4) let a teaser's
/// sentence ("Sony's new X-OCN format promises Raw image capture…") be read as the article's.
///
/// The article is found by the page's own structure, in this order, and only its paragraphs are
/// read; anything inside it that is another component (a nested `<article>`, an aside, a related or
/// promotional block, a ticker) is left out:
/// 1. the element marked as the article's body (`itemprop="articleBody"`);
/// 2. a publishing system's article container (`entry-content`, `post-content`,
///    `theme-post-content`, `article-body`…);
/// 3. the page's own `<article>` (one not inside another), the one holding the page's headline
///    when there are several; a list of `<article>` entries side by side holding most of the
///    page's prose is a round-up, read as one (`TechSpecs` then reads only this film's entry),
///    and one holding little of it is a row of cards, left out;
/// 4. the page's `<main>`;
/// 5. otherwise the one region that holds most of the page's prose.
///
/// Where the page has prose but no one article can be told apart (two regions of equal weight, two
/// article bodies), nothing is read: the page is reported as not readable (see
/// `CameraSourcesClient.page`), never read whole. Which paragraphs belong to the article is decided
/// here; whether what they say is about this film is decided later (`TechSpecs`).
public enum ArticleReader {
    /// What was read from a page.
    public struct Article: Equatable, Sendable {
        /// The article's paragraphs (prose, credits lines and spec sheets; see `HTMLText.keep`).
        public var paragraphs: [String]
        /// How the article was found; nil when it couldn't be told apart (nothing read).
        public var boundary: Boundary?
        /// Prose paragraphs on the page that were left out as not the article's.
        public var leftOut: Int
        /// The address the page gives for itself (`rel="canonical"`), when it has one.
        public var canonical: URL?

        public var found: Bool { boundary != nil }
    }

    public enum Boundary: String, Equatable, Sendable {
        case articleBody = "the page's article-body mark"
        case container = "the site's article container"
        case article = "the page's article element"
        case entries = "the page's list of entries (a round-up)"
        case main = "the page's main content"
        case region = "the region holding the page's prose"
    }

    /// Tags whose content is never the article's prose.
    static let rawText: Set<String> = ["script", "style", "noscript", "template", "svg", "iframe", "select", "textarea", "button"]
    static let void: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source",
                                    "track", "wbr"]
    /// Tags that end an open paragraph (HTML closes `<p>` before them).
    static let blocks: Set<String> = ["p", "div", "section", "article", "aside", "header", "footer", "nav", "main", "ul", "ol",
                                      "table", "h1", "h2", "h3", "h4", "h5", "h6", "figure", "blockquote", "form", "pre", "dl",
                                      "address", "details", "fieldset", "hr", "menu"]
    /// Components that aren't the article, by their element.
    static let componentTags: Set<String> = ["nav", "aside", "footer", "header", "form", "figcaption", "dialog"]
    /// Components that aren't the article, by a word of their class or id: related and recommended
    /// articles, tickers and carousels of other posts, promotions, advertising, newsletters, sharing
    /// and comments. Whole words of the name ("pp-content-ticker-item", "jp-relatedposts"), not
    /// parts of words. A block so named that holds most of the page's prose is the page's layout
    /// instead (comments excepted).
    static let componentWords: Set<String> = ["related", "relatedposts", "recommended", "recommendation", "recommendations",
                                              "teaser", "teasers", "ticker", "promo", "promos", "promoted", "promotion",
                                              "sponsored", "sponsor", "advert", "advertisement", "advertising", "ads", "newsletter",
                                              "subscribe", "subscription", "outbrain", "taboola", "yarpp", "carousel", "swiper",
                                              "sidebar", "comments", "comment", "share", "sharing", "sharedaddy", "social",
                                              "popular", "trending", "breadcrumb", "breadcrumbs", "readmore", "readnext",
                                              "morefrom", "youmaylike", "youmightlike"]
    /// Components written by readers, never the article however much of the page they fill.
    static let readerWords: Set<String> = ["comments", "comment"]
    /// A publishing system's article container, by (part of) a class name.
    static let containerNames = ["entry-content", "post-content", "post__content", "theme-post-content", "fl-post-content",
                                 "article-body", "article__body", "articlebody", "article-content", "article__content",
                                 "story-body", "post-body", "single-content"]

    struct Element {
        let tag: String
        let classes: [String]
        let id: String
        let itemprop: String
        let parent: Int?
        let start: Int
        var end: Int
    }

    /// The article on the page.
    public static func read(_ html: String) -> Article {
        let (text, elements) = parse(html)
        let canonical = HTMLText.canonical(html)
        // Each paragraph's text, kept or not by itself (prose, a credits line, a spec sheet).
        let paragraphIndices = elements.indices.filter { elements[$0].tag == "p" }
        func content(_ i: Int) -> String {
            HTMLText.plain(text.substring(with: NSRange(location: elements[i].start, length: max(0, elements[i].end - elements[i].start))))
        }
        let texts = Dictionary(uniqueKeysWithValues: paragraphIndices.map { ($0, content($0)) })
        func isProse(_ i: Int) -> Bool { HTMLText.counts(texts[i] ?? "") }
        func ancestors(_ i: Int) -> [Int] {
            var chain: [Int] = []
            var next = elements[i].parent
            while let j = next { chain.append(j); next = elements[j].parent }
            return chain
        }
        let headline = elements.indices.first { elements[$0].tag == "h1" }
        let headlineAncestors = Set(headline.map { ancestors($0) } ?? [])
        // An element that isn't the article: a component by its tag or name (unless it holds the
        // page's headline: a wrapper "has-sidebar" around the article), or an article inside another.
        // Cards found to be a row of other articles' teasers (see below).
        var cards = Set<Int>()
        // How much prose each element holds, components or not. A block named like a component
        // that holds most of the page's prose is the page's layout, not a component beside the
        // article (IndieWire's galleries sit in a "_sidebar_…" column); comments are never the article.
        let allProse = paragraphIndices.filter(isProse)
        var proseWeight: [Int: Int] = [:]
        for i in allProse { for j in ancestors(i) { proseWeight[j, default: 0] += texts[i]?.count ?? 0 } }
        let pageWeight = allProse.reduce(0) { $0 + (texts[$1]?.count ?? 0) }
        func isComponent(_ j: Int) -> Bool {
            let element = elements[j]
            if cards.contains(j) { return true }
            if element.tag == "html" || element.tag == "body" || headlineAncestors.contains(j) { return false }
            if componentTags.contains(element.tag) { return true }
            if element.tag == "article", ancestors(j).contains(where: { elements[$0].tag == "article" }) { return true }
            let words = (element.classes + [element.id]).flatMap { name in
                name.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map(String.init)
            }
            guard words.contains(where: componentWords.contains) else { return false }
            if words.contains(where: readerWords.contains) { return true }
            return 2 * (proseWeight[j] ?? 0) < pageWeight
        }
        // Prose paragraphs not inside any component.
        var open = paragraphIndices.filter { i in isProse(i) && !ancestors(i).contains(where: isComponent) }
        let leftOutOnPage = allProse.count
        // Nothing on the page reads as prose: an empty article (too little text), not a failure.
        guard !open.isEmpty else {
            return Article(paragraphs: [], boundary: .region, leftOut: leftOutOnPage, canonical: canonical)
        }
        // A container's paragraphs: inside it, and not inside a component within it.
        func paragraphs(in container: Int?) -> [Int] {
            open.filter { i in container.map { ancestors(i).contains($0) } ?? true }
        }
        func weight(_ indices: [Int]) -> Int { indices.reduce(0) { $0 + (texts[$1]?.count ?? 0) } }
        func done(_ container: Int?, _ boundary: Boundary) -> Article {
            let chosen = paragraphs(in: container)
            let kept = HTMLText.keep(chosen.compactMap { texts[$0] })
            return Article(paragraphs: kept, boundary: boundary, leftOut: leftOutOnPage - chosen.count, canonical: canonical)
        }
        let unbounded = Article(paragraphs: [], boundary: nil, leftOut: leftOutOnPage, canonical: canonical)
        /// Three or more of the page's own articles holding prose, none with the headline, in one
        /// list: each in an item of the same element, or directly in the same element.
        func entryList(_ articles: [Int]) -> (container: Int?, entries: [Int])? {
            let top = articles.filter { j in !ancestors(j).contains { elements[$0].tag == "article" } && !paragraphs(in: j).isEmpty }
            guard top.count >= 3, !top.contains(where: headlineAncestors.contains) else { return nil }
            func holder(_ j: Int) -> Int? {
                guard let parent = elements[j].parent else { return nil }
                return elements[parent].tag == "li" ? elements[parent].parent : parent
            }
            let holders = Set(top.map(holder))
            guard holders.count == 1, let container = holders.first else { return nil }
            return (container, top)
        }
        /// One of the candidates, when it's clear which: the outermost ones holding prose, one alone,
        /// the one holding the headline, or one with at least twice the prose of any other. Nil:
        /// none; `.some(nil)`: more than one and no telling (ambiguous).
        func pick(_ candidates: [Int]) -> Int?? {
            let usable = candidates.filter { j in !isComponent(j) && !ancestors(j).contains(where: isComponent) && !paragraphs(in: j).isEmpty }
            let outer = usable.filter { j in !ancestors(j).contains(where: usable.contains) }
            guard !outer.isEmpty else { return nil }
            if outer.count == 1 { return .some(outer[0]) }
            if let headline, let holding = outer.first(where: { ancestors(headline).contains($0) }),
               outer.filter({ ancestors(headline).contains($0) }).count == 1 {
                return .some(holding)
            }
            let ranked = outer.map { ($0, weight(paragraphs(in: $0))) }.sorted { $0.1 > $1.1 }
            if ranked[0].1 >= 2 * ranked[1].1 { return .some(ranked[0].0) }
            return .some(nil)
        }
        let tiers: [(Boundary, (Element) -> Bool)] = [
            (.articleBody, { $0.itemprop.lowercased() == "articlebody" }),
            (.container, { element in element.classes.contains { name in containerNames.contains { name.lowercased().contains($0) } } }),
            (.article, { $0.tag == "article" }),
            (.main, { $0.tag == "main" || $0.id.lowercased() == "main-content" }),
        ]
        for (boundary, matches) in tiers {
            // Several of the page's own articles side by side in one list (an `<article>` in each
            // item, or directly in one element): a round-up's entries when they hold most of the
            // page's prose, a row of cards when they don't.
            if boundary == .article, let list = entryList(elements.indices.filter { matches(elements[$0]) }) {
                if 2 * weight(list.entries.flatMap { paragraphs(in: $0) }) >= weight(open) {
                    return done(list.container, .entries)
                }
                cards.formUnion(list.entries)
                open = open.filter { i in !ancestors(i).contains(where: cards.contains) }
                continue
            }
            switch pick(elements.indices.filter { matches(elements[$0]) }) {
            case .none: continue
            case .some(.none): return unbounded
            case .some(.some(let container)): return done(container, boundary)
            }
        }
        // No marked container: the region holding most of the page's prose, going down while one
        // child holds at least 70% of it. Two regions of like weight can't be told apart.
        var region: Int? = nil
        while true {
            let children = elements.indices.filter { elements[$0].parent == region && elements[$0].tag != "p" }
            let weighed = children.map { ($0, weight(paragraphs(in: $0))) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
            guard let top = weighed.first else { break }
            let here = weight(paragraphs(in: region))
            if Double(top.1) >= 0.7 * Double(here) {
                region = top.0
                continue
            }
            // Its prose is spread over several regions, none dominating: ambiguous, unless the
            // paragraphs sit directly in it (a plain page of paragraphs).
            let direct = weight(open.filter { elements[$0].parent == region })
            if weighed.count >= 2, Double(weighed[1].1) >= 0.25 * Double(here), Double(direct) < 0.5 * Double(here) {
                return unbounded
            }
            break
        }
        return done(region, .region)
    }

    /// The page's elements, with where each one's content starts and ends in `text` (the page with
    /// comments and the content of scripts, styles and the like taken out).
    static func parse(_ html: String) -> (NSString, [Element]) {
        var cleaned = html.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: " ", options: .regularExpression)
        for tag in rawText {
            cleaned = cleaned.replacingOccurrences(of: "<\(tag)\\b[\\s\\S]*?</\(tag)\\s*>", with: " ",
                                                   options: [.regularExpression, .caseInsensitive])
        }
        let text = cleaned as NSString
        var elements: [Element] = []
        var stack: [Int] = []
        func close(from index: Int, at position: Int) {
            for j in stack[index...] { elements[j].end = position }
            stack.removeSubrange(index...)
        }
        let inline: Set<String> = ["a", "span", "em", "strong", "b", "i", "u", "small", "sup", "sub", "mark", "cite", "q", "abbr",
                                   "time", "code", "font", "s", "del", "ins", "label"]
        guard let tags = try? NSRegularExpression(pattern: #"<(/?)([A-Za-z][A-Za-z0-9:-]*)((?:[^>"']|"[^"]*"|'[^']*')*)>"#) else {
            return (text, [])
        }
        for match in tags.matches(in: cleaned, range: NSRange(location: 0, length: text.length)) {
            let closing = text.substring(with: match.range(at: 1)) == "/"
            let tag = text.substring(with: match.range(at: 2)).lowercased()
            let attributes = text.substring(with: match.range(at: 3))
            if closing {
                if let index = stack.lastIndex(where: { elements[$0].tag == tag }) { close(from: index, at: match.range.location) }
                continue
            }
            // A new block ends an open paragraph (with any inline elements left open inside it).
            if blocks.contains(tag), let p = stack.lastIndex(where: { elements[$0].tag == "p" }),
               stack[(p + 1)...].allSatisfy({ inline.contains(elements[$0].tag) }) {
                close(from: p, at: match.range.location)
            }
            let element = Element(tag: tag, classes: attribute("class", in: attributes).split(separator: " ").map(String.init),
                                  id: attribute("id", in: attributes), itemprop: attribute("itemprop", in: attributes),
                                  parent: stack.last, start: match.range.location + match.range.length, end: text.length)
            elements.append(element)
            if !void.contains(tag), !attributes.hasSuffix("/") { stack.append(elements.count - 1) }
        }
        return (text, elements)
    }

    static func attribute(_ name: String, in attributes: String) -> String {
        let pattern = "(?:^|\\s)" + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)) else { return "" }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: attributes) { return String(attributes[range]) }
        }
        return ""
    }
}
