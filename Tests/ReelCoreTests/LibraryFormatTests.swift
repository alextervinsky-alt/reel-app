import XCTest
@testable import ReelCore

/// Library.json format 7 (1.11, spec §4): each film's info is stored once and its copies refer to
/// it; the Shot on readings are gone. A format-6 file opens as it was, keeping every copy, match
/// and fix. Synthetic films only.
final class LibraryFormatTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A film with a realistic amount of info (an overview, thirty facts), on one or two drives.
    private func library(films count: Int, twice: Int) -> [FilmEntry] {
        var all: [FilmEntry] = []
        for id in 1...count {
            var details = TMDBMovieDetails(id: 50_000 + id, title: "Synthetic Film \(id)")
            details.overview = String(repeating: "A quiet story about a harbour town and the people who stay. ", count: 6)
            let facts = (0..<30).map { FunFact(category: "Production", text: "Fact \($0) about film \(id): " + String(repeating: "detail ", count: 25)) }
            for drive in id <= twice ? ["Main", "Backup"] : ["Main"] {
                var entry = FilmEntry(driveID: drive, relativePath: "Films/Film \(id).mkv", fileName: "Film \(id).mkv",
                                      size: Int64(1_000_000 + id), modified: start, addedAt: start, matchState: id % 10 == 0 ? .confirmed : .auto)
                entry.tmdb = details
                entry.funFacts = FunFacts(facts: facts, articleTitle: "Synthetic Film \(id)", fetchedAt: start)
                entry.infoVersion = FilmEntry.currentInfoVersion
                entry.infoUpdatedAt = start
                entry.checkedStills = ["/still-\(id)-a.jpg", "/still-\(id)-b.jpg"]
                entry.checkedStillsVersion = FilmEntry.currentStillsCheck
                entry.lastLookup = start
                all.append(entry)
            }
        }
        return all
    }

    func testEachFilmIsStoredOnceAndReadBackWhole() throws {
        let films = library(films: 300, twice: 270)
        XCTAssertEqual(films.count, 570)
        let file = LibraryFile(films: films, writtenBy: "test")
        let data = try JSONStore.encode(file)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual((json?["filmInfo"] as? [String: Any])?.count, 300, "one record per film")
        XCTAssertEqual(json?["version"] as? Int, 7)

        let read = try JSONStore.decode(LibraryFile.self, from: data)
        XCTAssertEqual(read.films, films, "every copy back as it was, both drives")
        XCTAssertEqual(read.readVersion, 7)

        // A second copy costs a few hundred bytes now, not the whole film's info again.
        let single = try JSONStore.encode(LibraryFile(films: library(films: 300, twice: 0))).count
        let perSecondCopy = Double(data.count - single) / 270
        XCTAssertLessThan(perSecondCopy, 600, "bytes per second copy")

        // The same library written the old way, each copy with its film's info.
        let old = try JSONStore.encode(films)
        print("GATE| Library.json at 300 films (570 copies, synthetic): \(data.count / 1024) KB in format 7, "
              + "\(old.count / 1024) KB with every copy's info; \(Int(perSecondCopy)) bytes per second copy")
    }

    func testAFormat6FileOpensWithEverythingKept() throws {
        // As 1.10.10 wrote it: every copy with its own info, and a reading this Reel no longer reads.
        var films = library(films: 3, twice: 2)
        films[0].matchState = .review
        films[0].candidates = [ScoredCandidate(movie: TMDBMovieSummary(id: 7, title: "Other"), score: 0.4)]
        let copies = try films.map { film -> [String: Any] in
            var copy = try JSONSerialization.jsonObject(with: JSONStore.encode(film)) as! [String: Any]
            copy["craft"] = ["version": 19, "shotOn": ["film"], "names": ["Panavision"], "claims": [["text": "old"]]]
            copy["craftAttempt"] = ["at": "2026-01-01T00:00:00Z"]
            return copy
        }
        let old: [String: Any] = ["version": 6, "writtenBy": "1.10.10 (428)", "films": copies,
                                  "scans": ["Main": ["at": "2026-01-01T00:00:00Z", "complete": true, "films": 3]]]
        let data = try JSONSerialization.data(withJSONObject: old)

        let opening = LibraryOpening.decide(data)
        guard case .loaded(let file) = opening else { return XCTFail("\(opening)") }
        XCTAssertTrue(opening.writable)
        XCTAssertEqual(file.readVersion, 6, "opening can tell it was upgraded without reading the file again")
        XCTAssertEqual(file.version, 7)
        XCTAssertEqual(file.films.count, 5)
        XCTAssertEqual(file.films.map(\.fileKey), films.map(\.fileKey))
        XCTAssertEqual(file.films.map(\.tmdb?.id), films.map(\.tmdb?.id), "every match kept")
        XCTAssertEqual(file.films.map(\.matchState), films.map(\.matchState))
        XCTAssertEqual(file.films[0].candidates.count, 1)
        XCTAssertEqual(file.films.map(\.checkedStills), films.map(\.checkedStills))
        XCTAssertEqual(file.films.map(\.funFacts), films.map(\.funFacts))
        XCTAssertEqual(file.scans?["Main"]?.films, 3)
        let written = String(decoding: try JSONStore.encode(file), as: UTF8.self)
        XCTAssertFalse(written.contains("\"craft"), "the old readings are dropped")

        // Written back as format 7 and read again: the same.
        let again = try JSONStore.decode(LibraryFile.self, from: JSONStore.encode(file))
        XCTAssertEqual(again.films, file.films)
    }

    func testACopyWhoseFilmInfoIsMissingIsLookedUpAgain() throws {
        let films = library(films: 2, twice: 0)
        var json = try JSONSerialization.jsonObject(with: JSONStore.encode(LibraryFile(films: films))) as! [String: Any]
        var info = json["filmInfo"] as! [String: Any]
        info.removeValue(forKey: String(films[1].tmdb!.id))
        json["filmInfo"] = info
        let read = try JSONStore.decode(LibraryFile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(read.films[0].tmdb?.id, films[0].tmdb?.id)
        XCTAssertNil(read.films[1].tmdb)
        XCTAssertEqual(read.films[1].matchState, .pending, "matched again, from what Your Notes remembers")
    }

    func testAStillsCheckFromAnOlderVersionIsCheckedAgain() throws {
        var films = library(films: 1, twice: 1)
        for i in films.indices { films[i].checkedStillsVersion = FilmEntry.currentStillsCheck - 1 }
        let read = try JSONStore.decode(LibraryFile.self, from: JSONStore.encode(LibraryFile(films: films)))
        XCTAssertTrue(read.films.allSatisfy { $0.checkedStills == nil })
    }

    func testOpeningAndSavingAtThreeHundredFilms() throws {
        let file = LibraryFile(films: library(films: 300, twice: 270))
        var data = Data()
        let save = try measureMilliseconds { data = try JSONStore.encode(file) }
        let open = try measureMilliseconds { _ = LibraryOpening.decide(data) }
        print("GATE| Library.json at 300 films (synthetic, Linux runner): encode \(save) ms, open \(open) ms")
        XCTAssertLessThan(open, 1_500, "a loose guard; the macOS figure is measured in the app")
    }

    private func measureMilliseconds(_ work: () throws -> Void) rethrows -> Int {
        let begin = Date()
        try work()
        return Int(Date().timeIntervalSince(begin) * 1000)
    }
}
