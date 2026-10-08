#if os(macOS)
import SwiftUI
import ReelCore

// MARK: - Behind the Film

/// The film's life off screen, short first: "Did you know?", quick facts, then the article as a
/// few cards, one per heading (Production, Release, Reception…). Each card opens on a sentence
/// or two and the facts picked from it, and opens in place to read the whole of it. What gives
/// the story away waits under After You Watch until the film is watched. Then frames from the
/// film, and where to read more.
struct BehindTheFilmTab: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    let openStill: ([String], Int) -> Void
    /// Cards opened to their full text.
    @State private var opened: Set<String> = []
    /// After You Watch (and facts that give the story away) shown anyway, for this visit.
    @State private var showAfter = false
    /// The cards, worked out once for what they're made from (not on each redraw).
    @State private var built = Built()

    var body: some View {
        let id = film.tmdb?.id ?? 0
        let hiding = model.hidesSpoilers(for: film) && !showAfter
        let article = model.articles[id]
        let content = built.content(film: film, article: article, hiding: hiding)

        VStack(alignment: .leading, spacing: 34) {
            if let highlight = content.highlight { DidYouKnow(text: highlight) }
            QuickFactsGrid(film: film)
            if content.hiddenFacts > 0, article?.after.isEmpty != false {
                // Nothing else to open: say what's held back, with a way to see it.
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash").foregroundStyle(Theme.brand)
                    Text(content.hiddenFacts == 1 ? "1 fact may give the story away, so it's hidden until you've watched the film."
                                                  : "\(content.hiddenFacts) facts may give the story away, so they're hidden until you've watched the film.")
                        .foregroundStyle(Theme.secondaryText)
                    Button("Show Anyway") { withAnimation(.easeOut(duration: 0.2)) { showAfter = true } }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.brand)
                        .fontWeight(.medium)
                }
                .font(.system(size: 13))
            }
            let before = content.before
            let after = content.after
            let more = content.more
            if !before.isEmpty || more != nil {
                part("Before You Watch", note: "How the film was made, its context and how it was received, without the story.") {
                    ForEach(before) { card($0) }
                    if let more { card(more) }
                }
            }
            if let article, !article.after.isEmpty {
                if hiding {
                    LockedAfter(count: article.after.count) {
                        withAnimation(.easeOut(duration: 0.25)) { showAfter = true }
                    }
                } else {
                    part("After You Watch", note: "The story, its themes and the ending.") {
                        ForEach(after) { card($0) }
                    }
                }
            }
            if article == nil { status(id) }
            // Hidden once checked and none turned out to be frames from the film.
            if !(film.tmdb?.stillPaths.isEmpty ?? true), film.checkedStills?.isEmpty != true {
                VStack(alignment: .leading, spacing: 14) {
                    Theme.sectionTitle("Frames from the Film")
                    FilmStills(film: film, open: openStill)
                }
            }
            ReadMore(film: film, article: article)
        }
        .frame(maxWidth: 820, alignment: .leading)
        // The facts first (refreshed when old; they say which article it is), then the article.
        .task(id: id) {
            await model.loadFunFacts(for: film)
            await model.loadArticle(for: film)
        }
        .onChange(of: film.id) {
            opened = []
            showAfter = false
        }
    }

    private func part<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.brand)
                Text(note).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func card(_ topic: Topic) -> some View {
        TopicCard(topic: topic, open: opened.contains(topic.id)) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                if opened.contains(topic.id) { opened.remove(topic.id) } else { opened.insert(topic.id) }
            }
        }
    }

    @ViewBuilder
    private func status(_ id: Int) -> some View {
        if model.articlesLoading.contains(id) || film.tmdb.map({ model.funFactsLoading.contains($0.id) }) == true {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Finding the story behind the film…").foregroundStyle(.secondary)
            }
        } else if model.articlesMissing.contains(id) {
            Text("Wikipedia has no article about this film yet.").foregroundStyle(.secondary)
        } else if film.funFacts == nil {
            Text("This needs an internet connection the first time.").foregroundStyle(.secondary)
        }
    }

    // MARK: Topics

    /// One card: a chapter of the article, made short.
    struct Topic: Identifiable {
        let id: String
        let title: String
        let symbol: String
        /// Its opening sentence or two.
        let lead: String
        /// The whole of it, section by section (none for a card of facts only).
        let parts: [Chapter.Part]
        /// Facts picked from it, beyond the lead.
        let facts: [FunFact]
        let minutes: Int
        /// There's more than the card shows closed.
        let hasMore: Bool
    }

    /// The cards for one part, each opening without repeating the "Did you know?".
    static func topics(_ sections: [FilmArticle.Section], facts: [FunFact], highlight: String?, prefix: String) -> [Topic] {
        Digest.chapters(sections).map { chapter in
            let paragraphs = chapter.paragraphs
            let lead = Digest.lead(of: paragraphs, skipping: highlight)
            return Topic(id: "\(prefix)-\(chapter.id)", title: chapter.title, symbol: symbol(for: chapter.title), lead: lead,
                         parts: chapter.parts, facts: Digest.facts(facts, in: paragraphs, lead: lead),
                         minutes: Digest.minutes(paragraphs), hasMore: Digest.hasMore(paragraphs, lead: lead))
        }
    }

    /// Facts from outside the article's sections (Wikidata, or sections not shown), as one card.
    static func leftover(_ facts: [FunFact], sections: [FilmArticle.Section]) -> Topic? {
        let rest = Digest.leftover(facts, sections: sections)
        guard !rest.isEmpty else { return nil }
        return Topic(id: "more", title: sections.isEmpty ? "Facts" : "More Facts", symbol: "sparkles", lead: "",
                     parts: [], facts: rest, minutes: 1, hasMore: rest.count > TopicCard.closedFacts)
    }

    /// The facts without any that may mention the story, and a "Did you know?" that makes sense
    /// on its own and gives nothing away.
    static func withoutStory(_ facts: FunFacts, hiding: Bool) -> FunFacts {
        var shown = facts
        if hiding { shown.facts = facts.facts.filter { !Spoilers.mentionsPlot($0.text) } }
        if let highlight = facts.highlight, !FunFactExtractor.standsAlone(highlight) || (hiding && Spoilers.mentionsPlot(highlight)) {
            shown.highlight = shown.facts.first { $0.category != "At a glance" && FunFactExtractor.standsAlone($0.text) }?.text
        }
        return shown
    }

    /// What the cards are made from, kept until the film's facts, its article or hiding change.
    @MainActor
    final class Built {
        struct Content {
            var highlight: String?
            var hiddenFacts = 0
            var before: [Topic] = []
            var after: [Topic] = []
            var more: Topic?
        }

        private var key: String?
        private var content = Content()

        func content(film: FilmEntry, article: FilmArticle?, hiding: Bool) -> Content {
            let stamp = "\(film.id)|\(film.funFacts?.fetchedAt.timeIntervalSince1970 ?? 0)|\(article?.title ?? "")|\(hiding)"
            if stamp == key { return content }
            let all = film.funFacts
            let facts = all.map { BehindTheFilmTab.withoutStory($0, hiding: hiding) }
            let picked = (facts?.facts ?? []).filter { $0.text != facts?.highlight }
            let highlight = facts?.highlight
            content = Content(
                highlight: highlight,
                hiddenFacts: (all?.facts.count ?? 0) - (facts?.facts.count ?? 0),
                before: article.map { BehindTheFilmTab.topics($0.before, facts: picked, highlight: highlight, prefix: "before") } ?? [],
                after: article.map { BehindTheFilmTab.topics($0.after, facts: picked, highlight: highlight, prefix: "after") } ?? [],
                more: BehindTheFilmTab.leftover(picked, sections: (article?.before ?? []) + (article?.after ?? [])))
            key = stamp
            return content
        }
    }

    private static func symbol(for title: String) -> String {
        let t = title.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if t == "about the film" { return "film" }
        if has(["plot", "synopsis", "story", "ending"]) { return "book" }
        if has(["theme", "analysis", "interpretation", "style"]) { return "sparkles" }
        if has(["development", "writing", "screenplay", "script", "pre-production", "origin"]) { return "text.book.closed" }
        if has(["casting", "cast "]) { return "person.2" }
        if has(["filming", "photography", "production", "shooting", "design", "cinematography"]) { return "video" }
        if has(["effects", "visual", "animation"]) { return "wand.and.stars" }
        if has(["music", "soundtrack", "score"]) { return "music.note" }
        if has(["release", "box office", "marketing", "distribution", "home media", "premiere"]) { return "ticket" }
        if has(["reception", "critical", "response", "reviews"]) { return "quote.bubble" }
        if has(["accolades", "awards", "honours", "honors"]) { return "trophy" }
        if has(["legacy", "influence", "sequel", "impact", "culture"]) { return "clock.arrow.circlepath" }
        if has(["controvers", "lawsuit", "legal"]) { return "exclamationmark.bubble" }
        return "text.alignleft"
    }
}

