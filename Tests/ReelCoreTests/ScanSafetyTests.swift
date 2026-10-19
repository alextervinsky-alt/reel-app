import XCTest
@testable import ReelCore

/// A scan only removes films when it read the whole drive while the drive stayed connected.
final class ScanSafetyTests: XCTestCase {
    private let now = Date()

    private func film(_ path: String, size: Int64 = 1_000, drive: String = "D", tmdb: Int? = nil) -> FilmEntry {
        var entry = FilmEntry(driveID: drive, relativePath: path, fileName: (path as NSString).lastPathComponent,
                              size: size, modified: nil, addedAt: now.addingTimeInterval(-90 * 86_400))
        if let tmdb {
            entry.tmdb = TMDBMovieDetails(id: tmdb, title: path)
            entry.matchState = .confirmed
        }
        return entry
    }

    private func seen(_ films: [FilmEntry]) -> [ScannedFile] {
        films.map { ScannedFile(relativePath: $0.relativePath, fileName: $0.fileName, size: $0.size, modified: nil) }
    }

    private func file(_ path: String, size: Int64 = 1_000) -> DriveScanner.Entry {
        .file(FilmGrouping.File(relativePath: path, size: size, modified: nil))
    }

    // MARK: What the listing reports

    func testUnreadableFoldersAndFilesAreReported() {
        let scan = DriveScanner.collect([file("A (2001).mkv"), .unreadable("Locked"), file("B (2002).mkv"),
                                         .unreadable("Other/C (2003).mkv")], minimumSize: 0)
        XCTAssertEqual(scan.files.map(\.fileName), ["A (2001).mkv", "B (2002).mkv"])
        XCTAssertEqual(scan.unreadable, ["Locked", "Other/C (2003).mkv"])
        XCTAssertFalse(scan.cancelled)
        XCTAssertFalse(scan.isComplete)
    }

    func testCancelledListingStopsAndSaysSo() {
        var asked = 0
        let scan = DriveScanner.collect([file("A (2001).mkv"), file("B (2002).mkv"), file("C (2003).mkv")], minimumSize: 0,
                                        isCancelled: { asked += 1; return asked > 1 })
        XCTAssertTrue(scan.cancelled)
        XCTAssertEqual(scan.files.map(\.fileName), ["A (2001).mkv"])
        XCTAssertFalse(scan.isComplete)
    }

