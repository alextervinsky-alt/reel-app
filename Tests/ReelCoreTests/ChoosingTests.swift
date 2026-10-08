import XCTest
@testable import ReelCore

final class ChoosingTests: XCTestCase {
    // MARK: Reasons

    func testReasonsFollowTheOrderAndAlwaysExist() {
        XCTAssertEqual(PickReason.pick(taste: .director(film: "Her"), onWatchlist: true, newOn: "Films", listed: nil, mood: ""),
                       .director(film: "Her"))
        XCTAssertEqual(PickReason.pick(taste: nil, onWatchlist: true, newOn: "Films", listed: "Palme d'Or · 2019", mood: ""), .watchlist)
        XCTAssertEqual(PickReason.pick(taste: nil, onWatchlist: false, newOn: "Films", listed: "Palme d'Or · 2019", mood: ""),
                       .new(drive: "Films"))
        XCTAssertEqual(PickReason.pick(taste: nil, onWatchlist: false, newOn: nil, listed: "Palme d'Or · 2019", mood: "Dark").short,
                       "Palme d'Or 2019")
        XCTAssertEqual(PickReason.pick(taste: nil, onWatchlist: false, newOn: nil, listed: nil, mood: "Dark").short, "Top rated dark")
    }

    func testShortReasonsFitAPoster() {
        let reasons: [PickReason] = [
            .director(film: "Eternal Sunshine of the Spotless Mind"), .alike(film: "The Assassination of Jesse James"),
            .cinematographer(name: "Roger Deakins", film: "Sicario"), .listed("Sight & Sound greatest films · #90"),
            .bestInMood("Mind-bending"),
        ]
        for reason in reasons {
            XCTAssertLessThanOrEqual(reason.short.count, PickReason.shortLimit, reason.short)
        }
        XCTAssertEqual(PickReason.director(film: "Her").short, "Director of Her")
        XCTAssertEqual(PickReason.cinematographer(name: "Roger Deakins", film: "Sicario").short, "Shot by Deakins")
        XCTAssertTrue(PickReason.alike(film: "The Assassination of Jesse James").short.hasSuffix("…"))
    }

    // MARK: Evening order

    func testEveningOrderKeepsBandsAndChangesWithinThem() {
        struct Film { let id: String; let score: Double? }
        let films = (0..<20).map { Film(id: "f\($0)", score: $0 < 10 ? 8.6 : 7.1) } + [Film(id: "x", score: nil)]
        let monday = EveningOrder.arrange(films, evening: "2026-10-05", id: { $0.id }, score: { $0.score })
        let tuesday = EveningOrder.arrange(films, evening: "2026-10-06", id: { $0.id }, score: { $0.score })
        XCTAssertEqual(monday.prefix(10).map(\.score), Array(repeating: 8.6, count: 10), "the 8.5–8.9 band stays first")
        XCTAssertEqual(monday.last?.id, "x", "unrated films stay at the end")
        XCTAssertEqual(monday.map(\.id), EveningOrder.arrange(films, evening: "2026-10-05", id: { $0.id }, score: { $0.score }).map(\.id),
                       "the same all evening")
        XCTAssertNotEqual(monday.map(\.id), tuesday.map(\.id), "different the next evening")
    }

    // MARK: Same people

    private func film(_ id: Int, director: String, writers: [String] = [], dp: String = "", composer: String = "",
                      cast: [String] = []) -> LikenessFeatures {
        LikenessFeatures(tmdbID: id, directors: [director], writers: writers, cinematographers: dp.isEmpty ? [] : [dp], cast: cast,
                         composers: composer.isEmpty ? [] : [composer], genres: [], keywords: [], moods: [], year: nil)
    }

    func testSamePeopleNamesTheStrongestConnection() {
        let poorThings = film(1, director: "Yorgos Lanthimos", dp: "Robbie Ryan", cast: ["Emma Stone", "Mark Ruffalo"])
        XCTAssertEqual(SamePeople.connection(of: poorThings, to: film(2, director: "Yorgos Lanthimos", dp: "Robbie Ryan"))?.label,
                       "Director · Yorgos Lanthimos")
        XCTAssertEqual(SamePeople.connection(of: poorThings, to: film(3, director: "Andrea Arnold", dp: "Robbie Ryan"))?.label,
                       "Cinematographer · Robbie Ryan")
        XCTAssertEqual(SamePeople.connection(of: poorThings, to: film(4, director: "Damien Chazelle", cast: ["Ryan Gosling", "Emma Stone"]))?.label,
                       "With · Emma Stone")
        XCTAssertEqual(SamePeople.connection(of: poorThings, to: film(5, director: "Someone", cast: ["Extra", "Mark Ruffalo"]))?.label,
                       "With · Mark Ruffalo")
        XCTAssertNil(SamePeople.connection(of: poorThings, to: film(6, director: "Someone Else")))
    }

    // MARK: Languages

