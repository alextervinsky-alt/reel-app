import XCTest
@testable import ReelCore

final class ReadingTests: XCTestCase {
    // MARK: Spoilers

    func testStoryDetailsAreRecognised() {
        XCTAssertTrue(Spoilers.mentionsPlot("In the final scene, Deckard leaves with Rachael."))
        XCTAssertTrue(Spoilers.mentionsPlot("It turns out the narrator and Tyler are the same man."))
        XCTAssertTrue(Spoilers.mentionsPlot("Bruce Willis's character died in the first scene."))
        XCTAssertTrue(Spoilers.mentionsPlot("The twist was kept secret from most of the crew."))
        XCTAssertFalse(Spoilers.mentionsPlot("Roger Deakins shot the film on an ARRI Alexa with natural light."))
        XCTAssertFalse(Spoilers.mentionsPlot("The studies and melodies of the score took Vangelis two years."), "words inside words don't count")
        XCTAssertTrue(Spoilers.isAfterSection(["Plot"]))
        XCTAssertTrue(Spoilers.isAfterSection(["Themes and interpretations"]))
        XCTAssertFalse(Spoilers.isAfterSection(["Production", "Casting"]))
    }

    func testArticleIsSplitForBeforeAndAfter() {
        let extract = """
        Stalker is a 1979 Soviet science fiction film directed by Andrei Tarkovsky, loosely based on a novel.
        == Plot ==
        A guide leads two men through the Zone to a room said to grant wishes, and what happens there is long.
        == Production ==
        The film was shot twice, after the first year of footage was ruined in development at the laboratory.
        In the final scene, the Stalker's daughter appears to move a glass with her mind across the table.
        === Casting ===
        Nikolai Grinko was cast as the Professor after Tarkovsky saw him in an earlier picture of his own.
        == Cast ==
        Alexander Kaidanovsky as the Stalker, a guide who leads people through the Zone for money.
        == References ==
        Some reference text that is long enough to count as a paragraph of its own here.
        """
        let article = FilmArticle(title: "Stalker (1979 film)", extract: extract)
        XCTAssertEqual(article.before.map { $0.title }, ["About the Film", "Production", "Production · Casting"])
        XCTAssertEqual(article.after.map { $0.title }, ["Plot", "Production"])
        XCTAssertEqual(article.before[1].paragraphs.count, 1, "the paragraph about the final scene moved to After")
        XCTAssertTrue(article.after[1].paragraphs[0].hasPrefix("In the final scene"))
        XCTAssertEqual(article.url?.absoluteString, "https://en.wikipedia.org/wiki/Stalker_(1979_film)")
    }

    // MARK: Badges

    func testBadgesWinsFirst() {
        let pulp = ListFilm(imdbID: "tt0110912", tmdbID: nil, title: "Pulp Fiction", year: 1994, note: "Won 1994", won: true, rank: "1994")
        let lists: [(kind: FilmListKind, films: [ListFilm])] = [
            (.award(.oscarBestPicture), [ListFilm(imdbID: "tt0110912", tmdbID: nil, title: "Pulp Fiction", year: 1994,
                                                  note: nil, won: false, rank: "1995")]),
            (.award(.palmeDOr), [pulp]),
            (.award(.criterion), [ListFilm(imdbID: "tt0110912", tmdbID: nil, title: "Pulp Fiction", year: 1994, note: "Spine #1000")]),
            (.sightAndSound, [ListFilm(imdbID: nil, tmdbID: nil, title: "Pulp Fiction", year: 1994, note: nil, rank: "54")]),
            (.award(.goldenLion), [ListFilm(imdbID: "tt0000001", tmdbID: nil, title: "Other", year: 1994, note: nil, won: true)]),
        ]
        let badges = ListBadges.badges(imdbID: "tt0110912", tmdbID: 680, title: "Pulp Fiction", year: 1994,
                                       lists: lists, tmdbIDOf: { _ in nil })
        XCTAssertEqual(badges.map { $0.text }, [
            "Palme d'Or · 1994", "Sight & Sound greatest films · #54", "Criterion Collection · Spine #1000",
            "Nominated: Oscar for Best Picture · 1995",
        ])
    }

    // MARK: Taste

    func testRatingsShapeTheReason() {
        func film(_ id: String, director: String, dp: String = "", moods: [Mood] = [], genres: [String] = ["Drama"]) -> TasteFeatures {
            TasteFeatures(id: id, title: id, directors: [director], cinematographers: dp.isEmpty ? [] : [dp], moods: moods,
                          keywords: [], genres: genres)
        }
        let profile = TasteProfile(rated: [
            (film("Stalker", director: "Tarkovsky", moods: [.mindBending]), 5),
            (film("Sicario", director: "Villeneuve", dp: "Roger Deakins", moods: [.gripping]), 4),
            (film("Bad", director: "Someone", moods: [.funny], genres: ["Comedy"]), 1),
        ])
        XCTAssertEqual(profile.match(film("Solaris", director: "Tarkovsky")).reason?.long, "From the director of Stalker")
        XCTAssertEqual(profile.match(film("Skyfall", director: "Mendes", dp: "Roger Deakins")).reason?.long,
                       "Shot by Roger Deakins, like Sicario")
        let comedy = profile.match(film("Other", director: "X", moods: [.funny], genres: ["Comedy"]))
        XCTAssertLessThan(comedy.score, 0, "like a film you rated low")
        XCTAssertNil(comedy.reason)
        XCTAssertTrue(TasteProfile(rated: []).isEmpty)

        // A list film, known only by its directors and genres.
        let byTarkovsky = profile.fit(directors: ["Tarkovsky"], genres: ["Drama"])
        XCTAssertEqual(byTarkovsky.sameDirectorAs, "Stalker")
        XCTAssertEqual(byTarkovsky.score, 3, accuracy: 0.001)
        XCTAssertLessThan(profile.fit(directors: [], genres: ["Comedy"]).score, profile.fit(directors: [], genres: ["Drama"]).score)
        XCTAssertEqual(TasteProfile(rated: []).fit(directors: ["Tarkovsky"], genres: ["Drama"]).score, 0)
    }

    // MARK: Evenings and files

    func testEveningRunsPastMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let ninePM = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 21))!
        let oneAM = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 1))!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))!
        XCTAssertEqual(Evening.of(ninePM, calendar: calendar), "2026-10-06")
        XCTAssertEqual(Evening.of(oneAM, calendar: calendar), "2026-10-06")
        XCTAssertEqual(Evening.of(noon, calendar: calendar), "2026-10-07")

        let film = FilmEntry(driveID: "D", relativePath: "Dune.2021.2160p.HDR.mkv", fileName: "Dune.2021.2160p.HDR.mkv",
                             size: 1, modified: nil, addedAt: ninePM,
                             extras: [FilmExtra(relativePath: "Dune.2021.en.srt", size: 1, kind: .subtitle),
                                      FilmExtra(relativePath: "Dune.2021.et.srt", size: 1, kind: .subtitle)])
        XCTAssertEqual(film.qualityLabel, "4K · HDR")
        XCTAssertEqual(film.subtitleLanguages, ["English", "Estonian"])
        XCTAssertTrue(film.hasSubtitles)
    }
}
