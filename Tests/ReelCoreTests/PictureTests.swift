import XCTest
@testable import ReelCore

/// HDR or SDR, the one choice a Mac's display has before Play: what the name says, what the kind of
/// file proves, and what's likely said as a guess. The names are made up, shaped like real ones.
final class PictureTests: XCTestCase {
    private func picture(_ name: String, folder: String? = nil, yours: DynamicRange? = nil) -> FilePicture {
        FilePicture.of(FilenameParser.parse(name), ownFolder: folder.map { FilenameParser.parse($0) }, yours: yours)
    }

    // MARK: Said in the name

    func testTheWaysNamesWriteHDR() {
        let cases: [(String, FilePicture.Format)] = [
            ("Film (2017) 2160p UHD BluRay REMUX DV HDR 10bit HEVC [Hindi DDP 2.0 + English TrueHD Atmos 7.1] x265 (GRP).mkv", .dolbyVisionHDR10),
            ("Film.2024.UHD.Blu-Ray.2160p.REMUX.HDR.DoVi.[Hindi.DDP5.1+English.TrueHD.Atmos.7.1].HEVC(GRP).mkv", .dolbyVisionHDR10),
            ("Film 2019 2160p 4K UHD HDR10 DV BluRay REMUX x265 10bit HEVC.mkv", .dolbyVisionHDR10),
            ("Film 2025 Hybrid 2160p UHD Blu-ray Remux DV HDR10P HEVC [English TrueHD Atmos 7.1] (GRP).mkv", .dolbyVisionHDR10Plus),
            ("Film.2021.Hybrid.2160p.UHD.Blu-ray.Remux.DV.HDR10plus.HEVC-GRP.mkv", .dolbyVisionHDR10Plus),
            ("Film.2023.2160p.REMUX.IMAX.Dolby.Vision.And.HDR10.PLUS.ENG.DTS-HD.Master.x265.mkv", .dolbyVisionHDR10Plus),
            ("Film 2015 Open Matte 2160p UHD BluRay DV HDR10+REMUX TrueHD Atmos 7.1-GRP.mkv.crdownload", .dolbyVisionHDR10Plus),
            ("Film (2025) 2160p 10bit HDR10+ DV BluRay HEVC x265.mkv", .dolbyVisionHDR10Plus),
            ("Film.2024.2160p.UHD.BluRay.HDR10.DTS-HD.MA.5.1.x265.10bit-GRP.mkv", .hdr10),
            ("Film 2012 UHD 1080p 10bit HDR BluRay HEVC x265 [Hindi DD 2.0 + English DDP 7.1] ESub-GRP.mkv", .hdr10),
            ("Film.2024.1080p.NF.WEB-DL.DUAL.AAC5.1.HDR.AV1-GRP.mkv", .hdr10),
            ("Film.2020.2160p.WEB-DL.HDR10Plus.HEVC-GRP.mkv", .hdr10Plus),
            ("Film.2020.2160p.HLG.WEB.H265-GRP.mkv", .hlg),
            ("Film (2021) [Bluray-2160p][DV HDR10][x265].mkv", .dolbyVisionHDR10),
        ]
        for (name, format) in cases {
            let found = picture(name)
            XCTAssertEqual(found.setting, .hdr, name)
            XCTAssertEqual(found.format, format, name)
            XCTAssertEqual(found.basis, .named, name)
            XCTAssertEqual(found.label, "HDR", name)
        }
    }

    /// Release names list every format a file has: "DV" alone means no HDR10 is named. On a 4K
    /// Blu-ray that's still HDR10 underneath (its Dolby Vision always is); on a web release it
    /// usually isn't (profile 5), which some players show in the wrong colours.
    func testDolbyVisionAlone() {
        let disc = picture("Film.2015.UHD.BluRay.2160p.TrueHD.Atmos.7.1.DV.HEVC.HYBRID.REMUX-GRP.mkv")
        XCTAssertEqual(disc.format, .dolbyVisionHDR10)
        XCTAssertTrue(disc.reason.contains("4K Blu-ray"), disc.reason)
        XCTAssertEqual(picture("Film 2012 EXTENDED 1080p UHD BluRay DoVi x265 HEVC 10bit.mkv").format, .dolbyVisionHDR10, "a copy of the disc")
        let web = picture("Film.2025.2160p.IT.WEB-DL.MULTI.DDP5.1.Atmos.DV.H.265-GRP.mkv")
        XCTAssertEqual(web.format, .dolbyVisionOnly)
        XCTAssertEqual(web.label, "HDR · Dolby Vision only")
        XCTAssertTrue(web.isDolbyVisionOnly)
        XCTAssertEqual(picture("Film.2025.2160p.WEB-DL.DV.HDR.H.265-GRP.mkv").format, .dolbyVisionHDR10, "a hybrid names both")
        XCTAssertEqual(picture("Film.2026.2160p.UHD.BluRay.REMUX.DV.P7.MULTi.H265-GRP.mkv").format, .dolbyVisionHDR10)
        XCTAssertEqual(picture("Film.2024.2160p.WEB-DL.DV.P5.H265-GRP.mkv").format, .dolbyVisionOnly)
        XCTAssertEqual(picture("Film.2024.2160p.DV.x265.mkv").format, .dolbyVision, "the source unknown: just Dolby Vision")
        XCTAssertEqual(picture("Film.2021.2160p.WEB-DL.Dolby.Vision.HEVC-GRP.mkv").format, .dolbyVisionOnly)
    }

