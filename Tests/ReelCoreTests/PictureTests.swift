import XCTest
@testable import ReelCore

/// HDR or SDR, so the TV can be set before Play: only what the name proves, never a guess.
final class PictureTests: XCTestCase {
    private func picture(_ name: String, folder: String? = nil, yours: DynamicRange? = nil) -> FilePicture {
        FilePicture.of(FilenameParser.parse(name), ownFolder: folder.map { FilenameParser.parse($0) }, yours: yours)
    }

    /// The real file names of a library (Reel 1.8.8's fixes), each with what the TV must be set to.
    func testRealNames() {
        let expected: [(String, DynamicRange?, DynamicRange?, FilePicture.Basis)] = [
            ("2001. The Fast and the Furious.mkv", nil, nil, .notStated),
            ("2003. 2 Fast 2 Furious.mkv", nil, nil, .notStated),
            ("2009, Fast & Furious.mkv", nil, nil, .notStated),
            ("2011. Fast Five [Extended Cut].mkv", nil, nil, .notStated),
            ("2013. Furious 6 [Extended.Cut].mkv", nil, nil, .notStated),
            ("2021. Fast & Furious 9 The Fast Saga.mkv", nil, nil, .notStated),
            ("Ah-ga-ssi.aka.The.Handmaiden.2016.Extended.BluRay.1080p.DTS-HD.MA.5.1.AVC.REMUX-FraMeSToR.mkv", .sdr, nil, .source),
            ("Anatomy of a Fall 2024 1080p BluRay REMUX AVC x264 [Hindi AMZN DDP 5.1 640kbps + English DTS-HD MA 5.1] ESub-CiNEPHiLES-4kHdHub.mkv", .sdr, nil, .source),
            ("Dune Part One (2021) 2160p 4K UHD DV HDR10 BluRay REMUX x265 10bit HEVC [Telugu AMZN DD5.1 640Kbps + Org Hindi BD 5.1 448Kbps + English DTS-HDMA TrueHD Atmos 7.1] ESub TeluguDrives.mkv", .dolbyVision, .hdr10, .named),
            ("Ex Machina (2014) 1080p UHD BluRay HDR 10bit HEVC [Hindi NF DDP 5.1 + English DDP 7.1] x265 (SA89-4kHDHub).mkv", .hdr10, nil, .named),
            ("F1 - The Movie 2025 2160p UHD BluRay REMUX DV HDR 10bit HEVC [Hindi-Tamil-Telugu DDP 5.1 + English TrueHD Atmos 7.1] x265 CiNPEHiLES-LUMiX.mkv", .dolbyVision, .hdr10, .named),
            ("Flow.AKA.Straume.2024.2160p.UHD.BluRay.HDR10.DTS-HD.MA.5.1.x265.10bit-StOiC-4kHDHub.com.mkv", .hdr10, nil, .named),
            ("Good Luck, Have Fun, Dont Die (2025) 2160p 10bit HDR10+ DV BluRay HEVC x265 [Hindi AMZN DDP 5.1 640kbps + English TrueHD Atmos 7.1] ESub-(SPHD-4kHdHub).mkv", .dolbyVision, .hdr10Plus, .named),
            ("Leon.the.Professional.Extended.1994.Dual.1080p.mkv", nil, nil, .notStated),
            ("Nomadland (2020) 1080p BluRay REMUX AVC [English DTS-HD MA 5.1] (FraMeSToR-Ionicboy).mkv", .sdr, nil, .source),
            ("Obsession (2025) 2160p UHD BluRay REMUX DV HDR 10bit HEVC [Hindi AMZN DDP 5.1 + English TrueHD Atmos 7.1] x265 (CiNEPHiLES-LUMiX).mkv", .dolbyVision, .hdr10, .named),
            ("Society.of.the.Snow.2024.1080p.NF.WEB-DL.DUAL.AAC5.1.HDR.AV1-AV1Core.mkv", .hdr10, nil, .named),
            ("The Girl with Dragon Tattoo (2011) 1080p 10bit BluRay x265 HEVC [Hindi (Org DVD DD 5.1 - 448 Kbps) + English DDP 5.1] ESubs (K1tKat-LUMiX).mkv", .sdr, nil, .source),
            ("The Place Beyond the Pines (2012) MULTi VFI 2160p 10bit 4KLight DV HDR BluRay DTS-HD MA 5.1 x265-QTZ.mkv", .dolbyVision, .hdr10, .named),
            ("The.Boy.and.the.Heron.2024.1080p.Blu-ray.Remux.AVC.TrueHD.Atmos.7.1-CiNEPHiLES.mkv", .sdr, nil, .source),
        ]
        for (name, range, fallback, basis) in expected {
            let found = picture(name)
            XCTAssertEqual(found.range, range, name)
            XCTAssertEqual(found.fallback, fallback, name)
            XCTAssertEqual(found.basis, basis, name)
        }
    }

    func testAnAudioTrackFromADVDIsNotADVD() {
        let found = picture("The Girl with Dragon Tattoo (2011) 1080p 10bit BluRay x265 HEVC [Hindi (Org DVD DD 5.1 - 448 Kbps) + English DDP 5.1] ESubs (K1tKat-LUMiX).mkv")
        XCTAssertTrue(found.reason.contains("1080p Blu-ray"), found.reason)
    }

    func testNotStatedIsNeverSDR() {
        let found = picture("2013. Furious 6 [Extended.Cut].mkv")
        XCTAssertNil(found.label)
        XCTAssertFalse(found.isHDR)
        XCTAssertFalse(found.isKnown)
        XCTAssertTrue(found.searchWords.isEmpty, "a search for SDR doesn't find it")
    }

