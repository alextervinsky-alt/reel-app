import XCTest
@testable import ReelCore

final class LibraryTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("reel-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeFile(_ relative: String, bytes: Int = 10) throws {
        let url = dir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0, count: bytes).write(to: url)
    }

    // MARK: Scanner

    func testScannerListsOnlyFilms() throws {
        try makeFile("A (2001) 1080p.mkv", bytes: 42)
        try makeFile("sub/B 2002 720p.mp4")
        try makeFile("poster.jpg")
        try makeFile(".hidden.mkv")
        try makeFile("sample.mkv")
        try makeFile("C (2003).mkv.part")
        try makeFile("Extras/Making of.mkv")
        try makeFile("$RECYCLE.BIN/Old (1999).mkv")

        let files = DriveScanner.scan(root: dir, minimumSize: 0)
        XCTAssertEqual(files.map { $0.relativePath }, ["A (2001) 1080p.mkv", "C (2003).mkv.part", "sub/B 2002 720p.mp4"])
        XCTAssertEqual(files.first?.size, 42)
        XCTAssertEqual(files.last?.fileName, "B 2002 720p.mp4")
    }

    func testScannerReportsProgress() throws {
        for i in 0..<260 { try makeFile("Folder/file \(i).txt") }
        var reported: [Int] = []
        _ = DriveScanner.scan(root: dir, minimumSize: 0) { reported.append($0) }
        XCTAssertEqual(reported, [250], "told every 250 files read")
    }

    func testScannerSkipsSmallFiles() throws {
        try makeFile("Big (2001).mkv", bytes: 2_000)
        try makeFile("Trailer (2001).mkv", bytes: 10)
        let files = DriveScanner.scan(root: dir, minimumSize: 1_000)
        XCTAssertEqual(files.map { $0.fileName }, ["Big (2001).mkv"])
    }

    // MARK: Library

    func testMergeKeepsMatchesAndRelinksMovedFiles() {
        let now = Date()
        var matched = FilmEntry(driveID: "D", relativePath: "old/Dredd 2012.mkv", fileName: "Dredd 2012.mkv",
                                size: 100, modified: nil, addedAt: now)
        matched.matchState = .confirmed
        matched.tmdb = TMDBMovieDetails(id: 49049, title: "Dredd")
        let gone = FilmEntry(driveID: "D", relativePath: "Gone.mkv", fileName: "Gone.mkv", size: 5, modified: nil, addedAt: now)
        let otherDrive = FilmEntry(driveID: "E", relativePath: "X.mkv", fileName: "X.mkv", size: 1, modified: nil, addedAt: now)

        let scan = [
            ScannedFile(relativePath: "new/Dredd 2012.mkv", fileName: "Dredd 2012.mkv", size: 100, modified: nil),
            ScannedFile(relativePath: "Fresh (2020).mkv", fileName: "Fresh (2020).mkv", size: 7, modified: nil),
        ]
        let result = LibraryMerge.apply(scan: scan, driveID: "D", to: [matched, gone, otherDrive], now: now)

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.contains(otherDrive))
        let moved = result.first { $0.relativePath == "new/Dredd 2012.mkv" }
        XCTAssertEqual(moved?.tmdb?.id, 49049)
        XCTAssertEqual(moved?.matchState, .confirmed)
        XCTAssertEqual(moved?.id, "D|new/Dredd 2012.mkv")
        XCTAssertEqual(result.first { $0.fileName == "Fresh (2020).mkv" }?.matchState, .pending)
        XCTAssertNil(result.first { $0.fileName == "Gone.mkv" })
    }

    func testFilmEntryRoundTripRebuildsParsedName() throws {
        var entry = FilmEntry(driveID: "D", relativePath: "Dredd 2012 1080p.mkv", fileName: "Dredd 2012 1080p.mkv",
                              size: 1, modified: nil, addedAt: Date(timeIntervalSince1970: 1_000_000))
        entry.matchState = .auto
        let library = LibraryFile(films: [entry])
        let url = dir.appendingPathComponent("Library.json")
        try JSONStore.save(library, to: url)
        let loaded = try XCTUnwrap(JSONStore.load(LibraryFile.self, from: url))
        XCTAssertEqual(loaded, library)
        XCTAssertEqual(loaded.films[0].parsed.title, "Dredd")
        XCTAssertEqual(loaded.films[0].id, "D|Dredd 2012 1080p.mkv")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("\"parsed\""))
    }

    // MARK: Storage

    func testStoreRoundTripAndSafetyCopies() throws {
        let file = dir.appendingPathComponent("Your Notes.json")
        var personal = PersonalFile()
        personal.records["tmdb:1"] = PersonalRecord(watched: true, favorite: true, note: "Rewatch with friends")
        try JSONStore.save(personal, to: file)
        XCTAssertEqual(JSONStore.load(PersonalFile.self, from: file), personal)

        let backups = dir.appendingPathComponent("Safety Copies")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: backups.appendingPathComponent("Your Notes 2000-01-01.json"))

        SafetyCopies.make(of: file, into: backups)
        SafetyCopies.make(of: file, into: backups)
        let names = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertEqual(names.count, 1)
        XCTAssertTrue(names[0].hasPrefix("Your Notes 20"))
        XCTAssertFalse(names.contains("Your Notes 2000-01-01.json"))
    }

    func testCacheTrimRemovesOldestFirst() throws {
        let cache = dir.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for i in 0..<5 {
            let url = cache.appendingPathComponent("img\(i).jpg")
            try Data(repeating: 1, count: 100).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(1_000 * (i + 1)))], ofItemAtPath: url.path)
        }
        XCTAssertEqual(CacheMaintenance.size(of: cache), 500)
        XCTAssertEqual(CacheMaintenance.trim(cache, limit: 1_000, target: 200), 0)
        XCTAssertEqual(CacheMaintenance.trim(cache, limit: 400, target: 200), 3)
        let left = try FileManager.default.contentsOfDirectory(atPath: cache.path).sorted()
        XCTAssertEqual(left, ["img3.jpg", "img4.jpg"])
        CacheMaintenance.clear(cache)
        XCTAssertEqual(CacheMaintenance.size(of: cache), 0)
    }

    func testOlderFilesStillLoad() throws {
        // Reel 0.3 kept drives in Library.json and wrote notes without corrections.
        let oldLibrary = """
        {"version": 2, "drives": [{"id": "D", "name": "Main", "volumeUUID": "ABC", "folderInVolume": "", "lastKnownPath": "/Volumes/Main"}],
         "films": []}
        """
        let library = try JSONDecoder().decode(LibraryFile.self, from: Data(oldLibrary.utf8))
        XCTAssertEqual(library.drives?.first?.name, "Main")

        let oldNotes = #"{"version": 1, "records": {"tmdb:1": {"watched": true, "favorite": false, "watchlist": false, "note": ""}}}"#
        let notes = try JSONDecoder().decode(PersonalFile.self, from: Data(oldNotes.utf8))
        XCTAssertEqual(notes.records["tmdb:1"]?.watched, true)
        XCTAssertEqual(notes.corrections, [:])

        let oldSettings = #"{"tmdbToken": "x"}"#
        let settings = try JSONDecoder().decode(ReelSettings.self, from: Data(oldSettings.utf8))
        XCTAssertEqual(settings.tmdbToken, "x")
        XCTAssertEqual(settings.drives, [])
    }

    func testSettingsArePrivate() throws {
        let url = dir.appendingPathComponent("Settings.json")
        try JSONStore.save(ReelSettings(tmdbToken: "t"), to: url, permissions: 0o600)
        try JSONStore.save(ReelSettings(tmdbToken: "u"), to: url, permissions: 0o600)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        XCTAssertEqual(JSONStore.load(ReelSettings.self, from: url)?.tmdbToken, "u")
    }

    func testUnreferencedCacheFilesAreRemoved() throws {
        let cache = dir.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let old = Date(timeIntervalSince1970: 1_000)
        for name in ["keep.jpg", "orphan.jpg", ".tmp-download"] {
            let url = cache.appendingPathComponent(name)
            try Data([1, 2, 3]).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        }
        try Data([1]).write(to: cache.appendingPathComponent("fresh.jpg"))
        let removed = CacheMaintenance.removeUnreferenced(in: cache, keep: ["keep.jpg"], olderThan: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(removed, 2)
        let left = try FileManager.default.contentsOfDirectory(atPath: cache.path).sorted()
        XCTAssertEqual(left, ["fresh.jpg", "keep.jpg"])
    }

    func testWriterRunsInOrderAndFlushes() {
        let writer = FileWriter()
        let url = dir.appendingPathComponent("order.json")
        for i in 0..<20 {
            writer.enqueue { try? JSONStore.save(["n": i], to: url) }
        }
        writer.flush()
        XCTAssertEqual(JSONStore.load([String: Int].self, from: url), ["n": 19])
    }

    func testMergingRecordsKeepsEverything() {
        let a = PersonalRecord(watched: false, favorite: true, watchlist: true, rating: nil, note: "From Mari")
        let b = PersonalRecord(watched: true, favorite: false, watchlist: false, rating: 4, note: "Great sound")
        let m = a.merged(with: b)
        XCTAssertTrue(m.watched)
        XCTAssertTrue(m.favorite)
        XCTAssertFalse(m.watchlist)
        XCTAssertEqual(m.rating, 4)
        XCTAssertEqual(m.note, "From Mari\n\nGreat sound")
        XCTAssertEqual(a.merged(with: a).note, "From Mari")
    }

    func testFolderLayout() {
        let folder = ReelFolder(root: dir)
        folder.prepare()
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.imageCache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.about.path))
        XCTAssertEqual(folder.notes.lastPathComponent, "Your Notes.json")
    }
}