    func testCompleteListingOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reel-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        try Data(count: 10).write(to: dir.appendingPathComponent("Sub/Film (2001).mkv"))
        let scan = DriveScanner.scan(root: dir, minimumSize: 0)
        XCTAssertEqual(scan.files.map(\.relativePath), ["Sub/Film (2001).mkv"])
        XCTAssertTrue(scan.isComplete)
    }

    /// A folder the system won't open is reported, not passed over. (Root ignores permissions,
    /// so this one only runs as an ordinary user; the error path itself is covered above.)
    func testLockedFolderOnDisk() throws {
        try XCTSkipIf(getuid() == 0, "running as root: permissions don't apply")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reel-scan-\(UUID().uuidString)")
        let locked = dir.appendingPathComponent("Locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(count: 10).write(to: locked.appendingPathComponent("Hidden Away (2001).mkv"))
        try Data(count: 10).write(to: dir.appendingPathComponent("Open (2002).mkv"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let scan = DriveScanner.scan(root: dir, minimumSize: 0)
        XCTAssertEqual(scan.files.map(\.fileName), ["Open (2002).mkv"])
        XCTAssertEqual(scan.unreadable, ["Locked"])
    }

    // MARK: What a scan may change

    func testPartialScanRemovesNothing() {
        let films = [film("A/A (2001).mkv", tmdb: 1), film("B/B (2002).mkv", tmdb: 2), film("Locked/C (2003).mkv", tmdb: 3)]
        let scan = DriveScan(files: seen(Array(films.prefix(2))), unreadable: ["Locked"])
        let verdict = ScanVerdict.of(scan, driveID: "D", known: films, driveStillThere: true)
        XCTAssertEqual(verdict, .keepUnseen(unreadable: ["Locked"]))
        let after = LibraryMerge.apply(scan: scan.files, driveID: "D", to: films, now: now, keepingUnseen: true)
        XCTAssertEqual(Set(after.map(\.id)), Set(films.map(\.id)), "the film in the unreadable folder stays")
        XCTAssertEqual(after.first { $0.relativePath == "Locked/C (2003).mkv" }, films[2], "exactly as it was")
    }

    func testPartialScanStillAddsNewAndMovedFilms() {
        let films = [film("Old/A (2001).mkv", tmdb: 1), film("Locked/C (2003).mkv", tmdb: 3)]
        let found = [ScannedFile(relativePath: "New/A (2001).mkv", fileName: "A (2001).mkv", size: 1_000, modified: nil),
                     ScannedFile(relativePath: "D (2004).mkv", fileName: "D (2004).mkv", size: 5, modified: nil)]
        let after = LibraryMerge.apply(scan: found, driveID: "D", to: films, now: now, keepingUnseen: true)
        XCTAssertEqual(after.first { $0.fileName == "A (2001).mkv" }?.relativePath, "New/A (2001).mkv", "moved keeps its match")
        XCTAssertEqual(after.first { $0.fileName == "A (2001).mkv" }?.tmdb?.id, 1)
        XCTAssertEqual(after.first { $0.fileName == "D (2004).mkv" }?.matchState, .pending)
        XCTAssertNotNil(after.first { $0.relativePath == "Locked/C (2003).mkv" })
        XCTAssertEqual(after.count, 3)
    }

    func testPartialScanDoesNotMakeKeptFilmsNew() {
        let films = [film("A (2001).mkv"), film("Locked/C (2003).mkv")]
        let after = LibraryMerge.apply(scan: seen([films[0]]), driveID: "D", to: films, now: now, keepingUnseen: true)
        XCTAssertTrue(after.allSatisfy { $0.addedAt < now }, "nothing is dated now, so nothing shows in New Arrivals")
    }

    func testCancelledScanIsNotUsed() {
        let films = [film("A (2001).mkv"), film("B (2002).mkv")]
        let scan = DriveScan(files: seen([films[0]]), cancelled: true)
        XCTAssertEqual(ScanVerdict.of(scan, driveID: "D", known: films, driveStillThere: true), .discard(.cancelled))
    }

    func testDisconnectedDriveIsNotUsed() {
        let films = [film("A (2001).mkv"), film("B (2002).mkv")]
        let scan = DriveScan(files: seen([films[0]]))
        XCTAssertEqual(ScanVerdict.of(scan, driveID: "D", known: films, driveStillThere: false), .discard(.driveGone))
    }

    func testNothingSeenIsNotUsed() {
        let films = [film("A (2001).mkv")]
        XCTAssertEqual(ScanVerdict.of(DriveScan(files: []), driveID: "D", known: films, driveStillThere: true), .discard(.nothingSeen))
        XCTAssertEqual(ScanVerdict.of(DriveScan(files: []), driveID: "D", known: [], driveStillThere: true), .apply,
                       "an empty new drive is simply empty")
    }

    func testCompleteScanRemovesWhatIsReallyGone() {
        let films = (1...20).map { film("F\($0) (2001).mkv") } + [film("Other (2001).mkv", drive: "E")]
        let scan = DriveScan(files: seen(Array(films.prefix(19))))
        XCTAssertEqual(ScanVerdict.of(scan, driveID: "D", known: films, driveStillThere: true), .apply)
        let after = LibraryMerge.apply(scan: scan.files, driveID: "D", to: films, now: now)
        XCTAssertNil(after.first { $0.fileName == "F20 (2001).mkv" })
        XCTAssertNotNil(after.first { $0.driveID == "E" }, "other drives are untouched")
        XCTAssertEqual(after.count, 20)
    }

    func testMovedFilesAreNotCountedAsRemoved() {
        let films = (1...20).map { film("Old/F\($0) (2001).mkv") }
        let moved = films.map { ScannedFile(relativePath: "New/" + $0.fileName, fileName: $0.fileName, size: $0.size, modified: nil) }
        XCTAssertEqual(ScanVerdict.of(DriveScan(files: moved), driveID: "D", known: films, driveStillThere: true), .apply,
                       "a reorganised drive isn't a mass removal")
    }

    func testRemovingManyFilmsAsksFirst() {
        let films = (1...40).map { film("F\($0) (2001).mkv") }
        let scan = DriveScan(files: seen(Array(films.prefix(28))))
        XCTAssertEqual(ScanVerdict.of(scan, driveID: "D", known: films, driveStillThere: true), .confirmRemovals(count: 12))
        let few = DriveScan(files: seen(Array(films.prefix(31))))
        XCTAssertEqual(ScanVerdict.of(few, driveID: "D", known: films, driveStillThere: true), .apply, "9 films: under the count")
        let small = (1...12).map { film("S\($0) (2001).mkv") }
        XCTAssertEqual(ScanVerdict.of(DriveScan(files: seen([small[0]])), driveID: "D", known: small, driveStillThere: true),
                       .confirmRemovals(count: 11))
    }

    func testNextCompleteScanRecovers() {
        let films = [film("A (2001).mkv", tmdb: 1), film("Locked/B (2002).mkv", tmdb: 2), film("Locked/C (2003).mkv", tmdb: 3)]
        // First a partial scan: the locked folder couldn't be read.
        let partial = LibraryMerge.apply(scan: seen([films[0]]), driveID: "D", to: films, now: now, keepingUnseen: true)
        XCTAssertEqual(partial.count, 3)
        // Then the folder reads again, and C was really deleted meanwhile.
        let complete = DriveScan(files: seen([films[0], films[1]]))
        XCTAssertEqual(ScanVerdict.of(complete, driveID: "D", known: partial, driveStillThere: true), .apply)
        let after = LibraryMerge.apply(scan: complete.files, driveID: "D", to: partial, now: now)
        XCTAssertEqual(after.map(\.relativePath).sorted(), ["A (2001).mkv", "Locked/B (2002).mkv"])
        XCTAssertEqual(after.first { $0.relativePath == "Locked/B (2002).mkv" }?.tmdb?.id, 2, "B kept its match throughout")
    }
}
