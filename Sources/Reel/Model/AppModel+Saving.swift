#if os(macOS)
import Foundation
import ReelCore

/// Writes are batched, atomic and done off the main thread.
extension AppModel {
    func scheduleSave(_ target: SaveTarget) {
        saveTasks[target]?.cancel()
        saveTasks[target] = Task { [weak self] in
            try? await Task.sleep(for: target.delay)
            guard !Task.isCancelled else { return }
            self?.save(target)
        }
    }

    /// Takes a snapshot now and writes it on the background queue.
    func save(_ target: SaveTarget) {
        saveTasks[target]?.cancel()
        saveTasks[target] = nil
        let folder = self.folder
        let report: @Sendable (Error) -> Void = { [weak self] error in
            Task { @MainActor in
                self?.notice = "Couldn't save to Documents › Reel: \(error.localizedDescription)"
            }
        }
        switch target {
        case .library:
            // Never written before the library has been read: that would replace it with nothing.
            guard isLoaded else {
                scheduleSave(.library)
                return
            }
            let snapshot = LibraryFile(films: films)
            writer.enqueue {
                do { try JSONStore.save(snapshot, to: folder.library) } catch { report(error) }
            }
        case .notes:
            guard notesWritable else { return }
            let snapshot = PersonalFile(records: personal.records, corrections: corrections, wishlist: wishlist,
                                        wishlistArrivals: wishlistArrivals, groupingFixes: groupingFixes)
            let today = SafetyCopies.day(Date())
            let firstSaveToday = today != lastSafetyCopyDay
            lastSafetyCopyDay = today
            writer.enqueue {
                // The copy is taken before the first change of the day overwrites the file.
                if firstSaveToday { SafetyCopies.make(of: folder.notes, into: folder.safetyCopies) }
                do { try JSONStore.save(snapshot, to: folder.notes) } catch { report(error) }
            }
        case .settings:
            guard settingsWritable else { return }
            let snapshot = ReelSettings(tmdbToken: token, omdbKey: omdbKey, drives: drives, lastFeatured: lastFeatured,
                                        lastRecommended: launchPicks.isEmpty ? Array(previousPicks) : launchPicks,
                                        spoilerSafe: spoilerSafe, player: player.rawValue, playFullScreen: playFullScreen, tonight: tonight,
                                        tonightEvening: tonightEvening, notTonight: notTonight,
                                        yearCountsElsewhere: yearCountsElsewhere, lastExplorePicks: explorePicksShown,
                                        switchedToIINA: switchedToIINA)
            writer.enqueue {
                do { try JSONStore.save(snapshot, to: folder.settings, permissions: 0o600) } catch { report(error) }
            }
        }
    }

    /// Writes everything still waiting and blocks until it is on disk (used when quitting).
    func saveAllNow() {
        for target in Array(saveTasks.keys) {
            save(target)
        }
        writer.flush()
        lists.flush()
    }
}
#endif
