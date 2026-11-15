import XCTest
@testable import ReelCore

/// What the library keeps doing on its own, kept from earlier releases' tests when the Shot on
/// reader was removed (1.11): background work resumes when the network comes back or the Mac
/// wakes, a library file is never replaced by an empty one or written over by an older Reel, and a
/// download in progress is never a film.
final class LibraryKeepingTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

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

    // MARK: Resuming background work

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
        XCTAssertEqual(version, LibraryFile.currentVersion + 1)
        XCTAssertEqual(read?.films.count, 2)
        XCTAssertEqual(opening.films.count, 2)
        XCTAssertFalse(opening.writable)
        // One this Reel can't even read.
        let unknown = Data(#"{"version": 9, "films": [{"shape": "new"}]}"#.utf8)
        XCTAssertEqual(LibraryOpening.decide(unknown), .newer(version: 9, nil))
        XCTAssertFalse(LibraryOpening.decide(unknown).writable)
        XCTAssertEqual(LibraryOpening.decide(Data("not json".utf8)), .damaged)
    }

    // MARK: Downloads in progress

    func entry(_ name: String, drive: String = "Main", tmdb: Int? = 7) -> FilmEntry {
        var film = FilmEntry(driveID: drive, relativePath: "Films/" + name, fileName: name, size: 4_000_000_000, modified: nil, addedAt: Date())
        if let tmdb { film.tmdb = TMDBMovieDetails(id: tmdb, title: "Pig") }
        return film
    }

    func scanned(_ name: String) -> ScannedFile { ScannedFile(relativePath: "Films/" + name, fileName: name, size: 4_000_000_000, modified: nil) }

    func testADownloadRecordIsDroppedOnlyByACompleteScan() {
        let partial = entry("Pig.2021.1080p.mkv.crdownload")
        let other = entry("Pig.2021.1080p.mkv", drive: "Backup")
        let neighbour = entry("Quiet.Harbour.2022.mkv", tmdb: 8)
        let library = [partial, other, neighbour]
        // A complete scan that no longer lists it (or still lists it): Reel's record of it goes.
        for files in [[scanned("Quiet.Harbour.2022.mkv")], [scanned("Quiet.Harbour.2022.mkv"), scanned("Pig.2021.1080p.mkv.crdownload")]] {
            let scan = DriveScan(files: files)
            XCTAssertEqual(ScanVerdict.of(scan, driveID: "Main", known: library, driveStillThere: true), .apply)
            let after = LibraryMerge.apply(scan: scan.files, driveID: "Main", to: library, now: Date())
            XCTAssertFalse(after.contains { $0.fileName.hasSuffix(".crdownload") })
            XCTAssertTrue(after.contains { $0.fileName == "Pig.2021.1080p.mkv" && $0.driveID == "Backup" }, "the film's other copy stays")
        }
        // An incomplete scan keeps everything it didn't see, the record included.
        let unreadable = DriveScan(files: [scanned("Quiet.Harbour.2022.mkv")], unreadable: ["Films"])
        XCTAssertEqual(ScanVerdict.of(unreadable, driveID: "Main", known: library, driveStillThere: true), .keepUnseen(unreadable: ["Films"]))
        let kept = LibraryMerge.apply(scan: unreadable.files, driveID: "Main", to: library, now: Date(), keepingUnseen: true)
        XCTAssertTrue(kept.contains { $0.fileName.hasSuffix(".crdownload") })
        // A drive gone or a cancelled scan uses nothing.
        XCTAssertEqual(ScanVerdict.of(DriveScan(files: []), driveID: "Main", known: library, driveStillThere: false), .discard(.driveGone))
        XCTAssertEqual(ScanVerdict.of(DriveScan(files: [], cancelled: true), driveID: "Main", known: library, driveStillThere: true), .discard(.cancelled))
    }

    func testAFinishedDownloadBecomesANewCopyAndAPartFileIsNeverAdded() {
        let partial = entry("Quiet.Harbour.2022.mkv.part")
        let after = LibraryMerge.apply(scan: [scanned("Quiet.Harbour.2022.mkv"), scanned("Other.2020.mkv.part")], driveID: "Main",
                                       to: [partial], now: Date())
        XCTAssertEqual(after.map(\.fileName), ["Quiet.Harbour.2022.mkv"], "the finished file, as a new copy to match")
        XCTAssertEqual(after.first?.matchState, .pending)
        // Completed videos keep their records as ever.
        let done = entry("Quiet.Harbour.2022.mkv")
        XCTAssertEqual(LibraryMerge.apply(scan: [scanned("Quiet.Harbour.2022.mkv")], driveID: "Main", to: [done], now: Date()).first?.tmdb?.id, 7)
        XCTAssertTrue(LibraryMerge.isIncompleteDownload("a.mkv.crdownload"))
        XCTAssertTrue(LibraryMerge.isIncompleteDownload("a.mkv.part"))
        XCTAssertFalse(LibraryMerge.isIncompleteDownload("a.mkv"))
    }
}