    func testFourKWithoutHDRIsNotStated() {
        XCTAssertEqual(picture("Film.2020.2160p.WEB-DL.x265-GRP.mkv").basis, .notStated)
        XCTAssertEqual(picture("Film (2019) [WEBDL-2160p].mkv").basis, .notStated)
        XCTAssertTrue(picture("Film.2020.2160p.WEB-DL.x265-GRP.mkv").reason.hasPrefix("4K"))
    }

    func testTraps() {
        // HDRip is an old word for a rip of an HD source: SDR.
        XCTAssertEqual(picture("Movie.2019.1080p.HDRip.x264-GRP.mkv").range, .sdr)
        // A DVD is not Dolby Vision.
        XCTAssertEqual(picture("Film.2001.DVD.mkv").range, .sdr)
        XCTAssertEqual(picture("Film (1999) DVDRip XviD.avi").basis, .source)
        // The uploader's site name isn't 4K.
        XCTAssertEqual(picture("Film 2020 1080p BluRay x264 (4kHDHub).mkv").basis, .source)
        // Dolby Vision written out, and tags in brackets.
        XCTAssertEqual(picture("Dune.2021.2160p.WEB-DL.Dolby.Vision.HEVC-GRP.mkv").range, .dolbyVision)
        XCTAssertEqual(picture("Dune (2021) [Bluray-2160p][DV HDR10][x265].mkv").fallback, .hdr10)
        XCTAssertEqual(picture("Film [Bluray-1080p].mkv").basis, .source)
        // Said outright.
        XCTAssertEqual(picture("Film.2020.2160p.SDR.WEB-DL.mkv").basis, .named)
        XCTAssertEqual(picture("Film.2020.2160p.SDR.WEB-DL.mkv").range, .sdr)
        XCTAssertEqual(picture("Film.2018.720p.WEB.mkv").range, .sdr)
    }

    func testOneThousandEightyFromA4KSourceIsOnlyAConvention() {
        let found = picture("Ex Machina (2014) 1080p UHD BluRay 10bit HEVC x265.mkv")
        XCTAssertEqual(found.range, .sdr)
        XCTAssertEqual(found.basis, .convention, "a 1080p copy of a 4K disc could have kept HDR: only the release name says SDR")
        XCTAssertEqual(picture("Film.2022.1080p.WEB-DL.DDP5.1.H.264-GRP.mkv").basis, .convention)
    }

    func testTheFilmsOwnFolder() {
        let found = picture("dune.mkv", folder: "Dune (2021) 2160p DV HDR10")
        XCTAssertEqual(found.range, .dolbyVision)
        XCTAssertEqual(found.basis, .folder)
        XCTAssertEqual(picture("dune.mkv").basis, .notStated, "no folder of its own: a collection folder isn't asked")
        XCTAssertEqual(picture("Dune.2021.1080p.BluRay.x264.mkv", folder: "Dune 2160p DV").range, .sdr, "the file's own name comes first")
    }

    /// A whole collection in one folder whose name says the picture (a real library's).
    func testACollectionFolderSpeaksForEachFilm() {
        let folder = "The Fast and The Furious - Complete Collection (2001-2021) 1080p HEVC HDR10 DTS 7.1.x265 [BluRay] {djdezzie}"
        let found = picture("2013. Furious 6 [Extended.Cut].mkv", folder: folder)
        XCTAssertEqual(found.range, .hdr10)
        XCTAssertEqual(found.basis, .folder)
        XCTAssertTrue(FilePicture.isCollection(folder))
        XCTAssertTrue(FilePicture.isCollection("The Godfather Trilogy 2160p DV"))
        XCTAssertTrue(FilePicture.isCollection("Alien Anthology 1979-1997 1080p"))
        XCTAssertFalse(FilePicture.isCollection("4K HDR Films"), "assorted films: their folder says nothing about each")
        XCTAssertFalse(FilePicture.isCollection("Movies 2160p"))
        XCTAssertFalse(FilePicture.isCollection("Blade Runner 2049 (2017) 2160p"), "a title with a number isn't a span of years")
    }

    func testWhichFoldersSpeak() {
        func entry(_ path: String) -> FilmEntry {
            FilmEntry(driveID: "D", relativePath: path, fileName: (path as NSString).lastPathComponent, size: 1, modified: nil, addedAt: Date())
        }
        let films = [entry("Fast Collection (2001-2021) HDR10/a.mkv"), entry("Fast Collection (2001-2021) HDR10/b.mkv"),
                     entry("4K HDR Films/c.mkv"), entry("4K HDR Films/d.mkv"), entry("Dune 2160p DV/dune.mkv"), entry("top.mkv")]
        let names = FilePicture.ownFolderNames(films)
        XCTAssertEqual(Set(names.values), ["Fast Collection (2001-2021) HDR10", "Dune 2160p DV"])
        XCTAssertEqual(names.count, 3)
    }

    func testYourSettingWins() {
        let found = picture("Dune.2021.2160p.WEB-DL.DV.HEVC-GRP.mkv", yours: .sdr)
        XCTAssertEqual(found.range, .sdr)
        XCTAssertEqual(found.basis, .yours)
        XCTAssertEqual(picture("2013. Furious 6.mkv", yours: .hdr).label, "HDR")
        XCTAssertEqual(picture("2013. Furious 6.mkv", yours: .dolbyVision).label, "HDR · Dolby Vision")
    }

    func testLabels() {
        XCTAssertEqual(picture("Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HDR.HEVC-GRP.mkv").label, "HDR · Dolby Vision + HDR10")
        XCTAssertEqual(picture("Heat.1995.1080p.BluRay.x264-GRP.mkv").label, "SDR")
        XCTAssertEqual(picture("Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HDR.HEVC-GRP.mkv").searchWords, ["HDR", "Dolby Vision", "HDR10"])
    }
}