    func testSDRSaidOutright() {
        XCTAssertEqual(picture("Film (2026) 2160p 10bit UHD BluRay REMUX HEVC SDR x265.mkv").setting, .sdr, "a 4K disc without HDR")
        XCTAssertEqual(picture("Film 2025 2160p NF 10bit WEB-DL SDR HEVC H.265-GRP.mkv").basis, .named)
        XCTAssertEqual(picture("Film.2020.2160p.UHD.BluRay.Tonemapped.x265-GRP.mkv").setting, .sdr)
        XCTAssertEqual(picture("Film.2020.2160p.HDR.to.SDR.x265-GRP.mkv").setting, .sdr)
        XCTAssertEqual(picture("Film.2020.2160p.UHD.BluRay.Tonemapped.x265-GRP.mkv").label, "SDR")
    }

    // MARK: What the file is

    func testWhatCantCarryHDR() {
        let bluRay = picture("Film.2014.BluRay.Remux.1080p.AVC.DTS-HD.MA.7.1-GRP.mkv")
        XCTAssertEqual(bluRay.setting, .sdr)
        XCTAssertEqual(bluRay.basis, .source)
        XCTAssertTrue(bluRay.reason.contains("1080p Blu-ray"), bluRay.reason)
        XCTAssertEqual(picture("Film (2016) 1080p Open Matte BluRay x265 HEVC 10bit.mkv").basis, .source, "10-bit isn't HDR")
        let avc = picture("Film.2023.1080p.AMZN.WEB-DL.DUAL.DDP5.1.H.264-GRP.mkv")
        XCTAssertEqual(avc.setting, .sdr)
        XCTAssertEqual(avc.basis, .source)
        XCTAssertTrue(avc.reason.contains("H.264"), avc.reason)
        XCTAssertEqual(picture("Film.1995.1080p.BluRay.REMUX.VC1.TrueHD.5.1-GRP.mkv").basis, .source)
        XCTAssertEqual(picture("Film.2001.DVD.mkv").setting, .sdr)
        XCTAssertEqual(picture("Film (1999) DVDRip XviD.avi").basis, .source)
        XCTAssertEqual(picture("Film.2018.720p.WEB.mkv").setting, .sdr)
        // HDRip is an old word for a rip of an HD source.
        XCTAssertEqual(picture("Film.2019.1080p.HDRip.x264-GRP.mkv").setting, .sdr)
        // The uploader's site name isn't 4K; a 4K remaster on a 1080p Blu-ray is still a 1080p Blu-ray.
        XCTAssertEqual(picture("Film 2020 1080p BluRay x264 (4kHDHub).mkv").basis, .source)
        XCTAssertEqual(picture("Film.1976.4K.Remaster.1080p.BluRay.Opus.5.1.AV1-GRP.mkv").basis, .source)
        XCTAssertEqual(picture("Film 1996 RM4K 1080p BluRay x265 10bit GRP.mkv").basis, .source)
        XCTAssertEqual(picture("Film [Bluray-1080p].mkv").basis, .source)
        // An audio track taken from a DVD doesn't make the film a DVD.
        XCTAssertTrue(picture("Film (2011) 1080p 10bit BluRay x265 HEVC [Hindi (Org DVD DD 5.1) + English DDP 5.1].mkv").reason.contains("Blu-ray"))
    }

    // MARK: Likely, said as a guess

