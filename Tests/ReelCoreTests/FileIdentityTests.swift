import XCTest
@testable import ReelCore

/// A file is its name plus its size: one film's match, fix or notes never pass to another file
/// that only shares its name.
final class FileIdentityTests: XCTestCase {
    private func file(_ path: String, size: Int64, drive: String = "Main", tmdb: Int? = nil) -> FilmEntry {
        var entry = FilmEntry(driveID: drive, relativePath: path, fileName: (path as NSString).lastPathComponent,
                              size: size, modified: nil, addedAt: Date())
        if let tmdb { entry.tmdb = TMDBMovieDetails(id: tmdb, title: path) }
        return entry
    }

    // MARK: Identity

    func testGenericNamesOfDifferentSizesAreDifferentFiles() {
        let heat = file("Heat/title_t00.mkv", size: 30_000_000_000)
        let ran = file("Ran/title_t00.mkv", size: 25_000_000_000)
        XCTAssertNotEqual(heat.fileKey, ran.fileKey)
        XCTAssertNotEqual(heat.personalKey, ran.personalKey, "their notes are kept apart")
        XCTAssertEqual(heat.personalKey, "file:title_t00.mkv|30000000000")
    }

    func testSameNameAndSizeIsTheSameFile() {
        let main = file("Heat/Heat (1995).mkv", size: 30_000)
        let backup = file("Films/Heat (1995).mkv", size: 30_000, drive: "Backup")
        XCTAssertEqual(main.fileKey, backup.fileKey, "a copy on the Backup is the same file")
        XCTAssertEqual(main.personalKey, backup.personalKey)
    }

    func testIdentifiedFilmsKeepTheirTMDBKey() {
        XCTAssertEqual(file("A.mkv", size: 1, tmdb: 49049).personalKey, "tmdb:49049", "unchanged for every identified film")
    }

    func testUnidentifiedSameNameFilesAreNotGroupedAsOneFilm() {
        let films = [file("Heat/title_t00.mkv", size: 3_000), file("Ran/title_t00.mkv", size: 2_000)]
        let groups = Dictionary(grouping: films, by: \.personalKey)
        XCTAssertEqual(groups.count, 2)
    }

    func testMovedFileKeepsItsIdentity() {
        let before = file("Old/title_t00.mkv", size: 3_000, tmdb: 1)
        let after = LibraryMerge.apply(scan: [ScannedFile(relativePath: "New/title_t00.mkv", fileName: "title_t00.mkv", size: 3_000, modified: nil)],
                                       driveID: "Main", to: [before], now: Date())
        XCTAssertEqual(after.first?.tmdb?.id, 1)
        XCTAssertEqual(after.first?.fileKey, before.fileKey)
    }

    func testSizeIsReadFromTheKey() {
        XCTAssertTrue(FileIdentity.hasSize("title_t00.mkv|3000"))
        XCTAssertFalse(FileIdentity.hasSize("title_t00.mkv"))
        XCTAssertFalse(FileIdentity.hasSize("Odd|name.mkv"))
        XCTAssertFalse(FileIdentity.hasSize("Ends with bar|"))
    }

    // MARK: Fixes

    func testFixSavedWithSizeAppliesToThatFileOnly() {
        let heat = file("Heat/title_t00.mkv", size: 3_000)
        let ran = file("Ran/title_t00.mkv", size: 2_000)
        let fixes = [heat.fileKey: 949]
        XCTAssertEqual(FileIdentity.fix(for: heat, corrections: fixes, library: [heat, ran]), .film(949))
        XCTAssertEqual(FileIdentity.fix(for: ran, corrections: fixes, library: [heat, ran]), FileIdentity.Fix.none)
    }

    func testOldFixForOneFileStillApplies() {
        let main = file("Heat (1995).mkv", size: 30_000)
        let backup = file("Heat (1995).mkv", size: 30_000, drive: "Backup")
        let fixes = ["Heat (1995).mkv": 949]
        XCTAssertEqual(FileIdentity.fix(for: main, corrections: fixes, library: [main, backup]), .film(949),
                       "one size (a file and its copy): the old fix can only mean this file")
    }

