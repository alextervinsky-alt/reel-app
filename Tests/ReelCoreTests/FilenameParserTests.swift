import XCTest
@testable import ReelCore

final class FilenameParserTests: XCTestCase {
    // MARK: Typical file names (made up)

    func testBladeRunner() {
        let p = FilenameParser.parse("/Volumes/Films/Blade Runner 2049 (2017) 2160p UHD BluRay REMUX DV HDR 10bit HEVC [Hindi DDP 2.0 + English TrueHD Atmos 7.1] x265 (GRP).mkv")
        XCTAssertEqual(p.title, "Blade Runner 2049")
        XCTAssertEqual(p.year, 2017)
        XCTAssertEqual(p.resolution, "2160p")
        XCTAssertEqual(p.source, "BluRay REMUX")
        XCTAssertEqual(p.hdr, "DV HDR")
        XCTAssertEqual(p.videoCodec, "HEVC")
        XCTAssertEqual(p.audioTracks, [
            AudioTrack(language: "Hindi", format: "DDP 2.0"),
            AudioTrack(language: "English", format: "TrueHD Atmos 7.1"),
        ])
        XCTAssertEqual(p.badges, ["4K", "Dolby Vision", "HDR", "REMUX", "Atmos"])
        XCTAssertTrue(p.isVideo)
        XCTAssertFalse(p.isIncomplete)
        XCTAssertFalse(p.looksLikeSample)
    }

    func testDredd() {
        let p = FilenameParser.parse("/Volumes/Films/Dredd 2012 UHD 1080p 10bit HDR BluRay HEVC x265 [Hindi DTH DD 2.0 384kbps + English DDP 7.1] ESub-EXAMPLE.mkv")
        XCTAssertEqual(p.title, "Dredd")
        XCTAssertEqual(p.year, 2012)
        XCTAssertEqual(p.resolution, "1080p")
        XCTAssertEqual(p.source, "BluRay")
        XCTAssertEqual(p.hdr, "HDR")
        XCTAssertEqual(p.audioTracks.count, 2)
        XCTAssertEqual(p.audioTracks[1], AudioTrack(language: "English", format: "DDP 7.1"))
    }

    func testGoneGirlIncomplete() {
        let p = FilenameParser.parse("/Volumes/Films/Gone.Girl.2014.BluRay.Remux.1080p.AVC.DTS-HD.MA.7.1-GRP.mkv.part")
        XCTAssertEqual(p.title, "Gone Girl")
        XCTAssertEqual(p.year, 2014)
        XCTAssertEqual(p.resolution, "1080p")
        XCTAssertEqual(p.source, "BluRay REMUX")
        XCTAssertEqual(p.videoCodec, "AVC")
        XCTAssertEqual(p.audioTracks, [AudioTrack(language: nil, format: "DTS-HD MA")])
        XCTAssertTrue(p.isIncomplete)
        XCTAssertTrue(p.isVideo)
    }

    func testTrainspotting() {
        let p = FilenameParser.parse("/Volumes/Films/T2 Trainspotting 2017 2160p 10bit HDR BluRay HEVC x265 [Hindi NF DDP 5.1 640kbps + English TrueHD Atmos 7.1] ESub-DEMO.mkv")
        XCTAssertEqual(p.title, "T2 Trainspotting")
        XCTAssertEqual(p.year, 2017)
        XCTAssertEqual(p.resolution, "2160p")
        XCTAssertEqual(p.audioTracks.count, 2)
    }

    func testNorthman() {
        let p = FilenameParser.parse("/Volumes/Films/The Northman (2022) 2160p MA WEB-DL DV HDR 10bit HEVC [Hindi DDP 5.1 + English DDP Atmos 5.1] x265 (TEST-GRP).mkv")
        XCTAssertEqual(p.title, "The Northman")
        XCTAssertEqual(p.year, 2022)
        XCTAssertEqual(p.source, "WEB-DL")
        XCTAssertEqual(p.hdr, "DV HDR")
        XCTAssertEqual(p.badges, ["4K", "Dolby Vision", "HDR", "Atmos"])
    }

