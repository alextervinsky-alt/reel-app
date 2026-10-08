import XCTest
@testable import ReelCore

final class ExtrasTests: XCTestCase {
    private let mb: Int64 = 1_000_000

    private func group(_ files: [(String, Int64)]) -> [ScannedFile] {
        FilmGrouping.group(files.map { FilmGrouping.File(relativePath: $0.0, size: $0.1, modified: nil) },
                           minimumSize: 30 * mb)
    }

    private func kinds(_ film: ScannedFile?) -> [String: ExtraKind] {
        Dictionary(uniqueKeysWithValues: (film?.extras ?? []).map { ($0.fileName, $0.kind) })
    }

    // MARK: Grouping

    func testFolderWithInterviewsAndSubtitles() {
        let films = group([
            ("Rosetta/Rosetta, Dardenne, 1999.avi", 700 * mb),
            ("Rosetta/Rosetta-Cannes.avi", 180 * mb),
            ("Rosetta/Rosetta-Cannes.idx", 1 * mb),
            ("Rosetta/Rosetta-Cannes.sub", 2 * mb),
            ("Rosetta/Rosetta-Interview.avi", 120 * mb),
            ("Rosetta/Luc et Jean-Pierre Dardenne - Rosetta (1999).idx", 1 * mb),
            ("Rosetta/Luc et Jean-Pierre Dardenne - Rosetta (1999).sub", 3 * mb),
        ])
        XCTAssertEqual(films.map { $0.fileName }, ["Rosetta, Dardenne, 1999.avi"])
        let found = kinds(films.first)
        XCTAssertEqual(found["Rosetta-Cannes.avi"], .festival)
        XCTAssertEqual(found["Rosetta-Interview.avi"], .interview)
        XCTAssertEqual(found["Rosetta-Cannes.idx"], .subtitle)
        XCTAssertEqual(films.first?.extras.count, 6)

        let catalog = ExtrasCatalog(films.first?.extras ?? [])
        XCTAssertEqual(catalog.videos.map { $0.file.fileName }, ["Rosetta-Interview.avi", "Rosetta-Cannes.avi"])
        XCTAssertEqual(catalog.videos.last?.subtitles.map { $0.fileName }, ["Rosetta-Cannes.idx"])
        XCTAssertEqual(catalog.subtitles.map { $0.fileName }, ["Luc et Jean-Pierre Dardenne - Rosetta (1999).idx"])
        XCTAssertEqual(catalog.videos.last?.file.title(removing: ["Rosetta"]), "Cannes")
    }

    func testExtrasFolderSampleAndNotes() {
        let films = group([
            ("Fallen.Angels.1995.1080p.BluRay.x264.AC3-GRP/Fallen.Angels.1995.1080p.BluRay.x264.AC3-GRP.mkv", 9_000 * mb),
            ("Fallen.Angels.1995.1080p.BluRay.x264.AC3-GRP/info.txt", 1_000),
            ("Fallen.Angels.1995.1080p.BluRay.x264.AC3-GRP/sample.mkv", 60 * mb),
            ("Fallen.Angels.1995.1080p.BluRay.x264.AC3-GRP/Extras/A Beautiful Evening.mkv", 400 * mb),
            ("Fallen.Angels.1995.1080p.BluRay.x264.AC3-GRP/Extras/Chris Doyle.mkv", 900 * mb),
            ("Fallen.Angels.1995.1080p.BluRay.x264.AC3-GRP/Extras/Stills.mkv", 20 * mb),
            ("Fallen.Angels.1995.1080p.BluRay.x264.AC3-GRP/Extras/Trailer.mkv", 80 * mb),
            ("Fallen.Angels.1995.1080p.BluRay.x264.AC3-GRP/www.example.com.jpg", 50_000),
        ])
        XCTAssertEqual(films.count, 1)
        let found = kinds(films.first)
        XCTAssertEqual(found["sample.mkv"], .sample)
        XCTAssertEqual(found["info.txt"], .document)
        XCTAssertEqual(found["Chris Doyle.mkv"], .bonus)
        XCTAssertEqual(found["Stills.mkv"], .gallery)
        XCTAssertEqual(found["Trailer.mkv"], .trailer)
        XCTAssertNil(found["www.example.com.jpg"], "release-group adverts are left out")

        let catalog = ExtrasCatalog(films.first?.extras ?? [])
        XCTAssertEqual(catalog.videos.count, 4)
        XCTAssertEqual(catalog.otherFiles.map { $0.kind }, [.sample, .document])
    }

