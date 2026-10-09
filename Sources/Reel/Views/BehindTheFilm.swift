#if os(macOS)
import SwiftUI
import ReelCore

// MARK: - Behind the Film

/// The film's life off screen, told as a story: five things worth knowing (each with what the
/// article says next), the film at a glance, then
/// its life from the idea to its legacy as numbered chapters, in the order it lived them (the
/// article's sections regrouped: the idea, the casting, the shoot, design, music, release, how it
/// was received, awards, legacy). Each chapter opens on its best lines, someone's own words set
/// apart and a fact or two, and opens in place to read the whole of it. What gives the story
/// away waits under After You Watch until the film is watched. Then where it was filmed, and
/// where to read more. (Frames from the film are in the Cinematography tab.)
struct BehindTheFilmTab: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    /// Chapters opened to their full text.
    @State private var opened: Set<String> = []
    /// After You Watch (and facts that give the story away) shown anyway, for this visit.
    @State private var showAfter = false
    /// The chapters, worked out once for what they're made from (not on each redraw).
    @State private var built = Built()

    var body: some View {
        let id = film.tmdb?.id ?? 0
        let hiding = model.hidesSpoilers(for: film) && !showAfter
        let article = model.articles[id]
        let content = built.content(film: film, article: article, hiding: hiding)

        VStack(alignment: .leading, spacing: 38) {
            if !content.toKnow.isEmpty { DidYouKnow(items: content.toKnow) }
            AtAGlance(film: film)
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
            let before = content.before + (content.more.map { [$0] } ?? [])
            if !before.isEmpty {
                part("From Idea to Legacy", note: "How the film came to be and the life it had, without the story. \(Self.readingTime(before)).") {
                    Timeline(topics: before) { card($0) }
                }
            }
            if let article, !article.after.isEmpty {
                if hiding {
                    LockedAfter(count: article.after.count) {
                        withAnimation(.easeOut(duration: 0.25)) { showAfter = true }
                    }
                } else {
                    part("After You Watch", note: "The story, its themes and the ending.") {
                        Timeline(topics: content.after) { card($0) }
                    }
                }
            }
            if article == nil { status(id) }
            WhereItWasFilmed(places: Self.places(film.funFacts?.quick), sentences: content.locations)
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

    /// Wikidata's filming places with what they are; names only for facts kept before 1.8.1.
    static func places(_ quick: QuickFacts?) -> [FilmingPlace] {
        quick?.filmingPlaces ?? (quick?.filmedIn ?? []).map { FilmingPlace(name: $0, about: nil) }
    }

    /// "About 14 minutes to read in full"
    static func readingTime(_ topics: [Topic]) -> String {
        let minutes = topics.reduce(0) { $0 + ($1.parts.isEmpty ? 0 : $1.minutes) }
        return minutes <= 1 ? "A minute to read in full" : "About \(minutes) minutes to read in full"
    }

    private func part<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
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

    /// One chapter: a stage of the film's life, made short.
    struct Topic: Identifiable {
        let id: String
        let title: String
        let symbol: String
        /// Its opening sentences.
        let lead: String
        /// Someone's own words, set apart (not in the lead).
        let quote: String?
        /// The whole of it, section by section (none for a card of facts only).
        let parts: [Chapter.Part]
        /// Facts picked from it, beyond the lead.
        let facts: [FunFact]
        let minutes: Int
        /// There's more than the card shows closed.
        let hasMore: Bool
    }

    /// The chapters before watching: the film's life in the order it lived it.
    static func story(_ sections: [FilmArticle.Section], facts: [FunFact], shown: [String]) -> [Topic] {
        Digest.story(sections).map { stage, chapter in
            topic(chapter, id: "before-\(stage.rawValue)", symbol: symbol(for: stage), facts: facts, shown: shown)
        }
    }

    /// The chapters after watching, under the article's own headings.
    static func topics(_ sections: [FilmArticle.Section], facts: [FunFact], shown: [String]) -> [Topic] {
        Digest.chapters(sections).map { chapter in
            topic(chapter, id: "after-\(chapter.id)", symbol: symbol(for: chapter.title), facts: facts, shown: shown)
        }
    }

    private static func topic(_ chapter: Chapter, id: String, symbol: String, facts: [FunFact], shown: [String]) -> Topic {
        let paragraphs = chapter.paragraphs
        // A lead a little longer than before: two or three sentences that tell, not one that labels.
        let lead = Digest.lead(of: paragraphs, limit: 330, skipping: shown)
        let quote = Digest.pullQuote(in: paragraphs, skipping: ([lead] + shown).joined(separator: " "))
        // The most surprising first; the business around the film (dates, takings) left out.
        let picked = Digest.facts(facts, in: paragraphs, lead: lead + " " + (quote ?? ""))
            .filter { !shown.contains($0.text) }
            .map { ($0, FunFactExtractor.score($0.text)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        return Topic(id: id, title: chapter.title, symbol: symbol, lead: lead, quote: quote,
                     parts: chapter.parts, facts: picked, minutes: Digest.minutes(paragraphs),
                     hasMore: Digest.hasMore(paragraphs, lead: lead))
    }

    /// Facts from outside the article's sections (Wikidata, or sections not shown), as one card.
    static func leftover(_ facts: [FunFact], sections: [FilmArticle.Section]) -> Topic? {
        // The introduction's facts sum up what the film page already says.
        let rest = Digest.leftover(facts, sections: sections.filter { $0.title != "About the Film" })
            .filter { $0.category != "At a glance" }
        guard !rest.isEmpty else { return nil }
        return Topic(id: "more", title: sections.isEmpty ? "Facts" : "More Facts", symbol: "sparkles", lead: "", quote: nil,
                     parts: [], facts: rest, minutes: 1, hasMore: rest.count > TopicCard.closedFacts)
    }

    /// The facts without any that may mention the story.
    static func withoutStory(_ facts: FunFacts, hiding: Bool) -> FunFacts {
        var shown = facts
        if hiding { shown.facts = facts.facts.filter { !Spoilers.mentionsPlot($0.text) } }
        return shown
    }

    /// A fact worth knowing, and what the article says next about it.
    struct Known: Identifiable {
        let fact: FunFact
        let more: String?
        var id: String { fact.text }
    }

    /// The five things most worth knowing, the most surprising first (see
    /// `FunFactExtractor.score`): the making of the film before its takings and prizes (one of
    /// those at most), each making sense on its own, at most two of a kind, none from the
    /// introduction (the film page already says it).
    static func didYouKnow(_ facts: FunFacts?) -> [FunFact] {
        guard let facts else { return [] }
        let business: Set<String> = ["Release", "Awards"]
        let worths: [(FunFact, Double)] = facts.facts.filter { fact in
            fact.category != "At a glance" && FunFactExtractor.standsAlone(fact.text) && fact.text.count <= 260
        }.map { fact in
            (fact, FunFactExtractor.score(fact.text) + (business.contains(fact.category) ? -2.5 : 0))
        }
        // Stable: equal worth keeps the article's order.
        let ranked = worths.enumerated().sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }.map(\.element)
        var chosen: [FunFact] = []
        for (fact, worth) in ranked where chosen.count < 5 && worth > 0 {
            guard chosen.filter({ $0.category == fact.category }).count < 2,
                  !business.contains(fact.category) || !chosen.contains(where: { business.contains($0.category) }) else { continue }
            chosen.append(fact)
        }
        return chosen
    }

    /// What the chapters are made from, kept until the film's facts, its article or hiding change.
    @MainActor
    final class Built {
        struct Content {
            var toKnow: [Known] = []
            /// The article's sentences about where it was shot (before-watching sections only).
            var locations: [String] = []
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
            var facts = all.map { BehindTheFilmTab.withoutStory($0, hiding: hiding) }
            // A sentence can pass on its own and still come from a paragraph that gives the story
            // away (After You Watch): while hiding, those stay out too.
            if hiding, let article, var safe = facts {
                safe.facts = Digest.leftover(safe.facts, sections: article.after)
                facts = safe
            }
            let top = BehindTheFilmTab.didYouKnow(facts)
            // What the article says next, from what may be read now (not After You Watch while hiding).
            let readable = (article?.before ?? []) + (hiding ? [] : article?.after ?? [])
            var taken = Set(top.map(\.text))
            let toKnow = top.map { fact -> Known in
                let more = Digest.followUp(to: fact.text, in: readable, excluding: taken)
                    .flatMap { hiding && Spoilers.mentionsPlot($0) ? nil : $0 }
                if let more { taken.insert(more) }
                return Known(fact: fact, more: more)
            }
            let shown = toKnow.flatMap { [$0.fact.text] + ($0.more.map { [$0] } ?? []) }
            // Each fact once: those at the top aren't repeated in the chapters.
            let picked = (facts?.facts ?? []).filter { !shown.contains($0.text) }
            content = Content(
                toKnow: toKnow,
                locations: article.map { Digest.locationSentences($0.before).filter { !shown.contains($0) } } ?? [],
                hiddenFacts: (all?.facts.count ?? 0) - (facts?.facts.count ?? 0),
                before: article.map { BehindTheFilmTab.story($0.before, facts: picked, shown: shown) } ?? [],
                after: article.map { BehindTheFilmTab.topics($0.after, facts: picked, shown: shown) } ?? [],
                more: BehindTheFilmTab.leftover(picked, sections: (article?.before ?? []) + (article?.after ?? [])))
            key = stamp
            return content
        }
    }

    private static func symbol(for stage: Digest.Stage) -> String {
        switch stage {
        case .idea: "lightbulb"
        case .making: "film.stack"
        case .casting: "person.2"
        case .shoot: "video"
        case .design: "wand.and.stars"
        case .music: "music.note"
        case .release: "ticket"
        case .reception: "quote.bubble"
        case .awards: "trophy"
        case .legacy: "clock.arrow.circlepath"
        case .other: "text.alignleft"
        }
    }

    private static func symbol(for title: String) -> String {
        let t = title.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if has(["plot", "synopsis", "story", "ending"]) { return "book" }
        if has(["theme", "analysis", "interpretation", "style"]) { return "sparkles" }
        return "text.alignleft"
    }
}

/// Chapters down a line, each with its number: the film's life read in order.
private struct Timeline<Card: View>: View {
    let topics: [BehindTheFilmTab.Topic]
    @ViewBuilder let card: (BehindTheFilmTab.Topic) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                HStack(alignment: .top, spacing: 16) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.brand)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.background))
                        .overlay(Circle().strokeBorder(Theme.brand.opacity(0.55), lineWidth: 1.5))
                        .padding(.top, 16)
                    card(topic)
                }
            }
        }
        // The line behind the numbers, from the first to the last.
        .background(alignment: .topLeading) {
            Rectangle()
                .fill(Theme.brand.opacity(0.22))
                .frame(width: 1.5)
                .padding(.leading, 16.25)
                .padding(.vertical, 34)
        }
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
                if let quote = topic.quote { PullQuote(text: quote) }
                facts(Array(topic.facts.prefix(Self.closedFacts)))
                if topic.hasMore {
                    Button(action: toggle) {
                        HStack(spacing: 4) {
                            Text(topic.parts.isEmpty ? "All \(topic.facts.count) Facts" : "Read the Chapter")
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

/// Someone's own words from the chapter, set apart.
private struct PullQuote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "quote.opening")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.brand)
                .padding(.top, 3)
            Text(text)
                .font(.system(size: 16, design: .serif))
                .italic()
                .lineSpacing(5)
                .foregroundStyle(Color.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .padding(.leading, 4)
    }
}

