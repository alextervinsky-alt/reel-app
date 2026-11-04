import Foundation
@testable import ReelCore

// The research benchmark's data (1.10.8): synthetic films, pages and searches, each statement that
// says something about a production labelled with the production it's about. The harness runs the
// production engine (`ResearchEngine`, `CraftReader`, `TechSpecs`) over them through an in-memory
// transport and measures what it accepted against the labels. Nothing real: made-up films, people,
// sites and gear statements (gear names are real products so the reader recognises them).

/// A statement on a page and the production it's about: `film` is the exact title of the film it
/// concerns ("" when it's about no film: a career remark, a company's news).
struct BenchClaim {
    let text: String
    let film: String
    /// Gear it establishes for `film`, as the reader would name it (for recall).
    var gear: [String] = []
}

struct BenchPage {
    let title: String
    let url: String
    /// The site's name as Reel knows it ("American Cinematographer", "Cinesite", "Filmmaker"…).
    let site: String
    /// The page's paragraphs: claims and filler. Each claim's text appears verbatim in one of them.
    let paragraphs: [String]
    let claims: [BenchClaim]
    /// When the page doesn't come: it didn't answer (`.unanswered`), another language, …
    var failure: SourceFailure? = nil
}

/// A provider's answer for one query: its hits (title and address), or that it didn't answer.
struct BenchSearch {
    let provider: String
    let query: String
    let hits: [(title: String, url: String)]
    var failure: String? = nil
}

struct BenchFilm {
    let id: Int
    let title: String
    let year: Int
    let director: String
    /// TMDB jobs and names ("Director of Photography", "Steadicam Operator", "Gaffer", "Colorist",
    /// "Visual Effects Supervisor", "Second Unit Director of Photography"…).
    let crew: [(job: String, name: String)]
    /// Its Wikipedia article's paragraphs (may be empty) and their claims.
    var article: [String] = []
    var articleClaims: [BenchClaim] = []
    /// Pages its first pass read (as the magazines' title searches and Wikipedia's links would).
    var firstPass: [String] = []
    /// What a reading of it should find, at least (gear names), from claims about it.
    var expected: [String] { [] }
}

struct BenchCorpus {
    let name: String
    let films: [BenchFilm]
    let pages: [String: BenchPage]
    let searches: [BenchSearch]

    func search(_ provider: String, _ query: String) -> BenchSearch? {
        searches.first { $0.provider == provider && $0.query.lowercased() == query.lowercased() }
    }

    /// Every labelled claim, with the page it's on.
    var claims: [(claim: BenchClaim, page: String)] {
        pages.values.flatMap { page in page.claims.map { ($0, page.url) } }
            + films.flatMap { film in film.articleClaims.map { ($0, "wikipedia:" + film.title) } }
    }
}