/// A section, closed to its opening and two facts; open to the whole of it.
private struct TopicCard: View {
    static let closedFacts = 2

    let topic: BehindTheFilmTab.Topic
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if open {
                ForEach(Array(topic.parts.enumerated()), id: \.offset) { _, part in
                    VStack(alignment: .leading, spacing: 10) {
                        if let title = part.title {
                            Text(title.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                        }
                        ForEach(Array(part.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.system(size: 15.5, design: .serif))
                                .lineSpacing(5)
                                .foregroundStyle(Color.white.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                // A card of facts only shows them all.
                if topic.parts.isEmpty { facts(topic.facts) }
            } else {
                if !topic.lead.isEmpty {
                    Text(topic.lead)
                        .font(.system(size: 15.5, design: .serif))
                        .lineSpacing(5)
                        .foregroundStyle(Color.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                facts(Array(topic.facts.prefix(Self.closedFacts)))
                if topic.hasMore {
                    Button(action: toggle) {
                        HStack(spacing: 4) {
                            Text(topic.parts.isEmpty ? "All \(topic.facts.count) Facts" : "Read More")
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
    }

    /// The title, and how long the whole of it takes to read; clicking it opens or closes it.
    private var header: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: topic.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 18)
                Text(topic.title)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .lineLimit(2)
                Spacer(minLength: 12)
                if topic.hasMore {
                    if !topic.parts.isEmpty {
                        Text(open ? "Show Less" : "\(topic.minutes) min read")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!topic.hasMore)
    }

    private func facts(_ facts: [FunFact]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(facts, id: \.text) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(Theme.brand)
                        .frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                    Text(fact.text)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// "Did you know?": the one fact most worth knowing.
private struct DidYouKnow: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Did you know?", systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.brand)
            Text(text)
                .font(.system(size: 18, weight: .medium))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Theme.brand.opacity(0.18), Theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

/// After You Watch, closed until the film is watched.
private struct LockedAfter: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("After You Watch", systemImage: "lock.fill")
                .font(.system(size: 15, weight: .semibold))
            Text("\(count == 1 ? "One part" : "\(count) parts") of the story behind the film tell the plot, its themes or the ending. They open on their own once you mark the film as watched.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Read Anyway", action: open)
                .buttonStyle(SecondaryCapsuleStyle())
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// Based on, filmed in, set in, money, awards, what it follows and what follows it.
private struct QuickFactsGrid: View {
    let film: FilmEntry

    var body: some View {
        let rows = self.rows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Theme.sectionTitle("Quick Facts")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(rows, id: \.label) { row in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: row.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.brand)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.label.uppercased())
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundStyle(.tertiary)
                                Text(row.value)
                                    .font(.system(size: 13.5))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
                    }
                }
            }
        }
    }

    private var rows: [(label: String, value: String, icon: String)] {
        var rows: [(label: String, value: String, icon: String)] = []
        let quick = film.funFacts?.quick
        if let q = quick {
            if !q.basedOn.isEmpty { rows.append(("Based on", q.basedOn.joined(separator: ", "), "book.closed")) }
            if !q.filmedIn.isEmpty { rows.append(("Filmed in", q.filmedIn.joined(separator: ", "), "mappin.and.ellipse")) }
            if !q.setIn.isEmpty { rows.append(("Set in", q.setIn.joined(separator: ", "), "globe.europe.africa")) }
        }
        if let money = moneyLine { rows.append(("Budget and box office", money, "dollarsign.circle")) }
        if let q = quick {
            if q.awardsWon > 0 || q.nominations > 0 {
                var text = "\(q.awardsWon) won, \(q.nominations) nominations"
                if !q.notableAwards.isEmpty { text += " · " + q.notableAwards.prefix(3).joined(separator: ", ") }
                rows.append(("Awards", text, "trophy"))
            }
            if let follows = q.follows { rows.append(("Follows", follows, "arrow.left.circle")) }
            if let next = q.followedBy { rows.append(("Followed by", next, "arrow.right.circle")) }
        }
        return rows
    }

    /// "$150M budget · $277M worldwide (1.8×)"
    private var moneyLine: String? {
        let budget = film.tmdb?.budget ?? 0
        let revenue = film.tmdb?.revenue ?? 0
        func money(_ value: Int) -> String {
            value >= 1_000_000_000 ? String(format: "$%.1fB", Double(value) / 1e9) : "$\(value / 1_000_000)M"
        }
        switch (budget >= 100_000, revenue >= 100_000) {
        case (true, true):
            return "\(money(budget)) budget · \(money(revenue)) worldwide (\(String(format: "%.1f", Double(revenue) / Double(budget)))×)"
        case (true, false): return "\(money(budget)) budget"
        case (false, true): return "\(money(revenue)) worldwide"
        default: return nil
        }
    }
}

/// Reviews and essays elsewhere, and where the text came from.
private struct ReadMore: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    let article: FilmArticle?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Read More").font(.system(size: 15, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8, alignment: .leading)],
                      alignment: .leading, spacing: 8) {
                ForEach(model.readMoreLinks(for: film), id: \.title) { link in
                    Link(destination: link.url) {
                        HStack(spacing: 5) {
                            Text(link.title)
                            Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(Color.white.opacity(0.88))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                if model.hidesSpoilers(for: film) { Text("Reviews elsewhere may discuss the story.") }
                Text("From Wikipedia and Wikidata (CC BY-SA).")
                if let url = article?.url { Link("Open the full article", destination: url) }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }
}
#endif
