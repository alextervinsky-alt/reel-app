#if os(macOS)
import Foundation
import Observation
import ReelCore

/// One film, observed on its own: a film page reads its film from here, so a change to another
/// film (background info arriving) doesn't redraw it (1.11, spec §9.2).
@Observable @MainActor
final class FilmBox {
    var film: FilmEntry?
    init(_ film: FilmEntry?) { self.film = film }
}

extension AppModel {
    /// The copy with this id, observed on its own (see `FilmBox`).
    func filmEntry(_ id: String) -> FilmEntry? {
        if let box = filmBoxes[id] { return box.film }
        // Found without reading `films` (observed), so the page depends on its box alone.
        let known = itemCache.values.lazy.flatMap(\.copies).first { $0.id == id }
        let box = FilmBox(known ?? films.first { $0.id == id })
        filmBoxes[id] = box
        return box.film
    }

    /// Whether any copy of the film has extras, without reading the whole library (so a page
    /// asking isn't redrawn when another film changes; its own film changing redraws it).
    func hasExtras(_ film: FilmEntry) -> Bool {
        if !film.extras.isEmpty { return true }
        return itemCache[film.personalKey]?.copies.contains { !$0.extras.isEmpty } ?? false
    }

    /// Tells each open page's film what changed, and only those whose film did change.
    func updateFilmBoxes() {
        guard !filmBoxes.isEmpty else { return }
        let wanted = Set(filmBoxes.keys)
        var found: [String: FilmEntry] = [:]
        for film in films where wanted.contains(film.id) { found[film.id] = film }
        for (id, box) in filmBoxes where box.film != found[id] {
            box.film = found[id]
        }
        // Boxes for pages long closed would only grow: at most 200 are kept.
        if filmBoxes.count > 200 {
            for id in filmBoxes.keys.prefix(filmBoxes.count - 200) { filmBoxes[id] = nil }
        }
    }
}
#endif
