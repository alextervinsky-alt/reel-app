import XCTest
@testable import ReelCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Live, in CI only (its own run, so many requests can't stop the other live checks): the most
/// acclaimed films of last year, worked out as the app does it — IMDb's files, the award lists,
/// TMDB's audience and the critics' scores — and written out to compare with what critics' and
/// audiences' round-ups name. A report only: it fails nothing.
final class LiveAcclaimTests: XCTestCase {
    func testTheMostAcclaimedOfLastYear() async throws {
        guard let token = ProcessInfo.processInfo.environment["TMDB_TOKEN"], !token.isEmpty else {
            throw XCTSkip("live tests only")
        }
        let year = Calendar.current.component(.year, from: Date()) - 1
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reel-acclaim-live")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ratings = dir.appendingPathComponent("ratings.tsv.gz"), basics = dir.appendingPathComponent("basics.tsv.gz")
        try await download(IMDbDataset.ratingsURL, to: ratings)
        try await download(IMDbDataset.basicsURL, to: basics)
        let films = try IMDbDataset.build(ratingsFile: ratings, basicsFile: basics)

        var awards: [(award: AwardList, films: [ListFilm])] = []
        for award in AwardList.allCases where award != .criterion {
            awards.append((award, (try? await WikidataLists().films(award)) ?? []))
        }
        let prizes = Acclaim.prizes(awards, year: year)
        let pool = Acclaim.pool(films, year: year, awarded: Set(prizes.keys))
        let client = TMDBClient(token: token)
        var candidates: [Acclaim.Candidate] = []
        for film in pool {
            let found = try? await client.find(imdbID: film.id)
            candidates.append(Acclaim.Candidate(film: film, tmdbVote: found?.voteAverage, tmdbVotes: found?.voteCount,
                                                prize: prizes[film.id]?.prize, prizeName: prizes[film.id]?.name))
        }
        if let key = ProcessInfo.processInfo.environment["OMDB_KEY"], !key.isEmpty {
            let omdb = OMDbClient(key: key)
            let likely = Set(Acclaim.rank(candidates).prefix(50).map { $0.candidate.film.id })
            for index in candidates.indices where likely.contains(candidates[index].film.id) {
                guard let scores = try? await omdb.ratings(imdbID: candidates[index].film.id) else { continue }
                candidates[index].metacritic = scores.metacritic
                candidates[index].rottenTomatoes = scores.rottenTomatoes
            }
        }
        let ranked = Acclaim.rank(candidates)
        let line = ranked.prefix(20).enumerated().map { index, entry in
            "\(index + 1). \(entry.candidate.film.title) (\(Acclaim.note(entry.candidate))\(entry.candidate.prizeName.map { " · \($0)" } ?? ""))"
        }
        print("::notice::Most acclaimed of \(year) (\(pool.count) in the running): \(line.joined(separator: "; "))")
        XCTAssertFalse(ranked.isEmpty)
    }

    private func download(_ url: URL, to file: URL) async throws {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: url) { data, _, error in
                if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: error ?? URLError(.badServerResponse)) }
            }.resume()
        }
        try data.write(to: file)
    }
}
