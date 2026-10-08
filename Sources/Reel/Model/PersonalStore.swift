#if os(macOS)
import Foundation
import Observation
import ReelCore

/// One film's notes, observed on its own: changing a film redraws only the views showing that
/// film, never the whole grid.
@Observable @MainActor
final class RecordBox {
    var record: PersonalRecord

    init(_ record: PersonalRecord) {
        self.record = record
    }
}

/// Which films are on tonight's shortlist, one observable flag per film: a poster's moon redraws
/// only that poster when the list changes.
@MainActor
final class TonightMarks {
    @Observable @MainActor
    final class Mark {
        var isOn = false
    }

    private var marks: [String: Mark] = [:]
    private var current: Set<String> = []

    func isOn(_ key: String) -> Bool {
        mark(key).isOn
    }

    func update(_ keys: [String]) {
        let new = Set(keys)
        for key in current.symmetricDifference(new) { mark(key).isOn = new.contains(key) }
        current = new
    }

    private func mark(_ key: String) -> Mark {
        if let existing = marks[key] { return existing }
        let created = Mark()
        created.isOn = current.contains(key)
        marks[key] = created
        return created
    }
}

/// Watched, favorites, watchlist, ratings and notes, keyed by `FilmEntry.personalKey`.
///
/// Views read one film through `record(forKey:)`. Shelves and lists read the derived sets, which
/// only change when a flag changes, so typing a note redraws nothing but the note.
@Observable @MainActor
final class PersonalStore {
    /// Everything, as saved in Your Notes.
    @ObservationIgnored private(set) var records: [String: PersonalRecord] = [:]
    @ObservationIgnored private var boxes: [String: RecordBox] = [:]

    private(set) var watchedKeys: Set<String> = []
    private(set) var watchlistKeys: Set<String> = []
    private(set) var favoriteKeys: Set<String> = []
    /// When each watched film was watched (for the diary and Year in Film).
    private(set) var watchedDates: [String: Date] = [:]
    /// TMDB ids of films watched, on a drive or elsewhere.
    private(set) var watchedIDs: Set<Int> = []
    /// Goes up whenever a rating or a heart changes (what Watch Again and your taste follow).
    private(set) var ratingsVersion = 0

    /// One film, for a view: the view redraws when this film changes, and only then.
    func record(forKey key: String) -> PersonalRecord {
        box(key).record
    }

    /// One film, for the model's own work (not observed).
    func stored(_ key: String) -> PersonalRecord {
        records[key] ?? PersonalRecord()
    }

    func load(_ all: [String: PersonalRecord]) {
        records = all
        for (key, box) in boxes { box.record = all[key] ?? PersonalRecord() }
        rederive()
    }

    /// Stores a film's record and returns the one it replaced.
    @discardableResult
    func set(_ record: PersonalRecord, forKey key: String) -> PersonalRecord {
        let old = stored(key)
        guard old != record else { return old }
        records[key] = record.isEmpty ? nil : record
        boxes[key]?.record = record
        if old.rating != record.rating || old.favorite != record.favorite { ratingsVersion += 1 }
        if old.watched != record.watched || old.watchlist != record.watchlist || old.favorite != record.favorite
            || old.watchedOn != record.watchedOn {
            update(key, from: old, to: record)
        }
        return old
    }

    /// Carries notes over when a file gets identified or re-identified. Notes that still belong
    /// to another film are copied, never moved.
    func migrate(from oldKey: String, to newKey: String, oldKeyStillUsed: Bool) {
        guard oldKey != newKey, let moving = records[oldKey] else { return }
        if oldKeyStillUsed && oldKey.hasPrefix("tmdb:") { return }
        set(records[newKey].map { $0.merged(with: moving) } ?? moving, forKey: newKey)
        if !oldKeyStillUsed { set(PersonalRecord(), forKey: oldKey) }
    }

    private func box(_ key: String) -> RecordBox {
        if let existing = boxes[key] { return existing }
        let created = RecordBox(stored(key))
        boxes[key] = created
        return created
    }

    private func update(_ key: String, from old: PersonalRecord, to new: PersonalRecord) {
        if old.watched != new.watched { Self.toggle(&watchedKeys, key, new.watched) }
        if old.watchlist != new.watchlist { Self.toggle(&watchlistKeys, key, new.watchlist) }
        if old.favorite != new.favorite { Self.toggle(&favoriteKeys, key, new.favorite) }
        let date = new.watched ? new.watchedOn : nil
        if watchedDates[key] != date { watchedDates[key] = date }
        if old.watched != new.watched, let id = Self.tmdbID(key) {
            if new.watched { watchedIDs.insert(id) } else { watchedIDs.remove(id) }
        }
    }

    private func rederive() {
        var watched = Set<String>(), watchlist = Set<String>(), favorites = Set<String>()
        var dates: [String: Date] = [:]
        var ids = Set<Int>()
        for (key, record) in records {
            if record.watched {
                watched.insert(key)
                if let date = record.watchedOn { dates[key] = date }
                if let id = Self.tmdbID(key) { ids.insert(id) }
            }
            if record.watchlist { watchlist.insert(key) }
            if record.favorite { favorites.insert(key) }
        }
        watchedKeys = watched
        watchlistKeys = watchlist
        favoriteKeys = favorites
        watchedDates = dates
        watchedIDs = ids
        ratingsVersion += 1
    }

    private static func toggle(_ set: inout Set<String>, _ key: String, _ on: Bool) {
        if on { set.insert(key) } else { set.remove(key) }
    }

    static func tmdbID(_ key: String) -> Int? {
        key.hasPrefix("tmdb:") ? Int(key.dropFirst(5)) : nil
    }
}
#endif
