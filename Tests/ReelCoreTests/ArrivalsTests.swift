import XCTest
@testable import ReelCore

final class ArrivalsTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: New arrivals

    func testOnlyFilmsFoundAfterTheDriveBaselineAreNew() {
        let since = now.addingTimeInterval(-30 * day)
        let fresh = Arrivals.Copy(addedAt: now.addingTimeInterval(-3 * day), since: since)
        XCTAssertEqual(Arrivals.arrival(of: [fresh], now: now), fresh.addedAt)

        // Found by the drive's first scan, or before 1.0: never new.
        XCTAssertNil(Arrivals.arrival(of: [Arrivals.Copy(addedAt: since, since: since)], now: now))
        XCTAssertNil(Arrivals.arrival(of: [Arrivals.Copy(addedAt: now, since: nil)], now: now))
        // 14 days later it's no longer new.
        XCTAssertNil(Arrivals.arrival(of: [Arrivals.Copy(addedAt: now.addingTimeInterval(-14 * day), since: since)], now: now))
        // Copied to the Backup today, but on Films for months: the earliest copy decides.
        let old = Arrivals.Copy(addedAt: now.addingTimeInterval(-90 * day), since: since.addingTimeInterval(-200 * day))
        XCTAssertNil(Arrivals.arrival(of: [old, fresh], now: now))
        // Made a film by hand: not an arrival.
        XCTAssertNil(Arrivals.arrival(of: [Arrivals.Copy(addedAt: fresh.addedAt, since: since, regrouped: true)], now: now))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(Arrivals.label(now, now: now, calendar: calendar), "Added today")
        XCTAssertEqual(Arrivals.label(now.addingTimeInterval(-day), now: now, calendar: calendar), "Added yesterday")
        XCTAssertEqual(Arrivals.label(now.addingTimeInterval(-3 * day), now: now, calendar: calendar), "Added 3 days ago")
    }

    func testOlderDrivesDecodeWithBackupRoleAndNoBaseline() throws {
        let json = #"[{"id": "A", "name": "Films", "volumeUUID": "1", "folderInVolume": "", "lastKnownPath": "/Volumes/Films"},"#
            + #"{"id": "B", "name": "Films (Backup)", "volumeUUID": "2", "folderInVolume": "", "lastKnownPath": "/Volumes/b"}]"#
        let drives = try JSONStore.decode([Drive].self, from: Data(json.utf8))
        XCTAssertEqual(drives.map { $0.isBackup }, [false, true])
        XCTAssertNil(drives[0].arrivalsSince)

        var edited = drives[1]
        edited.isBackup = false
        edited.arrivalsSince = now
        let again = try JSONStore.decode(Drive.self, from: JSONStore.encode(edited))
        XCTAssertFalse(again.isBackup, "a choice made by hand wins over the name")
        XCTAssertEqual(again.arrivalsSince, now)
    }

    // MARK: Wishlist

    func testWishlistFilmsInTheLibraryLeaveTheWishlist() {
        let dune = WishlistFilm(id: 438631, title: "Dune", year: 2021, posterPath: nil, backdropPath: nil)
        let her = WishlistFilm(id: 152601, title: "Her", year: 2013, posterPath: nil, backdropPath: nil)
        let (kept, arrived) = WishlistCleanup.split([dune, her], owned: [438631, 1])
        XCTAssertEqual(kept.map { $0.id }, [152601])
        XCTAssertEqual(arrived.map { $0.id }, [438631])

        let stale = WishlistArrival(id: 7, date: now.addingTimeInterval(-20 * day))
        let recent = WishlistArrival(id: 438631, date: now.addingTimeInterval(-day))
        let recorded = WishlistCleanup.record(arrived + [her], into: [stale, recent], now: now)
        XCTAssertEqual(recorded.map { $0.id }, [438631, 152601], "old arrivals drop off, known ones keep their date")
        XCTAssertEqual(recorded.first?.date, recent.date)
    }

    // MARK: Backup

    func testBackupCheckFindsMissingAndUnfinishedCopies() {
        func entry(_ drive: String, _ path: String, size: Int64, tmdb: Int? = nil) -> FilmEntry {
            var film = FilmEntry(driveID: drive, relativePath: path, fileName: FilenameParser.lastComponent(path),
                                 size: size, modified: nil, addedAt: now)
            if let tmdb { film.tmdb = TMDBMovieDetails(id: tmdb, title: "x") }
            return film
        }
        let films = [
            entry("main", "Dune (2021).mkv", size: 100, tmdb: 1),
            entry("backup", "Films/Dune.2021.mkv", size: 100, tmdb: 1),  // renamed on the mirror: fine
            entry("main", "Her (2013).mkv", size: 50, tmdb: 2),
            entry("backup", "Her (2013).mkv", size: 20, tmdb: 2),        // copy stopped half way
            entry("main", "Rosetta (1999).avi", size: 70, tmdb: 3),      // not on the Backup
            entry("main", "Unknown thing.mkv", size: 9),
            entry("backup", "Unknown thing.mkv", size: 9),               // unmatched, compared by name
        ]
        let gaps = BackupCheck.gaps(in: films, backupDrives: ["backup"])
        XCTAssertEqual(gaps.map { "\($0.key) \($0.problem.rawValue)" }, ["tmdb:2 incomplete", "tmdb:3 missing"])
        XCTAssertTrue(BackupCheck.gaps(in: films, backupDrives: []).isEmpty, "no backup drive, nothing to compare")
        XCTAssertTrue(BackupCheck.gaps(in: films, backupDrives: ["never-scanned"]).isEmpty, "an unscanned backup isn't empty")
        let unrelated = films + [entry("second", "Stalker (1979).mkv", size: 80, tmdb: 9)]
        XCTAssertEqual(BackupCheck.gaps(in: unrelated, backupDrives: ["backup"]).count, 2, "a drive the backup doesn't mirror isn't listed")
    }

    // MARK: Grouping fixes

    func testGroupingFixesSurviveEveryScan() {
        let mb: Int64 = 1_000_000
        let grouped = FilmGrouping.group([
            FilmGrouping.File(relativePath: "Chungking Express (1994)/Chungking Express (1994).mkv", size: 4000 * mb, modified: nil),
            FilmGrouping.File(relativePath: "Chungking Express (1994)/Extras/Wong Kar-wai short.mkv", size: 300 * mb, modified: nil),
            FilmGrouping.File(relativePath: "Fallen Angels (1995).mkv", size: 3000 * mb, modified: nil),
            FilmGrouping.File(relativePath: "Wong Kar-wai Interview (2015).mkv", size: 900 * mb, modified: nil),
        ], minimumSize: 30 * mb)
        XCTAssertEqual(grouped.count, 3)

        var fixes = GroupingFixes()
        fixes.makeFilm("Chungking Express (1994)/Extras/Wong Kar-wai short.mkv")
        fixes.makeExtra("Wong Kar-wai Interview (2015).mkv", of: "Fallen Angels (1995).mkv")
        let fixed = fixes.apply(to: grouped)
        XCTAssertEqual(fixed.map { $0.fileName },
                       ["Chungking Express (1994).mkv", "Wong Kar-wai short.mkv", "Fallen Angels (1995).mkv"])
        XCTAssertTrue(fixed[0].extras.isEmpty)
        XCTAssertEqual(fixed[2].extras.map { $0.fileName }, ["Wong Kar-wai Interview (2015).mkv"])
        XCTAssertEqual(fixed[2].extras.first?.kind, .interview)
        XCTAssertEqual(fixes.apply(to: fixed), fixed, "applying twice changes nothing")

        // A fix for a file that isn't on this drive is skipped; a reset undoes it.
        fixes.makeExtra("Elsewhere.mkv", of: "Fallen Angels (1995).mkv")
        XCTAssertEqual(fixes.apply(to: grouped), fixed)
        fixes.reset("Wong Kar-wai Interview (2015).mkv")
        XCTAssertEqual(fixes.apply(to: grouped).count, 4)
        XCTAssertTrue(fixes.isFixed("Elsewhere.mkv"))

        // Notes from before 1.0 have no fixes.
        let old = try? JSONStore.decode(PersonalFile.self, from: Data(#"{"version": 3, "records": {}}"#.utf8))
        XCTAssertEqual(old?.groupingFixes, GroupingFixes())
    }
}
