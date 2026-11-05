import XCTest
@testable import ReelCore

/// 1.10.9's isolated improvements, each tested on its own: an article read once whatever its address
/// (live, AMP, archived, re-filed under another slug); and a download in progress dropped from the
/// catalogue only by a complete scan of its drive (the file itself is never touched).
final class IdentityRelevanceAndScanTests: XCTestCase {
    // MARK: Article identity

    func url(_ text: String) -> URL { URL(string: text)! }

    func testLiveAMPAndArchivedCopiesAreOneArticle() {
        let live = url("https://variety.com/2024/artisans/news/alien-romulus-cinematographer-1236117157/")
        let amp = url("https://variety.com/2024/artisans/news/alien-romulus-cinematographer-1236117157/amp/")
        let archived = url("https://web.archive.org/web/20240925051015/https://variety.com/2024/artisans/news/alien-romulus-cinematographer-1236117157/amp/")
        XCTAssertEqual(CameraSources.identity(live), CameraSources.identity(amp))
        XCTAssertEqual(CameraSources.identity(live), CameraSources.identity(archived))
        // Unfamiliar forms: an AMP host, a ".amp" path, tracking tags.
        XCTAssertEqual(CameraSources.identity(url("https://amp.example-news.com/story/the-long-shoot")),
                       CameraSources.identity(url("https://www.example-news.com/story/the-long-shoot/?utm_source=x&outputType=amp")))
        XCTAssertEqual(CameraSources.identity(url("https://example.org/articles/the-long-shoot.amp")),
                       CameraSources.identity(url("https://example.org/articles/the-long-shoot")))
        // Different articles stay different.
        XCTAssertNotEqual(CameraSources.identity(url("https://variety.com/2024/news/story-one/")),
                          CameraSources.identity(url("https://variety.com/2024/news/story-two/")))
    }

    func testAnArticleReFiledUnderAnotherSlugIsReadOnce() {
        let body = ["The Society welcomes Jane Doe as an active member, recognising her work on The Quiet Harbour and two earlier features.",
                    "Doe began as a camera assistant in Glasgow.", "She lives in London."]
        let a = CameraReading.Source(title: "Jane Doe Welcomed as ASC Member", site: "American Cinematographer",
                                     url: url("https://theasc.com/news/jane-doe-new-asc-member/"), paragraphs: body)
        let b = CameraReading.Source(title: "Jane Doe Welcomed as ASC Member", site: "American Cinematographer",
                                     url: url("https://theasc.com/news/jane-doe-welcomed-as-asc-member/"), paragraphs: body)
        XCTAssertTrue(CameraSources.sameArticle(a, b))
        // A shared series title with different articles isn't one article.
        let c = CameraReading.Source(title: "Clubhouse Conversations — The Quiet Harbour", site: "American Cinematographer",
                                     url: url("https://theasc.com/video/clubhouse-the-quiet-harbour/"), paragraphs: ["Doe on lighting the harbour at night.", "x", "y"])
        let d = CameraReading.Source(title: "Clubhouse Conversations — The Quiet Harbour", site: "American Cinematographer",
                                     url: url("https://theasc.com/video/clubhouse-the-quiet-harbour-part-two/"), paragraphs: ["Doe on the grade and the LUT.", "x", "y"])
        XCTAssertFalse(CameraSources.sameArticle(c, d))
        // Another site with the same headline isn't the same article.
        let e = CameraReading.Source(title: a.title, site: "British Cinematographer", url: url("https://britishcinematographer.co.uk/jane-doe-asc/"),
                                     paragraphs: body)
        XCTAssertFalse(CameraSources.sameArticle(a, e))
    }

    /// The research engine reads an article once when a second search finds it at another address.
    func testTheEngineDoesntReadTheSameArticleTwice() async {
        let body = ["Jane Doe shot The Quiet Harbour on the Sony Venice 2 with Cooke S4 lenses.",
                    "The Quiet Harbour was lit with SkyPanels and practicals.", "Doe operated the A camera herself."]
        let first = "https://theasc.com/news/jane-doe-the-quiet-harbour/", second = "https://theasc.com/news/the-quiet-harbour-jane-doe/"
        let corpus = BenchCorpus(name: "dup", films: [], pages: [
            first: BenchPage(title: "Jane Doe on The Quiet Harbour", url: first, site: "American Cinematographer", paragraphs: body, claims: []),
            second: BenchPage(title: "Jane Doe on The Quiet Harbour", url: second, site: "American Cinematographer", paragraphs: body, claims: []),
        ], searches: [BenchSearch(provider: "American Cinematographer", query: "Jane Doe",
                                  hits: [("Jane Doe on The Quiet Harbour", first), ("Jane Doe on The Quiet Harbour", second)])])
        let transport = ResearchBenchmarkTests.Transport(corpus)
        let crew = [CraftCrew.Contributor(name: "Jane Doe", role: .cinematographer)]
        let run = await ResearchEngine.run(CameraReading(sources: [], more: [], cinematographer: nil), article: nil, filmTitle: "The Quiet Harbour",
                                           cinematographers: ["Jane Doe"], directors: [], year: 2022, otherTitles: [], crew: crew, previous: nil,
                                           transport: transport, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(run.sources.count, 1, "\(run.sources.map(\.url))")
        XCTAssertTrue(run.skipped.contains { $0.reason.hasPrefix("the same article as") })
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
