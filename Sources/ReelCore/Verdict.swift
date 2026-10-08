import Foundation

/// One or two sentences on who liked the film and why, from critics' and audiences' scores and
/// what reviewers praised or criticised.
public enum ReceptionVerdict {
    /// Critics' score out of 10: Rotten Tomatoes and Metacritic.
    public static func criticScore(_ ratings: ExternalRatings?) -> Double? {
        let parts = [ratings?.rottenTomatoes.map { Double($0) / 10 }, ratings?.metacritic.map { Double($0) / 10 }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +) / Double(parts.count)
    }

    /// Audience score out of 10: IMDb, else TMDB.
    public static func audienceScore(_ ratings: ExternalRatings?, tmdbVote: Double?) -> Double? {
        if let imdb = ratings?.imdb { return imdb }
        if let vote = tmdbVote, vote > 0 { return vote }
        return nil
    }

    public static func sentence(ratings: ExternalRatings?, tmdbVote: Double?, reception: ReceptionSummary?, cinemaScore: String?) -> String? {
        let liked = list((reception?.liked ?? []).prefix(2).map { ReceptionAnalyzer.phrase(for: $0.aspect) })
        let disliked = list((reception?.disliked ?? []).prefix(2).map { ReceptionAnalyzer.phrase(for: $0.aspect, disliked: true) })
        let firstDislike = reception?.disliked.first.map { ReceptionAnalyzer.phrase(for: $0.aspect, disliked: true) }
        let critics = criticScore(ratings)
        let audience = audienceScore(ratings, tmdbVote: tmdbVote)

        var text: String
        switch (critics, audience) {
        case (nil, nil):
            guard let liked else { return nil }
            text = "Viewers mostly praise \(liked)."
        default:
            let c = critics ?? audience!
            let a = audience ?? critics!
            if c >= 8 && a >= 7.5 {
                text = "Loved by critics and audiences alike" + (liked.map { ", especially for \($0)." } ?? ".")
                if let firstDislike { text += " A few found \(firstDislike) a weak spot." }
            } else if c - a >= 1 {
                text = "A critics' favourite" + (liked.map { " for \($0)" } ?? "")
                    + ", but casual audiences were cooler on it" + (disliked.map { ", mostly because of \($0)." } ?? ".")
            } else if a - c >= 1 {
                text = "A crowd-pleaser" + (liked.map { ": audiences enjoyed \($0)" } ?? "")
                    + ", while critics were less convinced" + (disliked.map { ", pointing to \($0)." } ?? ".")
            } else if c >= 7 && a >= 7 {
                text = "Well liked by critics and audiences" + (liked.map { " for \($0)" } ?? "")
                    + (firstDislike.map { "; the most common complaint is \($0)." } ?? ".")
            } else if c >= 5.5 && a >= 5.5 {
                text = "A mixed reception" + (liked.map { ": people liked \($0)" } ?? "")
                    + (disliked.map { ", but many found \($0) lacking." } ?? ".")
            } else {
                text = "Mostly disliked" + (disliked.map { ", with complaints about \($0)" } ?? "")
                    + ((reception?.liked.first).map { ", though some enjoyed \(ReceptionAnalyzer.phrase(for: $0.aspect))." } ?? ".")
            }
        }
        if let grade = cinemaScore {
            let article = ["A", "F"].contains(String(grade.prefix(1))) ? "an" : "a"
            text += " Opening-night audiences gave it \(article) \(grade) CinemaScore."
        }
        return text
    }

    /// "A", "A and B".
    static func list(_ items: [String]) -> String? {
        switch items.count {
        case 0: return nil
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