    func testLikelyFromTheKindOfRelease() {
        let web = picture("Film.2025.2160p.AMZN.WEB-DL.DDP5.1.H.265-GRP.mkv")
        XCTAssertEqual(web.setting, .sdr)
        XCTAssertEqual(web.basis, .likely)
        XCTAssertEqual(web.label, "Likely SDR")
        XCTAssertTrue(web.reason.hasPrefix("A 4K web release"), web.reason)
        XCTAssertEqual(picture("Film (2019) [WEBDL-2160p].mkv").label, "Likely SDR")
        let disc = picture("Film.2018.UHD.BluRay.2160p.TrueHD.Atmos.7.1.HEVC.HYBRID.REMUX-GRP.mkv")
        XCTAssertEqual(disc.setting, .hdr)
        XCTAssertEqual(disc.label, "Likely HDR")
        XCTAssertTrue(disc.isHDR)
        XCTAssertEqual(picture("Film (2014) 1080p UHD BluRay 10bit HEVC x265.mkv").label, "Likely SDR", "a 1080p copy of a 4K disc that doesn't say HDR")
        XCTAssertEqual(picture("Film 1999 1080p 10bit DS4K BluRay x265 HEVC.mkv").basis, .likely, "made from a 4K source")
        XCTAssertEqual(picture("Film.1997.1080p.NF.WEB-DL.DDP5.1.H.265-GRP.mkv").label, "Likely SDR")
        XCTAssertEqual(picture("Film.Extended.1994.Dual.1080p.mkv").label, "Likely SDR")
        XCTAssertEqual(picture("Film.2025.2160p.AMZN.WEB-DL.H.265-GRP.mkv").searchWords, ["SDR"])
    }

    func testNotStated() {
        let found = picture("2013. Furious 6 [Extended.Cut].mkv")
        XCTAssertNil(found.label)
        XCTAssertFalse(found.isHDR)
        XCTAssertFalse(found.isKnown)
        XCTAssertEqual(found.basis, .notStated)
        XCTAssertTrue(found.searchWords.isEmpty, "a search for SDR doesn't find it")
        XCTAssertNil(picture("Film.2024.2160p.x265.mkv").label, "4K of an unknown kind can be either")
    }

    /// Found by the independent review.
    func testReviewedCases() {
        XCTAssertEqual(FilenameParser.parse("Film.2020.2160p.HDR.to.SDR.x265-GRP.mkv").hdr, "SDR", "made from HDR, but SDR")
        XCTAssertEqual(picture("Film.2160p.WEB-DL.DVHDR10.H265-GRP.mkv").format, .dolbyVisionHDR10, "run together")
        XCTAssertEqual(picture("Film.2020.4KHDR.WEB-DL.H265-GRP.mkv").setting, .hdr)
        let remaster = FilenameParser.parse("Film.1976.4K.Remaster.BluRay.x265-GRP.mkv")
        XCTAssertNil(remaster.resolution, "a 4K remaster isn't a 4K file")
        XCTAssertNotEqual(picture("Film.1976.4K.Remaster.BluRay.x265-GRP.mkv").label, "Likely HDR")
        XCTAssertNil(FilenameParser.parse("Film.1999.Remastered.4K.1080p.BluRay.x265-GRP.mkv").pictureWords.written)
        XCTAssertEqual(picture("Film.2023.iPhone.DV.P8.4.HEVC.mov").format, .dolbyVisionHLG)
    }

    // MARK: Folders

    func testTheFilmsOwnFolder() {
        let found = picture("dune.mkv", folder: "Dune (2021) 2160p DV HDR10")
        XCTAssertEqual(found.setting, .hdr)
        XCTAssertEqual(found.format, .dolbyVisionHDR10)
        XCTAssertEqual(found.basis, .folder)
        XCTAssertEqual(picture("dune.mkv").basis, .notStated, "no folder of its own")
        XCTAssertEqual(picture("Dune.2021.1080p.BluRay.x264.mkv", folder: "Dune 2160p DV").setting, .sdr, "the file's own name comes first")
        XCTAssertEqual(picture("Film.2020.1080p.mkv", folder: "Film (2020) 1080p HDR10").basis, .folder, "a folder that says beats a guess")
        let collection = "Saga - Complete Collection (2001-2021) 1080p HEVC HDR10 [BluRay]"
        XCTAssertEqual(picture("Fast.Five.2011.1080p.BluRay.x265.mkv", folder: collection).setting, .hdr,
                       "a 1080p 'BluRay' in a folder that says HDR10 is a copy of a 4K disc")
        XCTAssertEqual(picture("Fast.Five.2011.1080p.BluRay.x264.mkv", folder: collection).setting, .sdr, "H.264 can't be HDR, whatever the folder says")
    }

    /// A whole collection in one folder whose name says the picture.
    func testACollectionFolderSpeaksForEachFilm() {
        let folder = "The Fast Saga - Complete Collection (2001-2021) 1080p HEVC HDR10 DTS 7.1.x265 [BluRay] {GRP}"
        let found = picture("2013. Furious 6 [Extended.Cut].mkv", folder: folder)
        XCTAssertEqual(found.setting, .hdr)
        XCTAssertEqual(found.format, .hdr10)
        XCTAssertEqual(found.basis, .folder)
        XCTAssertTrue(FilePicture.isCollection(folder))
        XCTAssertTrue(FilePicture.isCollection("The Godfather Trilogy 2160p DV"))
        XCTAssertTrue(FilePicture.isCollection("Alien Anthology 1979-1997 1080p"))
        XCTAssertFalse(FilePicture.isCollection("4K HDR Films"), "assorted films: their folder says nothing about each")
        XCTAssertFalse(FilePicture.isCollection("Movies 2160p"))
        XCTAssertFalse(FilePicture.isCollection("Blade Runner 2049 (2017) 2160p"), "a title with a number isn't a span of years")
    }

