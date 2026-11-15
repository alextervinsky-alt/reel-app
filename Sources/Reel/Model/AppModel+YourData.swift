#if os(macOS)
import Foundation
import ReelCore

/// Your data's safety in 1.11: matches remembered in Your Notes, frame removals kept there, and the
/// frame removals made before 1.11 carried over once. The rules are in ReelCore (`MatchMemory`,
/// `StillRemovals`); this only applies them.
extension AppModel {
    // MARK: Matches

    /// Remembers every copy's film in Your Notes (`MatchMemory`). Run whenever the library changes;
    /// saves only when something new was remembered.
    func rememberMatches() {
        guard isLoaded else { return }
        let updated = MatchMemory.remember(films, into: matches)
        guard updated != matches else { return }
        if matches.isEmpty {
            // The first time (the first launch of 1.11): how many matches are now kept as yours.
            AppendLog.append("\(Date().formatted(.iso8601)) \(AppModel.writtenBy): matches remembered in Your Notes: \(updated.count)"
                             + (notesWritable ? "" : " (Your Notes is read-only this session: not saved yet)") + ".\n",
                             to: folder.root.appendingPathComponent("Migration log.txt"))
        }
        matches = updated
        scheduleSave(.notes)
    }

    // MARK: Frames from the film

    /// The film's frames to show: what passed the check, less what you removed.
    func visibleStills(_ film: FilmEntry, checked: [String]? = nil) -> [String] {
        let stills = checked ?? film.checkedStills ?? []
        return StillRemovals.visible(stills, removed: film.tmdb.flatMap { removedStills[$0.id] })
    }

    /// Carries over, once per film, the frames you removed before 1.11, which were only kept as
    /// missing from the film's checked stills (`StillRemovals.recover`). It runs the same on-device
    /// check again on the same images, quietly, one film at a time, and writes what it found to
    /// Your Notes. A film whose images can't all be fetched now is tried again next launch.
    func recoverStillRemovals() async {
        guard notesWritable, hasToken else { return }
        try? await Task.sleep(for: .seconds(30))
        var seen = Set<Int>()
        let todo = films.compactMap { film -> (Int, [String], [String], String?)? in
            guard let details = film.tmdb, let stored = film.checkedStills, !stillsRecovered.contains(details.id),
                  seen.insert(details.id).inserted else { return nil }
            return (details.id, stored, details.stillPaths, details.backdropPath)
        }
        guard !todo.isEmpty else { return }
        var report = StillRecoveryReport()
        for (id, stored, paths, backdrop) in todo {
            guard !Task.isCancelled, notesWritable else { break }
            var passNow: [String] = []
            var complete = true
            // The same images as the check in Frames from the Film: the main backdrop is left out.
            for path in paths where path != backdrop {
                guard let image = await ImageStore.shared.image(path, .still) else {
                    complete = false
                    break
                }
                let keep = await Task.detached(priority: .utility) { StillFilter.looksLikeFrame(image.cgImage) }.value
                if keep { passNow.append(path) }
            }
            guard complete else {
                report.later += 1
                continue
            }
            if let removed = StillRemovals.recover(stored: stored, passNow: passNow) {
                if !removed.isEmpty {
                    removedStills[id, default: []].formUnion(removed)
                    report.filmsWithRemovals += 1
                    report.removals += removed.count
                }
                report.checked += 1
            } else {
                report.unclear += 1
            }
            stillsRecovered.insert(id)
            scheduleSave(.notes)
        }
        report.write(to: folder.root.appendingPathComponent("Migration log.txt"))
    }
}

/// What carrying over frame removals found: counts only, appended to "Migration log.txt" in the
/// Reel folder for the post-install check.
struct StillRecoveryReport {
    var checked = 0
    var filmsWithRemovals = 0
    var removals = 0
    /// Films where it couldn't be told (the images or the check changed since).
    var unclear = 0
    /// Films whose images couldn't all be fetched; tried again next launch.
    var later = 0

    func write(to url: URL) {
        let stamp = Date().formatted(.iso8601)
        let line = "\(stamp) \(AppModel.writtenBy): frame removals carried over: \(removals) in \(filmsWithRemovals) films; "
            + "\(checked) films checked, \(unclear) couldn't be told, \(later) to try again.\n"
        AppendLog.append(line, to: url)
    }
}

enum AppendLog {
    static func append(_ line: String, to url: URL) {
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
#endif
