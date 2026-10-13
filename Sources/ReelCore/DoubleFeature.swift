import Foundation

/// "Pair it with": one film from your own library to watch with this one as a double feature,
/// and why: two by the same director, the same cinematographer's eye, the same writer, a shared
/// lead, the same rare theme, or the same way of shooting (black and white, 16 mm). The pair has
/// to be alike enough in tone and audience (see `Likeness`); one you haven't seen is preferred.
public enum DoubleFeature {
    /// A film as the pairing sees it.
    public struct Film: Sendable {
        public let id: String
        public let features: LikenessFeatures
        public let collectionID: Int?
        /// What it was shot on and the gear and techniques read about it (see `CraftIndex`).
        public let shotOn: Set<ShotOn>
        public let craftNames: [String]
        public let watched: Bool

        public init(id: String, features: LikenessFeatures, collectionID: Int?, shotOn: Set<ShotOn>, craftNames: [String],
                    watched: Bool) {
            self.id = id
            self.features = features
            self.collectionID = collectionID
            self.shotOn = shotOn
            self.craftNames = craftNames
            self.watched = watched
        }
    }

    public struct Pick: Equatable, Sendable {
        public let id: String
        /// "Two by Denis Villeneuve, seven years apart"
        public let reason: String
    }

    /// Themes too common or too dry to pair films by.
    static let plainThemes: Set<String> = [
        "based on novel or book", "based on true story", "woman director", "duringcreditsstinger", "aftercreditsstinger",
        "sequel", "remake", "biography", "independent film", "based on comic", "based on short story", "based on play or musical",
        "anime", "live action remake", "3d", "imax",
    ]

    /// Ways of shooting worth a double feature (not "digital" or "anamorphic": too many films are).
    static let distinctiveCraft = ["16 mm", "Super 16 mm", "Super 8 mm", "65 mm", "70 mm", "VistaVision", "IMAX", "Techniscope",
                                   "Ultra Panavision 70", "Three-strip Technicolor", "Natural light", "Candlelight", "Handheld",
                                   "SnorriCam", "LED volume", "Bleach bypass"]

    /// The best partner for `film` among `others`, or nil when none is a good enough match.
    public static func pick(for film: Film, from others: [Film], keywordCounts: [String: Int], libraryCount: Int) -> Pick? {
        var best: (film: Film, score: Double, reason: String)?
        for other in others where other.id != film.id {
            // A sequel is next in its series, not a double feature's surprise.
            if let series = film.collectionID, series == other.collectionID { continue }
            guard let (bonus, reason) = connection(film, other, keywordCounts: keywordCounts, libraryCount: libraryCount) else { continue }
            let alike = Likeness.score(film.features, other.features, keywordCounts: keywordCounts, libraryCount: libraryCount)
            // Tone and audience must sit together (Likeness halves or worse a mismatch).
            guard alike >= 1.5 else { continue }
            let score = alike + bonus + (other.watched ? 0 : 1)
            if score > (best?.score ?? 0) { best = (other, score, reason) }
        }
        return best.map { Pick(id: $0.film.id, reason: $0.reason) }
    }

    /// What the two share that makes them a pair, the strongest first, and how much it counts.
    static func connection(_ a: Film, _ b: Film, keywordCounts: [String: Int], libraryCount: Int) -> (Double, String)? {
        let x = a.features, y = b.features
        if let name = first(x.directors, y.directors) {
            var reason = "Two by \(name)"
            if let ya = x.year, let yb = y.year, ya != yb {
                let gap = abs(ya - yb)
                reason += gap == 1 ? ", a year apart" : ", \(gap) years apart"
            }
            return (4, reason)
        }
        if let name = first(x.cinematographers, y.cinematographers) { return (3.5, "Both shot by \(name)") }
        if let name = first(x.writers, y.writers) { return (3, "Both written by \(name)") }
        if let shared = distinctiveCraft.first(where: { a.craftNames.contains($0) && b.craftNames.contains($0) }) {
            return (3, craftReason(shared))
        }
        if a.shotOn.contains(.blackAndWhite), b.shotOn.contains(.blackAndWhite) { return (3, "Both in black and white") }
        if let name = x.leads.first(where: { y.leads.contains($0) }) { return (2.5, "\(name) in both") }
        if let name = first(x.composers, y.composers) { return (2, "Both scored by \(name)") }
        // The rarest theme they share, if it's rare in the library.
        let total = max(libraryCount, 1)
        let themes = x.keywords.intersection(y.keywords).filter { !plainThemes.contains($0) }
            .map { ($0, keywordCounts[$0] ?? 1) }
            .filter { $0.1 <= max(3, total / 12) }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
        if let (theme, _) = themes.first { return (2, "A shared theme: \(theme)") }
        return nil
    }

    private static func first(_ a: Set<String>, _ b: Set<String>) -> String? {
        a.intersection(b).sorted().first
    }

    static func craftReason(_ name: String) -> String {
        switch name {
        case "Natural light": "Both lit with natural light"
        case "Candlelight": "Both lit by candlelight"
        case "Handheld": "Both shot handheld"
        case "IMAX": "Both shot in IMAX"
        case "Bleach bypass": "Both with a bleach-bypass look"
        case "LED volume": "Both shot in an LED volume"
        case "SnorriCam": "Both use a SnorriCam"
        default: "Both shot on \(name)"
        }
    }
}
