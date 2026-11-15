import XCTest
@testable import ReelCore

/// 1.11's rules for your data (spec §3): matches are yours, frame removals are yours, a newer
/// Reel's keys survive, a newer Reel's file isn't written, and a damaged file offers its newest
/// Safety Copy. Synthetic files only.
final class UserDataTests: XCTestCase {
    private func copy(_ name: String, size: Int64, tmdb: Int?, state: MatchState, drive: String = "Main") -> FilmEntry {
        var entry = FilmEntry(driveID: drive, relativePath: "Films/\(name)", fileName: name, size: size, modified: nil, addedAt: Date())
        if let tmdb { entry.tmdb = TMDBMovieDetails(id: tmdb, title: name) }
        entry.matchState = state
        return entry
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reel-userdata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: Matches

    func testARebuiltLibraryKeepsEveryFilmsPersonalData() {
        // 300 copies matched automatically; personal data is kept by the matched film.
        let library = (0..<300).map { copy("Film \($0) (2001).mkv", size: Int64(1_000 + $0), tmdb: 10_000 + $0, state: .auto) }
        let keysBefore = Set(library.map(\.personalKey))
        let matches = MatchMemory.remember(library, into: [:])
        XCTAssertEqual(matches.count, 300)

        // Library.json lost: every copy is pending again, and today's search would rank other films
        // first. A remembered copy is never searched for, so it gets its film back.
        let rebuilt = library.map { copy($0.fileName, size: $0.size, tmdb: nil, state: .pending) }
        let sizes = FileIdentity.sizesByName(rebuilt)
        var restored: [FilmEntry] = []
        for file in rebuilt {
            guard case .remembered(let id, let check) = FileIdentity.fix(for: file, corrections: [:], matches: matches, sizes: sizes) else {
                return XCTFail("\(file.fileName) would be searched for again")
            }
            XCTAssertFalse(check)
            let searchWouldPick = id + 50_000
            XCTAssertNotEqual(id, searchWouldPick)
            restored.append(copy(file.fileName, size: file.size, tmdb: id, state: .auto))
        }
        XCTAssertEqual(Set(restored.map(\.personalKey)), keysBefore, "every note, star and watched date still has its film")
    }

    func testYourFixesWinOverRememberedMatches() {
        let file = copy("Heat.mkv", size: 5, tmdb: nil, state: .pending)
        let matches = [file.fileKey: RememberedMatch(tmdb: 111)]
        XCTAssertEqual(FileIdentity.fix(for: file, corrections: [file.fileKey: 949], matches: matches, sizes: [:]), .film(949))
    }

    func testARememberedMatchTellsSameNamedFilesApart() {
        let heat = copy("title_t00.mkv", size: 30, tmdb: nil, state: .pending)
        let ran = copy("title_t00.mkv", size: 25, tmdb: nil, state: .pending)
        let sizes = FileIdentity.sizesByName([heat, ran])
        let matches = [heat.fileKey: RememberedMatch(tmdb: 949), ran.fileKey: RememberedMatch(tmdb: 11645)]
        // An old fix under the name alone can't tell them apart; what each was matched to can.
        XCTAssertEqual(FileIdentity.fix(for: heat, corrections: ["title_t00.mkv": 949], matches: matches, sizes: sizes),
                       .remembered(949, check: true))
        XCTAssertEqual(FileIdentity.fix(for: ran, corrections: ["title_t00.mkv": 949], matches: matches, sizes: sizes),
                       .remembered(11645, check: true))
        XCTAssertEqual(FileIdentity.fix(for: ran, corrections: ["title_t00.mkv": 949], sizes: sizes), .ambiguous, "as before without one")
    }

    func testWhatIsRemembered() {
        let auto = copy("A.mkv", size: 1, tmdb: 1, state: .auto)
        let check = copy("B.mkv", size: 2, tmdb: 2, state: .review)
        let pending = copy("C.mkv", size: 3, tmdb: nil, state: .pending)
        let failed = copy("D.mkv", size: 4, tmdb: nil, state: .failed)
        let away = RememberedMatch(tmdb: 9)
        let result = MatchMemory.remember([auto, check, pending, failed], into: ["Gone.mkv|7": away, auto.fileKey: RememberedMatch(tmdb: 77)])
        XCTAssertEqual(result[auto.fileKey], RememberedMatch(tmdb: 1), "a film chosen since replaces the old one")
        XCTAssertEqual(result[check.fileKey], RememberedMatch(tmdb: 2, check: true), "a match to check stays one")
        XCTAssertNil(result[pending.fileKey])
        XCTAssertNil(result[failed.fileKey])
        XCTAssertEqual(result["Gone.mkv|7"], away, "a copy on a drive that's away keeps its film")
        XCTAssertEqual(MatchMemory.remember([auto, check], into: result), result, "running it again changes nothing")
    }

    // MARK: What a newer Reel wrote

    func testKeysThisReelDoesNotKnowSurviveASave() throws {
        let json = #"""
        {"version": 5, "records": {"tmdb:949": {"watched": true}}, "corrections": {}, "wishlist": [], "wishlistArrivals": [],
         "removedShotOn": {"949": ["film", "vistaVision"]},
         "futureLists": [{"name": "Rainy days", "films": [949, 11645], "pinned": true, "score": 0.5, "note": null}]}
        """#
        var notes = try JSONDecoder().decode(PersonalFile.self, from: Data(json.utf8))
        XCTAssertEqual(notes.removedShotOn[949], [.film])
        // A change, as the app makes one, then a save and a read.
        notes.records["tmdb:11645"] = PersonalRecord(favorite: true)
        let saved = try JSONEncoder().encode(notes)
        let again = try JSONDecoder().decode(PersonalFile.self, from: saved)
        XCTAssertEqual(again.passthrough.keys["futureLists"], notes.passthrough.keys["futureLists"])
        XCTAssertEqual(again.passthrough.keys["futureLists"],
                       .array([.object(["name": .string("Rainy days"), "films": .array([.int(949), .int(11645)]),
                                        "pinned": .bool(true), "score": .double(0.5), "note": .null])]))
        XCTAssertEqual(again.passthrough.shotOn[949], ["vistaVision"], "a Shot on value this Reel doesn't know is kept")
        XCTAssertEqual(again.records["tmdb:11645"]?.favorite, true)
        XCTAssertEqual(again.records["tmdb:949"]?.watched, true)
        XCTAssertEqual(again, notes)
    }

    func testAFileFromANewerReelIsShownButNotWritten() {
        let newer = Data(#"{"version": 9, "records": {"tmdb:949": {"watched": true}}}"#.utf8)
        let opening = NotesOpening.decide(newer)
        guard case .newer(let version, let file) = opening else { return XCTFail("\(opening)") }
        XCTAssertEqual(version, 9)
        XCTAssertEqual(file?.records["tmdb:949"]?.watched, true, "still shown")
        XCTAssertFalse(opening.writable)

        // Even when this Reel can't read the rest of it.
        let unreadable = Data(#"{"version": 9, "records": "a shape from the future"}"#.utf8)
        XCTAssertEqual(NotesOpening.decide(unreadable), .newer(version: 9, nil))
    }

    func testOlderFilesStillOpenAndAreUpgraded() throws {
        let opening = NotesOpening.decide(Data(#"{"version": 4, "records": {}, "corrections": {"Heat.mkv|5": 949}}"#.utf8))
        guard case .loaded(let file) = opening else { return XCTFail("\(opening)") }
        XCTAssertTrue(opening.writable)
        XCTAssertEqual(file.corrections["Heat.mkv|5"], 949)
        let saved = PersonalFile(records: file.records, corrections: file.corrections)
        XCTAssertEqual(saved.version, PersonalFile.currentVersion)
    }

    // MARK: Frames you removed

    func testRemovalsMadeBefore111AreFound() {
        let passNow = ["/a.jpg", "/b.jpg", "/c.jpg", "/d.jpg", "/e.jpg"]
        let stored = ["/a.jpg", "/c.jpg", "/e.jpg"]
        XCTAssertEqual(StillRemovals.recover(stored: stored, passNow: passNow), ["/b.jpg", "/d.jpg"])
        XCTAssertEqual(StillRemovals.recover(stored: passNow, passNow: passNow), [], "nothing removed")
    }

    func testRemovalsAreNotGuessedWhenItCantBeTold() {
        // A stored still that fails now: the check isn't behaving as it did.
        XCTAssertNil(StillRemovals.recover(stored: ["/a.jpg", "/z.jpg"], passNow: ["/a.jpg", "/b.jpg"]))
        // Too many to be yours: the film's images changed since.
        let many = (0..<20).map { "/\($0).jpg" }
        XCTAssertNil(StillRemovals.recover(stored: Array(many.prefix(3)), passNow: many))
    }

    func testANewVersionOfTheStillsCheckKeepsYourRemovals() throws {
        var film = copy("Heat.mkv", size: 5, tmdb: 949, state: .auto)
        film.checkedStills = ["/a.jpg", "/b.jpg"]
        film.checkedStillsVersion = FilmEntry.currentStillsCheck - 1
        let reread = try JSONDecoder().decode(FilmEntry.self, from: JSONEncoder().encode(film))
        XCTAssertNil(reread.checkedStills, "an older check's result is checked again")

        // Your removal is in Your Notes, not in the check's result, so it outlives it.
        let notes = try JSONDecoder().decode(PersonalFile.self, from: JSONEncoder().encode(PersonalFile(removedStills: [949: ["/b.jpg"]])))
        let checkedAgain = ["/a.jpg", "/b.jpg", "/c.jpg"]
        XCTAssertEqual(StillRemovals.visible(checkedAgain, removed: notes.removedStills[949]), ["/a.jpg", "/c.jpg"])
    }

    // MARK: Damaged files and Safety Copies

    func testADamagedFileOffersTheNewestReadableSafetyCopy() throws {
        let folder = try temporaryFolder()
        func write(_ day: String, _ text: String) throws {
            try Data(text.utf8).write(to: folder.appendingPathComponent("Your Notes \(day).json"))
        }
        try write("2026-11-12", #"{"version": 4, "records": {"tmdb:1": {"watched": true}}}"#)
        try write("2026-11-14", #"{"version": 4, "records": {"tmdb:2": {"watched": true}}}"#)
        try write("2026-11-15", "{ damaged")
        try Data("{}".utf8).write(to: folder.appendingPathComponent("Settings 2026-11-16.json"))

        XCTAssertEqual(NotesOpening.decide(Data("{ damaged".utf8)), .damaged)
        XCTAssertFalse(NotesOpening.damaged.writable, "nothing is written until you choose")

        let offered = SafetyCopies.newestReadableNotes(in: folder)
        XCTAssertEqual(offered?.day, "2026-11-14", "the newest copy that reads, not the newest file")
        XCTAssertEqual(offered?.file.records["tmdb:2"]?.watched, true)
        XCTAssertNil(SafetyCopies.newestReadableNotes(in: folder.appendingPathComponent("none")))
    }

    func testSettingsGetsOneSafetyCopyADay() throws {
        let folder = try temporaryFolder()
        let settings = folder.appendingPathComponent("Settings.json")
        let copies = folder.appendingPathComponent("Safety Copies", isDirectory: true)
        try JSONStore.save(["notForMe": [1, 2]], to: settings, permissions: 0o600)
        let day = Date(timeIntervalSince1970: 1_763_251_200) // 16 Nov 2025
        SafetyCopies.make(of: settings, into: copies, now: day)
        SafetyCopies.make(of: settings, into: copies, now: day.addingTimeInterval(3_600))
        SafetyCopies.make(of: settings, into: copies, now: day.addingTimeInterval(86_400))
        let names = try FileManager.default.contentsOfDirectory(atPath: copies.path).filter { $0.hasPrefix("Settings ") }
        XCTAssertEqual(names.count, 2, "one a day")
        let first = copies.appendingPathComponent(names.sorted()[0])
        let permissions = try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600, "the copy is as private as Settings")
    }
}

/// The migration on a synthetic library the size Alex's will grow to (spec §3.6): what the first
/// launch of 1.11 would write. Printed as DRYRUN lines for the CI log.
final class UserDataDryRunTests: XCTestCase {
    func testMigrationDryRunOnASyntheticLibrary() throws {
        var films: [FilmEntry] = []
        for i in 0..<300 {
            let state: MatchState = i < 250 ? .auto : i < 280 ? .confirmed : i < 292 ? .review : i < 296 ? .pending : .failed
            let tmdb: Int? = state == .pending || state == .failed ? nil : 20_000 + i
            for drive in i < 270 ? ["Main", "Backup"] : ["Main"] {
                var entry = FilmEntry(driveID: drive, relativePath: "F/\(i).mkv", fileName: "Film \(i).mkv", size: Int64(10_000 + i),
                                      modified: nil, addedAt: Date())
                if let tmdb { entry.tmdb = TMDBMovieDetails(id: tmdb, title: "Film \(i)") }
                entry.matchState = state
                films.append(entry)
            }
        }
        let start = Date()
        let matches = MatchMemory.remember(films, into: [:])
        let elapsed = Date().timeIntervalSince(start) * 1000
        let toCheck = matches.values.filter { $0.check == true }.count
        XCTAssertEqual(matches.count, 292)
        XCTAssertEqual(toCheck, 12)

        // Frame removals: 40 films checked, 9 with removals Reel can tell, 3 it can't.
        var found = 0, filmsWith = 0, unclear = 0
        for i in 0..<40 {
            let passNow = (0..<12).map { "/\(i)/\($0).jpg" }
            var stored = passNow
            if i < 9 { stored.removeLast(i % 3 + 1) }
            if i >= 37 { stored.append("/\(i)/gone.jpg") }
            if let removed = StillRemovals.recover(stored: stored, passNow: passNow) {
                if !removed.isEmpty { filmsWith += 1; found += removed.count }
            } else { unclear += 1 }
        }
        XCTAssertEqual(filmsWith, 9)
        XCTAssertEqual(found, 18)
        XCTAssertEqual(unclear, 3)

        let notes = PersonalFile(matches: matches)
        let size = try JSONEncoder().encode(notes).count
        print("DRYRUN| \(films.count) copies of 300 films: \(matches.count) matches remembered (\(toCheck) to check), "
              + "4 pending and 4 failed left alone, in \(String(format: "%.1f", elapsed)) ms; Your Notes grows by \(size / 1024) KB")
        print("DRYRUN| frame removals (synthetic): \(found) carried over in \(filmsWith) films, \(unclear) films couldn't be told")
    }
}