/// Five things worth knowing, numbered, the most surprising first: each a fact that stands on
/// its own, with what the article says next, and what part of the film's life it's about.
private struct DidYouKnow: View {
    let items: [BehindTheFilmTab.Known]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Did You Know?", systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.brand)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Theme.hairline) }
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("\(index + 1)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.brand)
                            .frame(width: 22, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.fact.text)
                                .font(.system(size: 16.5, weight: .medium))
                                .lineSpacing(4)
                                .foregroundStyle(Color.white.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            if let more = item.more {
                                Text(more)
                                    .font(.system(size: 13.5))
                                    .lineSpacing(3)
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            Text(item.fact.category.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
        }
    }
}

/// Where the film was shot: every place Wikidata knows, each with what it is ("greenhouse area in
/// Almería, Spain"), and the article's own sentences about its locations, studios and stages.
private struct WhereItWasFilmed: View {
    let places: [FilmingPlace]
    let sentences: [String]

    var body: some View {
        if !places.isEmpty || !sentences.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WHERE IT WAS FILMED")
                        .font(.system(size: 11.5, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.brand)
                    Text("The locations, studios and stages behind the film.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if !places.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 0, alignment: .topLeading)], alignment: .leading, spacing: 0) {
                            ForEach(places) { place in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.brand)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(place.name).font(.system(size: 14, weight: .semibold))
                                        if let about = place.about {
                                            Text(about.prefix(1).uppercased() + about.dropFirst())
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                    }
                    if !sentences.isEmpty {
                        if !places.isEmpty { Divider().overlay(Theme.hairline) }
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(sentences, id: \.self) { sentence in
                                Text(sentence)
                                    .font(.system(size: 15, design: .serif))
                                    .lineSpacing(4)
                                    .foregroundStyle(Color.white.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(18)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
            }
        }
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

/// The film at a glance, in one band: based on, filmed in, set in, the money, the awards (the
/// best known named under them), what it follows and what follows it.
private struct AtAGlance: View {
    let film: FilmEntry

    var body: some View {
        let rows = self.rows
        let notable = film.funFacts?.quick?.notableAwards ?? []
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Theme.sectionTitle("At a Glance")
                VStack(alignment: .leading, spacing: 0) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 0, alignment: .top)], alignment: .leading, spacing: 0) {
                        ForEach(rows, id: \.label) { row in
                            VStack(alignment: .leading, spacing: 5) {
                                Label(row.label.uppercased(), systemImage: row.icon)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundStyle(.tertiary)
                                Text(row.value)
                                    .font(.system(size: 14.5, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    if !notable.isEmpty {
                        Divider().overlay(Theme.hairline)
                        FlowLayout(spacing: 8) {
                            ForEach(notable.prefix(5), id: \.self) { award in
                                Label(award, systemImage: "laurel.leading")
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .frame(height: 26)
                                    .background(Capsule().fill(Color.white.opacity(0.07)))
                            }
                        }
                        .padding(16)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
            }
        }
    }

    private var rows: [(label: String, value: String, icon: String)] {
        var rows: [(label: String, value: String, icon: String)] = []
        let quick = film.funFacts?.quick
        if let q = quick {
            if !q.basedOn.isEmpty { rows.append(("Based on", q.basedOn.joined(separator: ", "), "book.closed")) }
            if !q.setIn.isEmpty { rows.append(("Set in", q.setIn.joined(separator: ", "), "globe.europe.africa")) }
        }
        if let money = moneyLine { rows.append(("Budget and box office", money, "dollarsign.circle")) }
        if let q = quick {
            if q.awardsWon > 0 || q.nominations > 0 {
                rows.append(("Awards", "\(q.awardsWon) won · \(q.nominations) nominations", "trophy"))
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
                if let url = article?.url { TextLink("Open the full article", destination: url) }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }
}
#endif
