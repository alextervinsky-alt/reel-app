import Foundation

/// Why a film is among the picks, in two lengths: a short label for a poster (about 26
/// characters, "Director of Her") and a sentence for the film page ("From the director of Her").
public enum PickReason: Equatable, Sendable {
    case director(film: String)
    case cinematographer(name: String, film: String)
    case alike(film: String)
    case watchlist
    case new(drive: String)
    /// A list it's known for: "Palme d'Or · 2019", "Sight & Sound greatest films · #90".
    case listed(String)
    /// The best-rated unwatched films in the chosen mood ("" for any mood).
    case bestInMood(String)

    /// The longest a poster label may be.
    public static let shortLimit = 26

    public var long: String {
        switch self {
        case .director(let film): "From the director of \(film)"
        case .cinematographer(let name, let film): "Shot by \(name), like \(film)"
        case .alike(let film): "Because you loved \(film)"
        case .watchlist: "On your watchlist"
        case .new(let drive): "New on \(drive)"
        case .listed(let text): text
        case .bestInMood(let mood): mood.isEmpty ? "One of your best-rated unwatched films"
            : "One of the best-rated \(mood.lowercased()) films you haven't seen"
        }
    }

    public var short: String {
        switch self {
        case .director(let film): Self.fit("Director of ", film)
        case .cinematographer(let name, _): Self.fit("Shot by ", name.split(separator: " ").last.map(String.init) ?? name)
        case .alike(let film): Self.fit("Like ", film)
        case .watchlist: "On your watchlist"
        case .new: "New this week"
        case .listed(let text): Self.fit("", text.replacingOccurrences(of: " · ", with: " "))
        case .bestInMood(let mood): mood.isEmpty ? "Top rated, unwatched" : Self.fit("Top rated ", mood.lowercased())
        }
    }

    /// The first reason that applies, in order: your taste, your watchlist, new on a drive, a
    /// list it won or tops, and otherwise its rating in the mood you chose.
    public static func pick(taste: PickReason?, onWatchlist: Bool, newOn drive: String?, listed: String?,
                            mood: String) -> PickReason {
        if let taste { return taste }
        if onWatchlist { return .watchlist }
        if let drive { return .new(drive: drive) }
        if let listed { return .listed(listed) }
        return .bestInMood(mood)
    }

    /// "Director of " + a title cut with "…" so the whole label fits.
    static func fit(_ prefix: String, _ name: String) -> String {
        let room = shortLimit - prefix.count
        guard name.count > room else { return prefix + name }
        return prefix + name.prefix(max(room - 1, 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
