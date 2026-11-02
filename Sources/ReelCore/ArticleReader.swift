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
/// The page's headline is its `<h1>` matching the page's title (else the first not in a ticker
/// or menu). A block named only "sidebar" (or a `<form>`, a `<header>`) that holds most of the
/// page's prose is taken for the page's layout only when the page's structure alone finds no
/// article, or only an unmarked region, and that then finds one the page marks or one holding at
/// least twice the prose.
///
/// Where the page has prose but no one article can be told apart (two regions of equal weight, two
/// article bodies, every paragraph inside a component), nothing is read: the page is reported as not readable (see
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
                                      "address", "details", "fieldset", "hr", "menu", "li", "dd", "dt", "hgroup", "summary",
                                      "center", "figcaption", "search"]
    /// Components that aren't the article, by their element.
    static let componentTags: Set<String> = ["nav", "aside", "footer", "header", "form", "figcaption", "dialog"]
    /// Components that aren't the article, by a word of their class or id: related and recommended
    /// articles, tickers and carousels of other posts, promotions, advertising, newsletters, sharing
    /// and comments. Whole words of the name ("pp-content-ticker-item", "jp-relatedposts"), not
    /// parts of words. A block named only "sidebar" that holds most of the page's prose may be the
    /// page's layout instead (see `layoutWords`).
    static let componentWords: Set<String> = ["related", "relatedposts", "recommended", "recommendation", "recommendations",
                                              "teaser", "teasers", "ticker", "promo", "promos", "promoted", "promotion",
                                              "sponsored", "sponsor", "advert", "advertisement", "advertising", "ads", "newsletter",
                                              "subscribe", "subscription", "outbrain", "taboola", "yarpp", "carousel", "swiper",
                                              "sidebar", "comments", "comment", "share", "sharing", "sharedaddy", "social",
                                              "popular", "trending", "breadcrumb", "breadcrumbs", "readmore", "readnext",
                                              "morefrom", "youmaylike", "youmightlike"]
    /// Component words that can also name a page's layout column: a block so named that holds most
    /// of the page's prose may be the article's column (IndieWire's "_sidebar_…" gallery).
    static let layoutWords: Set<String> = ["sidebar"]
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

    nonisolated(unsafe) public static var debug: ((String) -> Void)? = nil
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
        // Each element's ancestors, nearest first, worked out once (a parent always comes first).
        var chains: [[Int]] = []
        chains.reserveCapacity(elements.count)
        for element in elements {
            let chain = element.parent.map { [$0] + chains[$0] } ?? []
            chains.append(chain)
        }
        func ancestors(_ i: Int) -> [Int] { chains[i] }
        // Each element's class and id, as words ("pp-content-ticker-item" → pp, content, ticker, item).
        let words: [[String]] = elements.map { element in
            (element.classes + [element.id]).flatMap { name in
                name.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map(String.init)
            }
        }
        func named(_ j: Int) -> Bool { words[j].contains(where: componentWords.contains) }
        // The page's headline: the `<h1>` that matches the page's title, else the first not in a
        // block named like a component or in a menu (a ticker's or slider's `<h1>`), else the first.
        let h1s = elements.indices.filter { elements[$0].tag == "h1" }
        let pageTitle = HTMLText.title(html).map { $0.lowercased() } ?? ""
        let headline = h1s.first { (j: Int) -> Bool in
            let heading = content(j).lowercased()
            return heading.count >= 4 && !pageTitle.isEmpty && (pageTitle.contains(heading) || heading.contains(pageTitle))
        } ?? h1s.first { j in !chains[j].contains { named($0) || ["nav", "aside", "footer"].contains(elements[$0].tag) } } ?? h1s.first
        let headlineAncestors = Set(headline.map { ancestors($0) } ?? [])
        // How much prose each element holds, components or not.
        let allProse = paragraphIndices.filter(isProse)
        var proseWeight: [Int: Int] = [:]
        for i in allProse { for j in ancestors(i) { proseWeight[j, default: 0] += texts[i]?.count ?? 0 } }
        let pageWeight = allProse.reduce(0) { $0 + (texts[$1]?.count ?? 0) }
        let leftOutOnPage = allProse.count
        // Nothing on the page reads as prose: an empty article (too little text), not a failure.
        guard !allProse.isEmpty else {
            return Article(paragraphs: [], boundary: .region, leftOut: 0, canonical: canonical)
        }
        let unbounded = Article(paragraphs: [], boundary: nil, leftOut: leftOutOnPage, canonical: canonical)
        // A round-up's entries nested in the page's own `<article>`: three or more sibling articles
        // holding a credits line or a spec sheet are entries, not cards.
        var nestedEntries = Set<Int>()
        do {
            let nested = elements.indices.filter { j in elements[j].tag == "article" && chains[j].contains { elements[$0].tag == "article" } }
            func holder(_ j: Int) -> Int? {
                guard let parent = elements[j].parent else { return nil }
                return elements[parent].tag == "li" ? elements[parent].parent : parent
            }
            let marked = nested.filter { (j: Int) -> Bool in
                allProse.contains { (i: Int) -> Bool in chains[i].contains(j) && (EntryLayout.isCredits(texts[i] ?? "") || EntryLayout.isLabelledSheet(texts[i] ?? "")) }
            }
            for (_, group) in Dictionary(grouping: marked, by: { holder($0) ?? -1 }) where group.count >= 3 { nestedEntries.formUnion(group) }
        }

        /// The article, with components left out. `layout`: a block named only by a layout word
        /// ("sidebar"), or a `<form>` or `<header>`, that holds most of the page's prose is the
        /// page's layout instead (IndieWire's galleries sit in a "_sidebar_…" column; a page wrapped
        /// in one form).
        func resolve(layout: Bool) -> Article {
            var cards = Set<Int>()
            func holdsMost(_ j: Int) -> Bool { layout && 2 * (proseWeight[j] ?? 0) >= pageWeight }
            var component: [Bool] = elements.indices.map { (j: Int) -> Bool in
                let element = elements[j]
                if element.tag == "html" || element.tag == "body" || headlineAncestors.contains(j) { return false }
                if element.tag == "header", chains[j].contains(where: { elements[$0].tag == "article" }) { return false }  // an article's own header
                if componentTags.contains(element.tag) { return !(["form", "header"].contains(element.tag) && holdsMost(j)) }
                if element.tag == "article", chains[j].contains(where: { elements[$0].tag == "article" }) { return !nestedEntries.contains(j) }
                guard named(j) else { return false }
                // Only a layout word ("sidebar") can name the page's layout; related posts, teasers,
                // promotions and comments are never the article, however much of the page they fill.
                let kinds = words[j].filter(componentWords.contains)
                return !(kinds.allSatisfy(layoutWords.contains) && holdsMost(j))
            }
            func isComponent(_ j: Int) -> Bool { component[j] }
            func inComponent(_ i: Int) -> Bool { chains[i].contains { component[$0] } }
            var open = allProse.filter { !inComponent($0) }
            if !layout {
                var why: [String: Int] = [:]
                for i in allProse where inComponent(i) {
                    if let j = chains[i].last(where: { component[$0] }) {
                        why[elements[j].tag + "." + elements[j].classes.joined(separator: ".") + "#" + elements[j].id, default: 0] += 1
                    }
                }
                debug?("excluded by: " + why.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key.prefix(90))=\($0.value)" }.joined(separator: " | "))
            }
            guard !open.isEmpty else { return unbounded }
            // Each element's open paragraphs, in page order.
            var under: [Int: [Int]] = [:]
            func index() {
                under = [:]
                for i in open { for j in chains[i] { under[j, default: []].append(i) } }
            }
            index()
            func paragraphs(in container: Int?) -> [Int] { container.map { under[$0] ?? [] } ?? open }
            func weight(_ indices: [Int]) -> Int { indices.reduce(0) { $0 + (texts[$1]?.count ?? 0) } }
            func done(_ container: Int?, _ boundary: Boundary) -> Article {
                let chosen = paragraphs(in: container)
                let kept = HTMLText.keep(chosen.compactMap { texts[$0] })
                return Article(paragraphs: kept, boundary: boundary, leftOut: leftOutOnPage - chosen.count, canonical: canonical)
            }
            /// Three or more of the page's own articles holding prose, none with the headline, in one
            /// list (each in an item of the same element, or directly in the same element): entries
            /// with credits lines or spec sheets, or none holding half the list's prose (a main
            /// article beside cards isn't a list).
            func entryList(_ articles: [Int]) -> (container: Int?, entries: [Int])? {
                let top = articles.filter { j in !chains[j].contains { elements[$0].tag == "article" } && !isComponent(j)
                    && !chains[j].contains(where: isComponent) && !paragraphs(in: j).isEmpty }
                guard top.count >= 3, !top.contains(where: headlineAncestors.contains) else { return nil }
                // A round-up's entries carry credits lines or spec sheets; otherwise none may hold
                // half the list's prose (that's an article beside its cards).
                func marked(_ j: Int) -> Bool {
                    paragraphs(in: j).contains { EntryLayout.isCredits(texts[$0] ?? "") || EntryLayout.isLabelledSheet(texts[$0] ?? "") }
                }
                let weights = top.map { weight(paragraphs(in: $0)) }
                let sorted = weights.sorted(by: >)
                guard top.filter(marked).count >= 3 || (2 * sorted[0] < weights.reduce(0, +) && sorted[0] < 2 * sorted[1]) else { return nil }
                func holder(_ j: Int) -> Int? {
                    guard let parent = elements[j].parent else { return nil }
                    return elements[parent].tag == "li" ? elements[parent].parent : parent
                }
                let holders = Set(top.map(holder))
                guard holders.count == 1, let container = holders.first else { return nil }
                return (container, top)
            }
            /// One of the candidates, when it's clear which: the outermost ones holding prose, one
            /// alone, the one holding the headline (unless it holds next to nothing: a hero with a
            /// dek), or one with at least twice the prose of any other. Nil: none; `.some(nil)`:
            /// more than one and no telling (ambiguous).
            func pick(_ candidates: [Int]) -> Int?? {
                let usable = candidates.filter { j in !isComponent(j) && !chains[j].contains(where: isComponent) && !paragraphs(in: j).isEmpty }
                let usableSet = Set(usable)
                let outer = usable.filter { j in !chains[j].contains(where: usableSet.contains) }
                guard !outer.isEmpty else { return nil }
                if outer.count == 1 { return .some(outer[0]) }
                let ranked = outer.map { ($0, weight(paragraphs(in: $0))) }.sorted { $0.1 > $1.1 }
                let holding = ranked.filter { headlineAncestors.contains($0.0) }
                if holding.count == 1, 4 * holding[0].1 >= ranked[0].1 { return .some(holding[0].0) }
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
                // Several of the page's own articles side by side in one list (an `<article>` in
                // each item, or directly in one element): a round-up's entries when they hold most
                // of the page's prose, a row of cards when they don't.
                if boundary == .article { debug?("layout=\(layout) entryList=\(String(describing: entryList(elements.indices.filter { matches(elements[$0]) })?.entries.count)) articles=\(elements.indices.filter { matches(elements[$0]) }.count)") }
                if boundary == .article, let list = entryList(elements.indices.filter { matches(elements[$0]) }) {
                    if 2 * weight(list.entries.flatMap { paragraphs(in: $0) }) >= weight(open) {
                        return done(list.container, .entries)
                    }
                    cards.formUnion(list.entries)
                    for j in cards { component[j] = true }
                    open = open.filter { !inComponent($0) }
                    guard !open.isEmpty else { return unbounded }
                    index()
                    continue
                }
                let pk = pick(elements.indices.filter { matches(elements[$0]) })
                debug?("layout=\(layout) tier=\(boundary) pick=\(String(describing: pk)) open=\(open.count)")
                switch pk {
                case .none: continue
                case .some(.none): return unbounded
                case .some(.some(let container)):
                    // A choice that would leave too little to read while the page holds more prose
                    // elsewhere (a hero `<article>` with the headline and a dek, the body outside
                    // it) isn't the article: the next tier looks.
                    let chosen = paragraphs(in: container).count
                    if chosen < 3, open.count - chosen >= 3 { continue }
                    return done(container, boundary)
                }
            }
            // No marked container: the region holding the page's prose, going down while one child
            // holds at least 70% of it, or half of it and twice any other's when the paragraphs
            // aren't its own (the article beside two teaser blocks).
            // Regions none of which outweighs the others can't be told apart.
            var region: Int? = nil
            while true {
                let children = (region.map { j in elements.indices.filter { elements[$0].parent == j } } ?? elements.indices.filter { elements[$0].parent == nil })
                    .filter { elements[$0].tag != "p" }
                let weighed = children.map { ($0, weight(paragraphs(in: $0))) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
                guard let top = weighed.first else { break }
                let here = weight(paragraphs(in: region))
                let direct = weight(paragraphs(in: region).filter { elements[$0].parent == region })
                let dominant = 2 * direct < here && 2 * top.1 >= here && top.1 >= 2 * direct
                    && (weighed.count == 1 || top.1 >= 2 * weighed[1].1)
                if Double(top.1) >= 0.7 * Double(here) || dominant {
                    region = top.0
                    continue
                }
                // Its prose is spread over two or more large regions, none dominating: ambiguous,
                // unless the paragraphs sit directly in it (a plain page of paragraphs). Many small
                // blocks of one article (a block editor's) are read together.
                if weighed.count >= 2, Double(weighed[1].1) >= 0.25 * Double(here), 2 * direct < here { return unbounded }
                break
            }
            return done(region, .region)
        }
        // The page's own structure first. Only when that finds no article, or only an unmarked
        // region, is a large block named like a component taken for the page's layout, and then
        // only if that finds an article the page marks as one.
        debug?("allProse=\(allProse.count) headline=\(String(describing: headline.map { content($0).prefix(60) })) title=\(pageTitle.prefix(60))")
        let first = resolve(layout: false)
        debug?("first=\(String(describing: first.boundary)) \(first.paragraphs.count) leftOut=\(first.leftOut)")
        let thin = first.paragraphs.count < 3
        guard first.boundary == nil || first.boundary == .region || thin else { return first }
        let second = resolve(layout: true)
        debug?("second=\(String(describing: second.boundary)) \(second.paragraphs.count) leftOut=\(second.leftOut)")
        if first.boundary == nil || first.paragraphs.isEmpty { return second.boundary == nil && first.boundary != nil ? first : second }
        guard second.boundary != nil else { return first }
        // An unmarked region from what the layout column left over: the column's reading, when the
        // page marks it, or when it holds at least twice the prose.
        func weight(_ article: Article) -> Int { article.paragraphs.reduce(0) { $0 + $1.count } }
        if first.boundary == .region, second.boundary != .region { return second }
        return weight(second) >= 2 * weight(first) ? second : first
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
                                   "time", "code", "font", "s", "del", "ins", "label", "kbd", "var", "samp", "bdi", "bdo", "dfn",
                                   "picture", "data", "big", "tt", "nobr"]
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
            // A new item ends the open item before it (and anything left open in it), in the same list.
            if ["li", "dd", "dt"].contains(tag),
               let item = stack.lastIndex(where: { ["li", "dd", "dt"].contains(elements[$0].tag) }),
               !stack[(item + 1)...].contains(where: { ["ul", "ol", "dl", "menu"].contains(elements[$0].tag) }) {
                close(from: item, at: match.range.location)
            }
            let element = Element(tag: tag, classes: attribute("class", in: attributes).split(separator: " ").map(String.init),
                                  id: attribute("id", in: attributes), itemprop: attribute("itemprop", in: attributes),
                                  parent: stack.last, start: match.range.location + match.range.length, end: text.length)
            elements.append(element)
            // A "/" before ">" closes nothing in HTML ("<div/>" opens a div; "<a href=/news/>" is a link).
            if !void.contains(tag) { stack.append(elements.count - 1) }
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