    func testWhichFoldersSpeak() {
        func entry(_ path: String, collection: Int? = nil, id: Int = 1) -> FilmEntry {
            var film = FilmEntry(driveID: "D", relativePath: path, fileName: (path as NSString).lastPathComponent, size: 1, modified: nil, addedAt: Date())
            var details = TMDBMovieDetails(id: id, title: path)
            details.collection = collection.map { TMDBCollectionRef(id: $0, name: "Set") }
            film.tmdb = details
            return film
        }
        let films = [entry("Fast Collection (2001-2021) HDR10/a.mkv", collection: 9), entry("Fast Collection (2001-2021) HDR10/b.mkv", collection: 9),
                     entry("Fast Collection (2001-2021) HDR10/spinoff.mkv", collection: 10),
                     entry("Criterion Collection DV/x.mkv", collection: 1), entry("Criterion Collection DV/y.mkv", collection: 2),
                     entry("Criterion Collection DV/z.mkv"),
                     entry("4K HDR Films/c.mkv"), entry("4K HDR Films/d.mkv"), entry("Dune 2160p DV/dune.mkv"), entry("top.mkv")]
        let names = FilePicture.ownFolderNames(films)
        XCTAssertEqual(Set(names.values), ["Fast Collection (2001-2021) HDR10", "Dune 2160p DV"],
                       "a collection's folder (two of three films of one collection) speaks; assorted films' doesn't")
        XCTAssertEqual(names.count, 4)
    }

    // MARK: Yours

    func testYourSettingWins() {
        let found = picture("Film.2021.2160p.WEB-DL.DV.HDR.HEVC-GRP.mkv", yours: .sdr)
        XCTAssertEqual(found.setting, .sdr)
        XCTAssertEqual(found.basis, .yours)
        XCTAssertEqual(picture("2013. Furious 6.mkv", yours: .hdr).label, "HDR")
        XCTAssertEqual(picture("2013. Furious 6.mkv", yours: .dolbyVision).label, "HDR", "an older Reel's Dolby Vision setting is HDR")
        XCTAssertEqual(picture("Film.2021.2160p.UHD.BluRay.REMUX.DV.HDR.HEVC-GRP.mkv", yours: .hdr).format, .dolbyVisionHDR10,
                       "the name's format, when it agrees")
        XCTAssertEqual(FilePicture.choices, [.hdr, .sdr], "all a Mac's display has")
        let slip = picture("Film (2006) 1080p BluRay REMUX AVC [English DTS-HD MA 5.1].mkv", yours: .hdr)
        XCTAssertEqual(slip.setting, .hdr, "yours still wins")
        XCTAssertNotNil(slip.against, "but a 1080p H.264 Blu-ray can't be HDR: said")
        XCTAssertNil(picture("Film (2006) 1080p BluRay REMUX AVC.mkv", yours: .sdr).against)
        XCTAssertNil(picture("2013. Furious 6.mkv", yours: .hdr).against, "nothing to go against")
        XCTAssertNil(picture("Film.2025.2160p.AMZN.WEB-DL.H.265-GRP.mkv", yours: .hdr).against, "a guess isn't proof")
    }

    func testSearchWords() {
        XCTAssertEqual(picture("Film.2024.2160p.UHD.BluRay.REMUX.DV.HDR.HEVC-GRP.mkv").searchWords, ["HDR", "Dolby Vision", "HDR10"])
        XCTAssertEqual(picture("Film.1995.1080p.BluRay.x264-GRP.mkv").searchWords, ["SDR"])
    }

    func testPictureWordsAsWritten() {
        XCTAssertEqual(PictureWords.read("Film.2160p.DV.HDR10+.mkv").written, "DV HDR10+")
        XCTAssertEqual(PictureWords.read("Film 2160p DoVi HDR").written, "DV HDR")
        XCTAssertEqual(PictureWords.read("Film.2160p.HLG").written, "HLG")
        XCTAssertNil(PictureWords.read("Film.1080p.HDRip.DVDRip").written)
        XCTAssertNil(PictureWords.read("Film.2020.DVD").dolbyVisionProfile)
        XCTAssertEqual(PictureWords.read("Film.UHD.BluRay.DV.P8.HDR").dolbyVisionProfile, 8)
        XCTAssertEqual(PictureWords.read("Film.UHD.BluRay.DV.FEL.HDR").dolbyVisionProfile, 7)
    }
}