    func testLanguages() {
        XCTAssertEqual(FilmLanguage.code("cn"), "zh")
        XCTAssertNil(FilmLanguage.code("xx"))
        XCTAssertEqual(FilmLanguage.name("ko"), "Korean")
        XCTAssertEqual(FilmLanguage.name("et"), "Estonian")
    }

    // MARK: Trailers

    func testOnlyOfficialTrailersAndTeasersInTheRightOrder() {
        let videos = [
            TMDBVideo(key: "fan", site: "YouTube", type: "Trailer", official: false, language: "en", publishedAt: "2019-01-01"),
            TMDBVideo(key: "clip", site: "YouTube", type: "Clip", official: true, language: "en", publishedAt: "2019-01-01"),
            TMDBVideo(key: "vimeo", site: "Vimeo", type: "Trailer", official: true, language: "en"),
            TMDBVideo(key: "trailer2", site: "YouTube", type: "Trailer", official: true, language: "en", publishedAt: "2019-06-01"),
            TMDBVideo(key: "trailer1", site: "YouTube", type: "Trailer", official: true, language: "en", publishedAt: "2019-03-01"),
            TMDBVideo(key: "teaser", site: "YouTube", type: "Teaser", official: true, language: "en", publishedAt: "2019-02-01"),
            TMDBVideo(key: "korean", site: "YouTube", type: "Trailer", official: true, language: "ko", publishedAt: "2018-12-01"),
            TMDBVideo(key: "french", site: "YouTube", type: "Trailer", official: true, language: "fr"),
        ]
        XCTAssertEqual(Trailers.candidates(videos, title: nil, preferTeaser: false, originalLanguage: "ko").map(\.key),
                       ["trailer1", "trailer2", "teaser", "korean"])
        XCTAssertEqual(Trailers.candidates(videos, title: nil, preferTeaser: true, originalLanguage: "ko").map(\.key),
                       ["teaser", "trailer1", "trailer2", "korean"])
        let korean = videos.filter { $0.language != "en" }
        XCTAssertEqual(Trailers.candidates(korean, title: nil, preferTeaser: false, originalLanguage: "ko").map(\.key), ["korean"])
    }

    func testATeaserInTheFilmsLanguageBeatsAnEnglishTrailerWhenSpoilerSafe() {
        let videos = [
            TMDBVideo(key: "english", site: "YouTube", type: "Trailer", official: true, language: "en", publishedAt: "2019-05-01"),
            TMDBVideo(key: "teaser", site: "YouTube", type: "Teaser", official: true, language: "ko", publishedAt: "2019-03-01"),
        ]
        XCTAssertEqual(Trailers.candidates(videos, title: nil, preferTeaser: true, originalLanguage: "ko").map(\.key), ["teaser", "english"])
        XCTAssertEqual(Trailers.candidates(videos, title: nil, preferTeaser: false, originalLanguage: "ko").map(\.key), ["english", "teaser"])
    }

    func testTheNameDecidesWhatIsATrailer() {
        func video(_ key: String, _ name: String, type: String = "Trailer", official: Bool = true, date: String = "2020-01-01") -> TMDBVideo {
            TMDBVideo(key: key, site: "YouTube", type: type, name: name, official: official, language: "en", publishedAt: date)
        }
        let videos = [
            video("spot", "TV Spot - \"Revenge\"", date: "2019-01-01"),
            video("date", "Release Date Announcement", type: "Teaser", date: "2019-01-02"),
            video("clip", "Official Clip: The Kitchen", type: "Teaser", date: "2019-01-03"),
            video("reaction", "Critics React", date: "2019-01-04"),
            video("look", "First Look", type: "Teaser", date: "2019-01-05"),
            video("tease", "Trailer Tease", type: "Teaser", date: "2019-01-06"),
            video("teaser", "Official Teaser", type: "Teaser", date: "2019-03-01"),
            video("trailer", "Official Trailer", date: "2019-06-01"),
            video("archive", "The Interview (2014) Trailer", official: false, date: "2014-01-01"),
            video("fan", "Concept Video", official: false),
        ]
        XCTAssertEqual(Trailers.candidates(videos, title: "The Interview", preferTeaser: false, originalLanguage: nil).map(\.key),
                       ["trailer", "teaser", "archive"], "the studio's own first; the title isn't mistaken for an interview")
        XCTAssertEqual(Trailers.candidates(videos, title: "The Interview", preferTeaser: true, originalLanguage: nil).map(\.key),
                       ["teaser", "trailer", "archive"], "a teaser named one, never an announcement labelled Teaser")
        XCTAssertEqual(Trailers.candidates(videos, title: nil, preferTeaser: false, originalLanguage: nil).map(\.key),
                       ["trailer", "teaser"], "without the title the archive upload reads as an interview")
        let onlyOthers = [video("old", "Rashomon - Original Trailer (1950)", official: false), video("x", "Rashomon", official: false)]
        XCTAssertEqual(Trailers.candidates(onlyOthers, title: "Rashomon", preferTeaser: false, originalLanguage: nil).map(\.key), ["old"],
                       "an older film still has its trailer")
    }
}
