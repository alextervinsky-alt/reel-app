#if os(macOS)
import Foundation
import ReelCore

/// Writes are batched, atomic and done off the main thread.
extension AppModel {
    func scheduleSave(_ target: SaveTarget) {
        // The library changes in a steady stream while film info is looked up: a save already
        // waiting takes its snapshot when it runs, so it isn't put off again (and again).
        if target == .library, saveTasks[target] != nil { return }
        saveTasks[target]?.cancel()
        // While film info is being looked up the library changes all the time: written every 30 s
        // and once at the end, not every 2 s (1.11; the run's end saves, see `lookUpPending`).
        let delay: Duration = target == .library && lookupRunning ? .seconds(30) : target.delay
        saveTasks[target] = Task { [weak self] in
            try? await Task.sleep(for: delay)
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
            // One that's there and couldn't be used isn't replaced (see `LibraryOpening`).
            guard libraryWritable else { return }
            let snapshot = LibraryFile(films: films, writtenBy: Self.writtenBy, scans: libraryScans.isEmpty ? nil : libraryScans)
            writer.enqueue {
                do { try JSONStore.save(snapshot, to: folder.library) } catch { report(error) }
            }
        case .notes:
            guard notesWritable else { return }
            let snapshot = PersonalFile(records: personal.records, corrections: corrections, matches: matches, wishlist: wishlist,
                                        wishlistArrivals: wishlistArrivals, groupingFixes: groupingFixes, pictures: pictures,
                                        removedShotOn: removedShotOn, removedStills: removedStills, removedFacts: removedFacts,
                                        stillsRecovered: stillsRecovered, passthrough: notesPassthrough)
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
                                        switchedToIINA: switchedToIINA, notForMe: notForMe.sorted())
            let today = SafetyCopies.day(Date())
            let firstSaveToday = today != lastSettingsCopyDay
            lastSettingsCopyDay = today
            writer.enqueue {
                // Settings keeps Not for Me and your drives: a daily copy too, before the day's first change (1.11).
                if firstSaveToday { SafetyCopies.make(of: folder.settings, into: folder.safetyCopies) }
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

extension AppModel {
    /// This Reel, as Library.json records who wrote it: "1.10.10 (380)".
    nonisolated static var writtenBy: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "development"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

#endif