    /// Every line of the sample list must produce a non-empty title and a year.
    func testWholeFixtureFile() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/reel-files-sample.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        var count = 0
        for line in text.split(separator: "\n") {
            guard let space = line.firstIndex(of: " ") else { continue }
            let path = String(line[line.index(after: space)...])
            let p = FilenameParser.parse(path)
            XCTAssertFalse(p.title.isEmpty, path)
            XCTAssertNotNil(p.year, path)
            count += 1
        }
        XCTAssertEqual(count, 5)
    }

    // MARK: Tricky names

    func testYearThatIsAlsoTitle() {
        let a = FilenameParser.parse("1917 (2019) 1080p BluRay x264.mkv")
        XCTAssertEqual(a.title, "1917")
        XCTAssertEqual(a.year, 2019)

        let b = FilenameParser.parse("1917.2019.1080p.BluRay.x264-GRP.mkv")
        XCTAssertEqual(b.title, "1917")
        XCTAssertEqual(b.year, 2019)
        XCTAssertEqual(b.videoCodec, "AVC")

        let c = FilenameParser.parse("2012 (2009) 1080p.mkv")
        XCTAssertEqual(c.title, "2012")
        XCTAssertEqual(c.year, 2009)
    }

    func testDotsMixedWithSpaces() {
        let p = FilenameParser.parse("/Volumes/Films/Dune.Part.Two.2024.UHD.Blu-Ray.2160p.REMUX.HDR.DoVi. .HEVC.TrueHD.Atmos.7.1-GROUP.mkv")
        XCTAssertEqual(p.title, "Dune Part Two")
        XCTAssertEqual(p.year, 2024)
        XCTAssertEqual(p.resolution, "2160p")
        XCTAssertEqual(p.source, "BluRay REMUX")
        XCTAssertEqual(p.hdr, "DV HDR")
    }

    func testNoYear() {
        let p = FilenameParser.parse("Blade.Runner.2049.2160p.UHD.BluRay.x265-GRP.mkv")
        XCTAssertEqual(p.title, "Blade Runner 2049")
        XCTAssertNil(p.year)
        XCTAssertEqual(p.resolution, "2160p")
    }

    func testPunctuationInTitles() {
        let a = FilenameParser.parse("Mr. Nobody (2009) 1080p.mkv")
        XCTAssertEqual(a.title, "Mr. Nobody")
        XCTAssertEqual(a.year, 2009)

        let b = FilenameParser.parse("(500) Days of Summer (2009) 1080p BluRay.mkv")
        XCTAssertEqual(b.title, "(500) Days of Summer")
        XCTAssertEqual(b.year, 2009)
    }

    func testNonVideoAndPartial() {
        let a = FilenameParser.parse("poster.jpg")
        XCTAssertFalse(a.isVideo)

        let b = FilenameParser.parse("Movie (2020) 1080p.mkv.part")
        XCTAssertTrue(b.isIncomplete)
        XCTAssertEqual(b.title, "Movie")
        XCTAssertEqual(b.year, 2020)
    }

    func testSampleDetection() {
        XCTAssertTrue(FilenameParser.parse("Sample.mkv").looksLikeSample)
        XCTAssertTrue(FilenameParser.parse("movie-sample.mkv").looksLikeSample)
        XCTAssertFalse(FilenameParser.parse("Dredd 2012 1080p.mkv").looksLikeSample)
    }

    func testDynamicRangeForTheTV() {
        XCTAssertEqual(FilenameParser.parse("Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HDR.HEVC-GRP.mkv").dynamicRange, .dolbyVision)
        XCTAssertTrue(FilenameParser.parse("Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HDR.HEVC-GRP.mkv").dolbyVisionWithHDR10)
        XCTAssertEqual(FilenameParser.parse("Arrival.2016.2160p.UHD.BluRay.HDR10+.HEVC-GRP.mkv").dynamicRange, .hdr10Plus)
        XCTAssertEqual(FilenameParser.parse("Heat 1995 2160p UHD BluRay HDR x265.mkv").dynamicRange, .hdr10)
        XCTAssertEqual(FilenameParser.parse("Heat.1995.1080p.BluRay.x264-GRP.mkv").dynamicRange, .sdr)
        XCTAssertFalse(FilenameParser.parse("Heat.1995.1080p.BluRay.x264-GRP.mkv").dynamicRange.isHDR)
    }
}
