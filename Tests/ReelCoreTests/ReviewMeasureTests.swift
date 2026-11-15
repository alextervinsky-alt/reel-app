import Foundation
import XCTest
@testable import ReelCore

/// Code review 1.11, scratch branch `review-1.11` only (throwaway, never merged): the drive scan,
/// the file-name reader and match scoring at about 300 films (550 files), with synthetic names in a
/// temporary folder. Prints "REVIEW| " lines; asserts nothing about speed.
final class ReviewMeasureTests: XCTestCase {
    private func ms(_ start: Date) -> String { String(format: "%.1f", Date().timeIntervalSince(start) * 1000) }

    func testScanParseAndMatchAt300Films() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let words = ["Harbour", "Quiet", "Night", "Glass", "River", "North", "Summer", "Last", "Long", "Silent", "Red", "Winter"]
        let tags = ["2160p.UHD.BluRay.HDR10.x265", "1080p.BluRay.x264", "2160p.WEB-DL.DV.HDR10", "720p.WEBRip", "1080p.REMUX.AVC"]
        var titles: [(String, Int)] = []
        for i in 0..<300 {
            let title = "\(words[i % words.count]) \(words[(i / words.count) % words.count]) \(i)"
            let year = 1950 + (i * 7) % 75
            titles.append((title, year))
            let folder = root.appendingPathComponent("\(title) (\(year))", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = title.replacingOccurrences(of: " ", with: ".") + ".\(year).\(tags[i % tags.count])"
            FileManager.default.createFile(atPath: folder.appendingPathComponent(name + ".mkv").path, contents: Data(count: 16))
            // Every other film has subtitles, every fifth an extra, every sixth a second cut.
            if i % 2 == 0 { FileManager.default.createFile(atPath: folder.appendingPathComponent(name + ".en.srt").path, contents: Data(count: 8)) }
            if i % 5 == 0 {
                let extras = folder.appendingPathComponent("Extras", isDirectory: true)
                try FileManager.default.createDirectory(at: extras, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: extras.appendingPathComponent("Making of.mkv").path, contents: Data(count: 16))
            }
            if i % 6 == 0 {
                FileManager.default.createFile(atPath: folder.appendingPathComponent(name + ".Directors.Cut.mkv").path, contents: Data(count: 16))
            }
        }
        var start = Date()
        let scan = DriveScanner.scan(root: root, minimumSize: 0)
        print("REVIEW| drive scan of 300 film folders (synthetic, \(scan.files.count) films found): \(ms(start)) ms")
        start = Date()
        let parsed = scan.files.map { FilenameParser.parse($0.relativePath) }
        print("REVIEW| file-name reader, \(parsed.count) names: \(ms(start)) ms")
        // Twenty candidates a film, as a TMDB search returns.
        let candidates = (0..<20).map { TMDBMovieSummary(id: $0, title: "\(words[$0 % words.count]) \(words[($0 + 3) % words.count])", releaseDate: "\(1950 + $0 * 3)-01-01") }
        start = Date()
        var best = 0.0
        for name in parsed {
            for candidate in candidates { best = max(best, FilmMatcher.score(candidate, title: name.title, year: name.year)) }
        }
        print("REVIEW| match scoring, \(parsed.count) names × 20 candidates: \(ms(start)) ms (best \(String(format: "%.2f", best)))")
        XCTAssertFalse(scan.files.isEmpty)
    }
}