    func testDriveRootIsAShelf() {
        let films = group([
            ("Up (2009).mkv", 2_000 * mb),
            ("Up (2009).en.srt", 80_000),
            ("Upgrade (2018).mkv", 3_000 * mb),
            ("Upgrade (2018) Trailer.mkv", 50 * mb),
            ("The Interview (2014).mkv", 2_500 * mb),
            ("poster.jpg", 100_000),
        ])
        XCTAssertEqual(films.map { $0.fileName }, ["The Interview (2014).mkv", "Up (2009).mkv", "Upgrade (2018).mkv"])
        XCTAssertEqual(films[1].extras.map { $0.fileName }, ["Up (2009).en.srt"])
        XCTAssertEqual(films[1].extras.first?.language, "English")
        XCTAssertEqual(films[2].extras.map { $0.kind }, [.trailer])
    }

    func testCollectionFolderKeepsFilmsApart() {
        let films = group([
            ("Before Trilogy/Before Sunrise (1995).mkv", 1_500 * mb),
            ("Before Trilogy/Before Sunset (2004).mkv", 1_400 * mb),
            ("Before Trilogy/Before Midnight (2013).mkv", 600 * mb),
            ("Before Trilogy/Before Sunset (2004).et.srt", 70_000),
        ])
        XCTAssertEqual(films.count, 3)
        XCTAssertEqual(films.first { $0.fileName.hasPrefix("Before Sunset") }?.extras.first?.language, "Estonian")
    }

    func testFilmInPiecesAndBonusFolderBesideIt() {
        let pieces = group([
            ("Stalker/Stalker 1979 CD2.avi", 720 * mb),
            ("Stalker/Stalker 1979 CD1.avi", 700 * mb),
        ])
        XCTAssertEqual(pieces.map { $0.fileName }, ["Stalker 1979 CD1.avi"])
        XCTAssertEqual(pieces.first?.extras.first?.kind, .part)

        let beside = group([
            ("Heat/Movie/Heat (1995).mkv", 9_000 * mb),
            ("Heat/Featurettes/Making Heat.mkv", 300 * mb),
        ])
        XCTAssertEqual(beside.map { $0.fileName }, ["Heat (1995).mkv"])
        XCTAssertEqual(beside.first?.extras.first?.kind, .behindTheScenes)
    }

    // MARK: Names, people and lookups

    func testExtraTitlesAndPeople() {
        let trailer = FilmExtra(relativePath: "x/Fallen.Angels.1995.Trailer.1080p.mkv", size: 1, kind: .trailer)
        XCTAssertEqual(trailer.title(removing: ["Fallen Angels"]), "Trailer")
        let beach = FilmExtra(relativePath: "x/The.Beach.Bum.Making.Of.mkv", size: 1, kind: .behindTheScenes)
        XCTAssertEqual(beach.title(removing: ["The Beach Bum"]), "Making Of")

        let people = [(name: "Wong Kar-wai", role: "Director"), (name: "Christopher Doyle", role: "Director of Photography")]
        XCTAssertEqual(ExtraPeople.person(in: "Chris Doyle", among: people)?.role, "Director of Photography")
        XCTAssertNil(ExtraPeople.person(in: "A Beautiful Evening", among: people))
    }

    func testLookupUsesFolderAndNameParts() {
        let film = FilmEntry(driveID: "D", relativePath: "Rosetta/Rosetta, Dardenne, 1999.avi",
                             fileName: "Rosetta, Dardenne, 1999.avi", size: 1, modified: nil, addedAt: Date())
        XCTAssertEqual(film.parsed.title, "Rosetta, Dardenne")
        XCTAssertEqual(film.lookupTitles, ["Rosetta, Dardenne", "Rosetta", "Dardenne"])
        XCTAssertEqual(film.lookupYear, 1999)

        let loose = FilmEntry(driveID: "D", relativePath: "Movies/Dredd 2012.mkv", fileName: "Dredd 2012.mkv",
                              size: 1, modified: nil, addedAt: Date())
        XCTAssertEqual(loose.lookupTitles, ["Dredd"], "a generic folder name isn't used")
    }

    func testExtrasSurviveSavingAndRescans() throws {
        let extra = FilmExtra(relativePath: "F/Extras/Trailer.mkv", size: 5, kind: .trailer)
        let entry = FilmEntry(driveID: "D", relativePath: "F/F (2001).mkv", fileName: "F (2001).mkv", size: 9,
                              modified: nil, addedAt: Date(), extras: [extra])
        let decoded = try JSONDecoder().decode(FilmEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(decoded.extras, [extra])

        let rescanned = LibraryMerge.apply(
            scan: [ScannedFile(relativePath: "F/F (2001).mkv", fileName: "F (2001).mkv", size: 9, modified: nil)],
            driveID: "D", to: [entry], now: Date())
        XCTAssertEqual(rescanned.first?.extras, [], "a rescan replaces the extras with what's on the drive now")
    }
}