    func testOldFixForSeveralFilesIsNotApplied() {
        let heat = file("Heat/title_t00.mkv", size: 3_000)
        let ran = file("Ran/title_t00.mkv", size: 2_000)
        let fixes = ["title_t00.mkv": 949]
        XCTAssertEqual(FileIdentity.fix(for: heat, corrections: fixes, library: [heat, ran]), .ambiguous)
        XCTAssertEqual(FileIdentity.fix(for: ran, corrections: fixes, library: [heat, ran]), .ambiguous)
    }

    func testFixWithSizeWinsOverOldOne() {
        let heat = file("Heat/title_t00.mkv", size: 3_000)
        let fixes = ["title_t00.mkv": 1, heat.fileKey: 949]
        XCTAssertEqual(FileIdentity.fix(for: heat, corrections: fixes, library: [heat]), .film(949))
    }

    // MARK: Upgrading what was saved before

    func testUpgradeMovesOldFixesOnlyWhenTheyMeanOneFile() {
        let heat = file("Heat (1995).mkv", size: 30_000)
        let heatCopy = file("Heat (1995).mkv", size: 30_000, drive: "Backup")
        let a = file("A/title_t00.mkv", size: 3_000)
        let b = file("B/title_t00.mkv", size: 2_000)
        let old = ["Heat (1995).mkv": 949, "title_t00.mkv": 11, "Gone.mkv.crdownload": 5]
        let upgrade = FileIdentity.upgrade(corrections: old, noteKeys: [], library: [heat, heatCopy, a, b])
        XCTAssertEqual(upgrade.corrections, ["Heat (1995).mkv|30000": 949, "title_t00.mkv": 11, "Gone.mkv.crdownload": 5],
                       "one file: moved; two different files: left as it was; no file now: left as it was")
        XCTAssertEqual(upgrade.ambiguous, ["title_t00.mkv"])
    }

    func testUpgradeKeepsANewerFixWithSize() {
        let heat = file("Heat (1995).mkv", size: 30_000)
        let upgrade = FileIdentity.upgrade(corrections: ["Heat (1995).mkv": 1, "Heat (1995).mkv|30000": 949], noteKeys: [], library: [heat])
        XCTAssertEqual(upgrade.corrections, ["Heat (1995).mkv|30000": 949])
    }

    func testUpgradeMovesOldNotesOnlyWhenTheyMeanOneFile() {
        let heat = file("Heat/Unknown film.mkv", size: 3_000)
        let a = file("A/title_t00.mkv", size: 3_000)
        let b = file("B/title_t00.mkv", size: 2_000)
        let upgrade = FileIdentity.upgrade(corrections: [:],
                                           noteKeys: ["file:Unknown film.mkv", "file:title_t00.mkv", "file:Gone.mkv", "tmdb:1",
                                                      "file:Already.mkv|10"],
                                           library: [heat, a, b])
        XCTAssertEqual(upgrade.notes.map(\.from), ["file:Unknown film.mkv"])
        XCTAssertEqual(upgrade.notes.map(\.to), ["file:Unknown film.mkv|3000"])
        XCTAssertEqual(upgrade.ambiguous, ["title_t00.mkv"])
    }

    func testUpgradingTwiceChangesNothing() {
        let heat = file("Heat (1995).mkv", size: 30_000)
        let first = FileIdentity.upgrade(corrections: ["Heat (1995).mkv": 949], noteKeys: [], library: [heat])
        let second = FileIdentity.upgrade(corrections: first.corrections, noteKeys: [], library: [heat])
        XCTAssertEqual(second.corrections, first.corrections)
        XCTAssertTrue(second.notes.isEmpty)
    }

    /// The fixes in Reel 1.8.7's notes (shape of a real file): specific names, some saved again
    /// for the unfinished download of the same film.
    func testReleaseNamesUpgradeCleanly() {
        let dune = file("Dune Part One (2021) 2160p.mkv", size: 80_000)
        let old = ["Dune Part One (2021) 2160p.mkv": 438631, "Dune Part One (2021) 2160p.mkv.crdownload": 438631]
        let upgrade = FileIdentity.upgrade(corrections: old, noteKeys: [], library: [dune])
        XCTAssertEqual(upgrade.corrections, ["Dune Part One (2021) 2160p.mkv|80000": 438631,
                                             "Dune Part One (2021) 2160p.mkv.crdownload": 438631])
        XCTAssertTrue(upgrade.ambiguous.isEmpty)
    }
}
