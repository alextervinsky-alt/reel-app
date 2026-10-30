import XCTest
@testable import ReelCore

/// Reel 1.10.4: the library looks after itself. The Shot on queue is run here as the app runs it
/// (`AppModel.readCraft` takes every decision from `CraftRun`), over a made-up library the size of a
/// real one (146 films, 266 copies), with made-up sources: nothing here reads the network or a real
/// library, and nobody opens a film page.
final class AutonomyTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: A made-up library

    /// 146 films, 120 of them on two drives (266 copies), info and Wikipedia facts in.
    private func library(films count: Int = 146, twice: Int = 120) -> [FilmEntry] {
        var all: [FilmEntry] = []
        for id in 1...count {
            for drive in id <= twice ? ["Main", "Backup"] : ["Main"] {
                var entry = FilmEntry(driveID: drive, relativePath: "Film \(id).mkv", fileName: "Film \(id).mkv", size: Int64(id),
                                      modified: nil, addedAt: start, matchState: .auto)
                entry.tmdb = TMDBMovieDetails(id: id, title: "Film \(id)")
                entry.funFacts = FunFacts(facts: [], articleTitle: "Film \(id)", fetchedAt: start)
                all.append(entry)
            }
        }
        return all
    }

    /// What a made-up source gives for a film.
    private enum Source {
        case found(CraftIndex)
        /// Every site there, nothing about how it was shot.
        case nothing
        /// Nothing could be reached.
        case unreachable
        /// A site didn't answer (or asked Reel to wait): read in part.
        case siteDown(String)
    }

    private func reading(_ source: Source, now: Date) -> CraftIndex? {
        switch source {
        case .found(let index):
            var index = index
            index.readAt = now
            return index
        case .nothing:
            return CraftIndex(readAt: now, shotOn: [], names: [], sources: 2, read: ["Wikipedia", "Lens Weekly"])
        case .unreachable:
            return nil
        case .siteDown(let site):
            return CraftIndex(readAt: now, shotOn: [], names: [], sources: 1, read: ["Wikipedia"], unanswered: [site])
        }
    }

    private func film(_ id: Int, digital: Bool = true) -> CraftIndex {
        CraftIndex(shotOn: digital ? [.digital] : [.film], names: [],
                   evidence: [CraftIndex.Evidence(shotOn: digital ? .digital : .film, text: "Film \(id) was shot on…", source: "Lens Weekly")],
                   sources: 2, read: ["Wikipedia", "Lens Weekly"])
    }

    /// One run, as the app does it: batches of two until nothing is due or it's offline, written in
    /// batches. `quitAfter`: Reel quits after that many films, before the readings not yet written
    /// are written (nil: the run ends normally). Returns the films read, in order.
    @discardableResult
    private func run(_ films: inout [FilmEntry], at now: Date, quitAfter: Int? = nil, source: (Int) -> Source) -> [Int] {
        var run = CraftRun(now: now)
        var order: [Int] = []
        while true {
            let batch = run.nextBatch(films, now: now)
            if batch.isEmpty { break }
            for entry in batch {
                guard let id = entry.tmdb?.id else { continue }
                order.append(id)
                let stored = CraftQueue.representatives(of: films.filter { $0.tmdb?.id == id }).first
                run.record(id, stored: stored, reading: reading(source(id), now: now), now: now)
                if let quitAfter, order.count >= quitAfter { return order }
            }
            run.endBatch()
            if run.offline { break }
            if let writes = run.takeWrites(now: now) { CraftRun.apply(read: writes.read, failed: writes.failed, to: &films) }
        }
        if let writes = run.takeWrites(now: now, force: true) { CraftRun.apply(read: writes.read, failed: writes.failed, to: &films) }
        return order
    }

    // MARK: Every film, by itself

    func testAWholeLibraryIsReadOnItsOwnEachFilmOnce() {
        var films = library()
        XCTAssertEqual(films.count, 266)
        XCTAssertEqual(CraftQueue.due(films, now: start).count, 146, "every film once, however many copies")
        let order = run(&films, at: start) { _ in .found(self.film(1)) }
        XCTAssertEqual(order.count, 146)
        XCTAssertEqual(Set(order).count, 146, "no film read twice")
        XCTAssertTrue(films.allSatisfy { $0.craft != nil }, "every copy has its film's reading")
        XCTAssertTrue(films.allSatisfy { CraftQueue.state(of: $0, now: self.start) == .complete })
        // Launched again: nothing to do, nothing asked again.
        XCTAssertEqual(run(&films, at: start.addingTimeInterval(60)) { _ in XCTFail("read again"); return .nothing }, [])
        XCTAssertEqual(CraftQueue.nextDue(films, now: start), start.addingTimeInterval(CraftIndex.maxAge), "half a year on")
    }

    /// No qualifying evidence is a finished reading, not a failure; it isn't read again soon.
    func testNothingFoundIsDoneNotFailed() {
        var films = library(films: 10, twice: 0)
        run(&films, at: start) { _ in .nothing }
        XCTAssertTrue(films.allSatisfy { $0.craft?.shotOn == [] && $0.craftAttempt == nil })
        XCTAssertTrue(films.allSatisfy { CraftQueue.state(of: $0, now: self.start.addingTimeInterval(86_400)) == .complete })
    }

    /// One film that can't be reached doesn't hold up the rest, waits its turn, and is read when due.
    func testAFilmThatCantBeReachedDoesntHoldUpTheRest() {
        var films = library()
        let order = run(&films, at: start) { id in id == 5 ? .unreachable : .found(self.film(id)) }
        XCTAssertEqual(order.count, 146)
        XCTAssertEqual(films.filter { $0.craft != nil }.count, 266 - 2, "all but film 5's two copies")
        let five = films.first { $0.tmdb?.id == 5 }!
        XCTAssertEqual(CraftQueue.state(of: five, now: start), .failed)
        let retry = five.craftAttempt!.retryAt
        XCTAssertEqual(retry, start.addingTimeInterval(6 * 3600))
        XCTAssertEqual(CraftQueue.nextDue(films, now: start), retry, "the app wakes then")
        // Before its time: nothing. At its time: that film alone.
        XCTAssertEqual(run(&films, at: start.addingTimeInterval(3600)) { _ in .nothing }, [])
        XCTAssertEqual(run(&films, at: retry.addingTimeInterval(1)) { _ in .found(self.film(5)) }, [5])
        XCTAssertTrue(films.allSatisfy { $0.craft != nil && $0.craftAttempt == nil })
    }

    /// Offline: the run stops after a few films, none of them marked failed (no fault of theirs), and
    /// everything is read once the network is back.
    func testOfflineStopsTheRunAndNoFilmIsBlamed() {
        var films = library()
        let order = run(&films, at: start) { _ in .unreachable }
        XCTAssertEqual(order.count, CraftRun.offlineAfter)
        XCTAssertTrue(films.allSatisfy { $0.craftAttempt == nil && $0.craft == nil })
        XCTAssertEqual(CraftQueue.due(films, now: start).count, 146, "still due, from what's stored")
        var trigger = ResumeTrigger()
        XCTAssertEqual(trigger.handle(.network(reachable: false), now: start), .none)
        XCTAssertEqual(trigger.handle(.network(reachable: true), now: start.addingTimeInterval(600)), .now, "back online: a pass starts")
        XCTAssertEqual(run(&films, at: start.addingTimeInterval(600)) { .found(self.film($0)) }.count, 146)
    }

    /// A site that's down keeps what it said, is read again at its planned time, and its tag stays
    /// until it answers; then the reading is complete.
    func testASiteDownIsReadAgainWhenDueAndKeepsWhatItSaid() {
        var films = library(films: 20, twice: 10)
        run(&films, at: start) { .found(self.film($0, digital: false)) }
        // Six months on, everything is read again; one magazine is down for film 3.
        let later = start.addingTimeInterval(CraftIndex.maxAge + 60)
        XCTAssertEqual(CraftQueue.due(films, now: later).count, 20)
        run(&films, at: later) { id in id == 3 ? .siteDown("Lens Weekly") : .found(self.film(id, digital: false)) }
        let three = films.first { $0.tmdb?.id == 3 }!
        XCTAssertEqual(three.craft?.shotOn, [.film], "what the site said is kept")
        XCTAssertNotNil(three.craft?.evidence(for: .film)?.carriedFrom)
        XCTAssertEqual(CraftQueue.state(of: three, now: later), .partial)
        let retry = three.craft!.retryAt!
        XCTAssertEqual(CraftQueue.nextDue(films, now: later), retry)
        // The app is closed until after the retry is due, then opened: it's read then, and only it.
        let reopened = retry.addingTimeInterval(3 * 86_400)
        XCTAssertEqual(run(&films, at: reopened) { .found(self.film($0, digital: false)) }, [3])
        XCTAssertEqual(CraftQueue.state(of: films.first { $0.tmdb?.id == 3 }!, now: reopened), .complete)
        XCTAssertNil(films.first { $0.tmdb?.id == 3 }!.craft?.evidence(for: .film)?.carriedFrom)
    }

    /// Quitting mid-run: what wasn't written is read again next time (and only that); what was
    /// written isn't.
    func testQuittingMidRunLosesOnlyWhatWasntWritten() {
        var films = library()
        // Quit after 4 films, before the first write (every 9).
        run(&films, at: start, quitAfter: 4) { .found(self.film($0)) }
        XCTAssertEqual(CraftQueue.due(films, now: start).count, 146)
        // Quit after 20 films: the first 10 were written (at the first batch reaching nine).
        let order = run(&films, at: start, quitAfter: 20) { .found(self.film($0)) }
        let written = Set(films.compactMap { $0.craft != nil ? $0.tmdb?.id : nil })
        XCTAssertEqual(written.count, 10)
        XCTAssertTrue(written.isSubset(of: Set(order)))
        let next = run(&films, at: start.addingTimeInterval(60)) { .found(self.film($0)) }
        XCTAssertEqual(next.count, 146 - 10, "the rest, not the films already written")
        XCTAssertTrue(Set(next).isDisjoint(with: written))
        // The app writes what's still waiting when it quits (flush): nothing is read twice then.
        var flushed = library(films: 10, twice: 0)
        var run = CraftRun(now: start)
        for entry in run.nextBatch(flushed, now: start) {
            run.record(entry.tmdb!.id, stored: entry, reading: reading(.found(film(1)), now: start), now: start)
        }
        if let writes = run.takeWrites(now: start, force: true) { CraftRun.apply(read: writes.read, failed: writes.failed, to: &flushed) }
        XCTAssertEqual(CraftQueue.due(flushed, now: start).count, 8)
    }

    /// The queue as stored is the queue after a relaunch: decoding the library gives the same work.
    func testARelaunchFindsTheSameWorkFromWhatsStored() throws {
        var films = library()
        run(&films, at: start, quitAfter: 40) { id in id % 7 == 0 ? .unreachable : .found(self.film(id)) }
        let data = try JSONStore.encode(LibraryFile(films: films))
        guard case .loaded(let reopened) = LibraryOpening.decide(data) else { return XCTFail("not reopened") }
        XCTAssertEqual(reopened.films.count, 266)
        XCTAssertEqual(CraftQueue.due(reopened.films, now: start).map { $0.tmdb?.id }, CraftQueue.due(films, now: start).map { $0.tmdb?.id })
        XCTAssertEqual(CraftQueue.nextDue(reopened.films, now: start), CraftQueue.nextDue(films, now: start))
    }

    /// Fair: never read first, then the longest since tried; a film tried and failed goes behind
    /// the others, so one film can't keep the front of the queue.
    func testTheQueueIsFair() {
        var films = library(films: 6, twice: 0)
        let old = start.addingTimeInterval(-CraftIndex.maxAge - 3 * 86_400)
        for i in films.indices {
            guard let id = films[i].tmdb?.id else { continue }
            if id == 2 { films[i].craft = CraftIndex(readAt: old, shotOn: [], names: [], sources: 2) }
            if id == 4 { films[i].craft = CraftIndex(readAt: old.addingTimeInterval(86_400), shotOn: [], names: [], sources: 2) }
            if id == 6 { films[i].craftAttempt = CraftAttempt(at: start.addingTimeInterval(-30 * 86_400), failures: 3, retryAt: start.addingTimeInterval(-60)) }
        }
        // Never read (1, 3, 5), then the longest since read or tried: 2 and 4 half a year ago, then 6,
        // tried a month ago.
        XCTAssertEqual(CraftQueue.due(films, now: start).compactMap { $0.tmdb?.id }, [1, 3, 5, 2, 4, 6])
        // Each film once per run, even when it fails again at once.
        var run = CraftRun(now: start)
        var seen: [Int] = []
        while case let batch = run.nextBatch(films, now: start), !batch.isEmpty {
            for entry in batch {
                seen.append(entry.tmdb!.id)
                run.record(entry.tmdb!.id, stored: entry, reading: entry.tmdb!.id == 1 ? nil : reading(.nothing, now: start), now: start)
            }
        }
        XCTAssertEqual(seen.count, 6)
        XCTAssertEqual(Set(seen).count, 6)
    }

    /// Launched while offline: the very first report (before the library is open) is noted, so the
    /// network's return starts a pass.
    func testLaunchedOfflineTheNetworksReturnStartsAPass() {
        var trigger = ResumeTrigger()
        XCTAssertEqual(trigger.handle(.network(reachable: false), now: start), .none)
        XCTAssertTrue(trigger.isOffline)
        XCTAssertEqual(trigger.handle(.network(reachable: true), now: start.addingTimeInterval(300)), .now)
        // Launched online: the first report starts nothing (launch does its own pass).
        var online = ResumeTrigger()
        XCTAssertEqual(online.handle(.network(reachable: true), now: start), .none)
        XCTAssertEqual(online.handle(.network(reachable: true), now: start.addingTimeInterval(10)), .none, "no change")
    }

    /// Woken: the pass waits for the network to settle; the network dropping and coming back
    /// meanwhile starts it then, once.
    func testAWakeWaitsForTheNetworkAndItsReturnIsntLost() {
        var trigger = ResumeTrigger()
        _ = trigger.handle(.network(reachable: true), now: start)
        XCTAssertEqual(trigger.handle(.wake, now: start), .at(start.addingTimeInterval(ResumeTrigger.settle)))
        XCTAssertEqual(trigger.handle(.network(reachable: false), now: start.addingTimeInterval(1)), .none)
        // Back up before the planned start: now (the app cancels the planned one).
        XCTAssertEqual(trigger.handle(.network(reachable: true), now: start.addingTimeInterval(4)), .now)
        // Down and up again a minute later: not dropped, put off to the end of the gap.
        _ = trigger.handle(.network(reachable: false), now: start.addingTimeInterval(60))
        XCTAssertEqual(trigger.handle(.network(reachable: true), now: start.addingTimeInterval(70)),
                       .at(start.addingTimeInterval(4 + ResumeTrigger.minimumGap)))
        // More signals before then: still the one planned start.
        XCTAssertEqual(trigger.handle(.wake, now: start.addingTimeInterval(80)), .none)
        XCTAssertTrue(trigger.fire(now: start.addingTimeInterval(124)))
        // A wake while the network is known to be gone starts nothing; its return will.
        _ = trigger.handle(.network(reachable: false), now: start.addingTimeInterval(500))
        XCTAssertEqual(trigger.handle(.wake, now: start.addingTimeInterval(600)), .none)
        XCTAssertEqual(trigger.handle(.network(reachable: true), now: start.addingTimeInterval(700)), .now)
        // A planned start that falls due while offline doesn't start.
        var later = ResumeTrigger()
        _ = later.handle(.network(reachable: true), now: start)
        _ = later.handle(.wake, now: start)
        _ = later.handle(.network(reachable: false), now: start.addingTimeInterval(2))
        XCTAssertFalse(later.fire(now: start.addingTimeInterval(10)))
    }

    /// Offline is judged per batch: films come back in any order, and one that was read means the
    /// network is there; when it is offline, no film of the failing run is blamed.
    func testOfflineIsJudgedPerBatch() {
        let films = library(films: 20, twice: 0)
        func outcome(_ pattern: [Bool]) -> CraftRun {
            var run = CraftRun(now: start)
            var results = pattern[...]
            while !run.offline, !results.isEmpty, case let batch = run.nextBatch(films, now: start), !batch.isEmpty {
                for entry in batch {
                    guard let ok = results.popFirst() else { break }
                    run.record(entry.tmdb!.id, stored: entry, reading: ok ? reading(.nothing, now: start) : nil, now: start)
                }
                run.endBatch()
            }
            return run
        }
        // read, failed | failed, failed | failed, failed | failed, read: the sixth failure comes
        // first in its batch and the other film was read: not offline.
        let mixed = outcome([true, false, false, false, false, false, false, true])
        XCTAssertFalse(mixed.offline)
        // read, failed | then six more failures: offline, and none of the seven blamed.
        let down = outcome([true, false, false, false, false, false, false, false])
        XCTAssertTrue(down.offline)
        XCTAssertEqual(down.failed, [:])
        XCTAssertEqual(CraftRun.offlineRetryDelay(1), 300)
        XCTAssertEqual(CraftRun.offlineRetryDelay(9), 3600)
    }

    // MARK: The library file

    func testALibraryThatsThereIsNeverReplacedByAnEmptyOne() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("reel-autonomy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Library.json")
        XCTAssertEqual(LibraryOpening.open(url), .missing)
        XCTAssertTrue(LibraryOpening.open(url).writable)
        // Reel's own: read and written.
        try JSONStore.save(LibraryFile(films: library(films: 3, twice: 1)), to: url)
        guard case .loaded(let file) = LibraryOpening.open(url) else { return XCTFail("not loaded") }
        XCTAssertEqual(file.films.count, 4)
        // Damaged (cut short): set aside by the app, never read as an empty library.
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 2).write(to: url)
        XCTAssertEqual(LibraryOpening.open(url), .damaged)
        XCTAssertEqual(LibraryOpening.open(url).films, [])
        // Can't be opened (here: it's a folder): not written this session.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertEqual(LibraryOpening.open(url), .unopenable)
        XCTAssertFalse(LibraryOpening.open(url).writable)
    }

    func testANewerReelsLibraryIsReadButNotWrittenOver() throws {
        var file = LibraryFile(films: library(films: 2, twice: 0))
        file.version = LibraryFile.currentVersion + 1
        let opening = LibraryOpening.decide(try JSONStore.encode(file))
        guard case .newer(let version, let read) = opening else { return XCTFail("not newer") }
        XCTAssertEqual(version, 4)
        XCTAssertEqual(read?.films.count, 2)
        XCTAssertEqual(opening.films.count, 2)
        XCTAssertFalse(opening.writable)
        // One this Reel can't even read.
        let unknown = Data(#"{"version": 9, "films": [{"shape": "new"}]}"#.utf8)
        XCTAssertEqual(LibraryOpening.decide(unknown), .newer(version: 9, nil))
        XCTAssertFalse(LibraryOpening.decide(unknown).writable)
        XCTAssertEqual(LibraryOpening.decide(Data("not json".utf8)), .damaged)
    }
}
