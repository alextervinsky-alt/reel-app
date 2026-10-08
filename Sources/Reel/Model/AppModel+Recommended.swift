#if os(macOS)
import Foundation
import ReelCore

/// Recommended: five films from the library, picked fresh at each launch, with mood chips.
/// "Any" opens every launch; a chip swaps the five for films with that mood. Picks are kept per
/// chip for the session, so going back to a chip shows the same five.
extension AppModel {
    /// Unwatched films with info, except the one in the banner and ones set aside with "Not tonight".
    /// Films like the ones you rated highly rank higher (`taste`).
    private func recommendationPool() -> [Recommendable] {
        let now = Date()
        return items.compactMap { item in
            guard item.main.tmdb != nil, !personal.watchedKeys.contains(item.id), item.id != featuredKey,
                  (notTonight[item.id] ?? .distantPast) <= now else { return nil }
            let affinity = tasteMatch(item)?.score ?? 0
            return Recommendable(id: item.id, score: item.score, onWatchlist: personal.watchlistKeys.contains(item.id),
                                 isOnline: item.isOnline, genre: item.shortGenre, moods: item.moods, runtime: item.runtime,
                                 affinity: affinity)
        }
    }

    static func features(of item: LibraryItem) -> TasteFeatures {
        let d = item.main.tmdb
        return TasteFeatures(id: item.id, title: item.main.displayTitle, directors: d?.directors ?? [],
                             cinematographers: d?.cinematographers ?? [], moods: item.moods,
                             keywords: Array(item.keywords), genres: Array(item.genres))
    }

    /// Learns again from the films you've rated (one shared rating per film), only when a
    /// rating changed.
    private func updateTaste() {
        var signature = Hasher()
        let rated = personal.records.compactMap { key, record in record.rating.map { (key, $0) } }
            .filter { itemCache[$0.0] != nil }
            .sorted { $0.0 < $1.0 }
        for (key, stars) in rated {
            signature.combine(key)
            signature.combine(stars)
        }
        let value = signature.finalize()
        guard value != tasteSignature else { return }
        tasteSignature = value
        tasteMatches = [:]
        taste = TasteProfile(rated: rated.compactMap { key, stars in
            itemCache[key].map { (Self.features(of: $0), stars) }
        })
    }

    /// How a film fits your ratings, worked out once per film until a rating or the library changes.
    func tasteMatch(_ item: LibraryItem) -> TasteMatch? {
        guard !taste.isEmpty else { return nil }
        if let known = tasteMatches[item.id] { return known }
        let match = taste.match(Self.features(of: item))
        tasteMatches[item.id] = match
        return match
    }

    /// Why a pick is there (every pick has a reason; see `PickReason.pick`).
    private func reason(for item: LibraryItem) -> PickReason {
        let newOn = arrivals[item.id] != nil ? item.copies.first.flatMap { drive($0.driveID) }?.name : nil
        let listed = badges(for: item.main).first { $0.isWin }?.text
        let mood = recommendedChoice == .any ? "" : recommendedChoice.title
        return PickReason.pick(taste: tasteMatch(item)?.reason, onWatchlist: personal.watchlistKeys.contains(item.id),
                               newOn: newOn, listed: listed, mood: mood)
    }

    /// Why a film is offered: its Recommended reason, or what it shares with films you loved.
    func pickReason(forKey key: String) -> PickReason? {
        if let reason = recommendedReasons[key] { return reason }
        return itemCache[key].flatMap { tasteMatch($0) }.flatMap { $0.score >= 1 ? $0.reason : nil }
    }

    /// Takes a film out of the five on show (Not tonight) and fills its place.
    func dropFromPicks(_ key: String) {
        for (choice, list) in picks where list.contains(key) {
            picks[choice] = list.filter { $0 != key }
        }
        fillPicks(for: recommendedChoice, pool: recommendationPool())
        publishRecommended()
    }

    /// Runs in `rebuild()`. Keeps the picks on show (even ones watched since), fills places left
    /// by films that left the library, and picks once more films become eligible (e.g. while the
    /// library's info is still loading at launch).
    func updateRecommended() {
        updateTaste()
        let pool = recommendationPool()
        let choices = Recommender.choices(for: pool, keeping: recommendedChoice)
        if choices != recommendedChoices { recommendedChoices = choices }
        if !choices.contains(where: { $0.choice == recommendedChoice }) { recommendedChoice = .any }
        fillPicks(for: recommendedChoice, pool: pool)
        publishRecommended()
    }

    /// Shows a chip's five (picked the first time it's chosen).
    func chooseRecommended(_ choice: MoodChoice) {
        guard choice != recommendedChoice else { return }
        recommendedChoice = choice
        fillPicks(for: choice, pool: recommendationPool())
        publishRecommended()
    }

    /// Five other films for the current chip. The ones shuffled away come back less often until
    /// Reel quits; nothing about it is saved.
    func reshuffleRecommended() {
        let choice = recommendedChoice
        shuffledAway.formUnion(picks[choice] ?? [])
        picks[choice] = Recommender.pick(from: recommendationPool(), choice: choice,
                                         lastLaunch: previousPicks, shuffledAway: shuffledAway)
        rememberLaunchPicks(choice)
        publishRecommended()
    }

    private func fillPicks(for choice: MoodChoice, pool: [Recommendable]) {
        let current = (picks[choice] ?? []).filter { itemCache[$0] != nil }
        let eligible = pool.filter { Recommender.fits($0, choice) }.map { $0.id }
        let available = Set(eligible).union(current).count
        guard current.count < min(Recommender.count, available) || current.count != (picks[choice] ?? []).count else { return }
        picks[choice] = Recommender.pick(from: pool, choice: choice, keeping: current,
                                         lastLaunch: previousPicks, shuffledAway: shuffledAway)
        rememberLaunchPicks(choice)
    }

    /// Next launch avoids this launch's "Any" picks.
    private func rememberLaunchPicks(_ choice: MoodChoice) {
        guard choice == .any, let current = picks[.any], !current.isEmpty, current != launchPicks else { return }
        launchPicks = current
        scheduleSave(.settings)
    }

    private func publishRecommended() {
        let list = (picks[recommendedChoice] ?? []).compactMap { itemCache[$0] }
        if list != recommended { recommended = list }
        var reasons: [String: PickReason] = [:]
        for item in list { reasons[item.id] = reason(for: item) }
        if reasons != recommendedReasons { recommendedReasons = reasons }
    }
}
#endif
