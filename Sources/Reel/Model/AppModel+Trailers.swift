#if os(macOS)
import Foundation
import ReelCore

/// A trailer to play over the page: the official videos to try in order, and what the panel
/// under the player shows.
struct TrailerRequest: Equatable {
    /// YouTube keys, best first (see `Trailers.candidates`).
    let videos: [String]
    let title: String
    /// The film in the library (nil for a film you don't own, from Explore).
    let filmID: String?
    let tmdbID: Int?
    let backdropPath: String?
    /// Where the poster was on screen, in window coordinates: the player grows from there.
    var origin: CGRect?
    /// Shows Open Film under the player (not when the trailer was started from the film page).
    var offersFilmPage = true
}

/// Trailers: only official ones (see `Trailers`), played inside Reel. In Cinema mode Reel never
/// opens a browser; a film whose trailers won't play here loses its button for the session.
extension AppModel {
    /// The official videos to try for a film: a teaser first for an unwatched film while
    /// spoiler-safe is on (it shows less), otherwise the trailer.
    func trailerVideos(for film: FilmEntry) -> [TMDBVideo] {
        guard let details = film.tmdb, !unplayableTrailers.contains(details.id) else { return [] }
        let stored = details.videos?.results ?? []
        let fetched = fetchedVideos[details.id] ?? []
        return Trailers.candidates(fetched + stored, preferTeaser: hidesSpoilers(for: film),
                                   originalLanguage: details.originalLanguage)
    }

    /// Whether to offer a trailer button: in Cinema mode only while trailers play inside Reel.
    func offersTrailer(for film: FilmEntry) -> Bool {
        (!cinemaMode || trailersPlayInReel) && !trailerVideos(for: film).isEmpty
    }

    /// "Teaser" or "Trailer", for the button.
    func trailerLabel(for film: FilmEntry) -> String {
        trailerVideos(for: film).first?.type == "Teaser" ? "Teaser" : "Trailer"
    }

    func showTrailer(for film: FilmEntry, from origin: CGRect? = nil, offersFilmPage: Bool = false) {
        let videos = trailerVideos(for: film)
        guard !videos.isEmpty else { return }
        TrailerEngine.shared.warm()
        trailer = TrailerRequest(videos: videos.map(\.key), title: film.displayTitle, filmID: film.id, tmdbID: film.tmdb?.id,
                                 backdropPath: film.tmdb?.backdropPath,
                                 origin: origin, offersFilmPage: offersFilmPage)
    }

    /// When a film page opens: official videos in the film's own language too, once per session.
    func loadVideos(for film: FilmEntry) async {
        TrailerEngine.shared.warm()
        guard hasToken, let details = film.tmdb, fetchedVideos[details.id] == nil else { return }
        guard let videos = try? await TMDBClient(token: token).videos(id: details.id, originalLanguage: details.originalLanguage)
        else { return } // offline: tried again next time
        fetchedVideos[details.id] = videos
    }

    /// The player's verdict on a film's trailers.
    func trailerResult(tmdbID: Int?, played: Bool) {
        if played {
            trailerFailuresInARow = 0
            return
        }
        if let tmdbID { unplayableTrailers.insert(tmdbID) }
        trailerFailuresInARow += 1
        if trailerFailuresInARow >= 3, trailersPlayInReel { trailersPlayInReel = false }
    }
}
#endif
