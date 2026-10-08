import Foundation

public struct TMDBPersonCredit: Codable, Equatable, Sendable {
    public var id: Int
    public var title: String?
    public var releaseDate: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var overview: String?
    public var character: String?
    public var job: String?
    public var department: String?
    public var voteAverage: Double?
    public var voteCount: Int?
    public var genreIDs: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, character, job, department
        case genreIDs = "genre_ids"
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }
}

public struct TMDBPersonCredits: Codable, Equatable, Sendable {
    public var cast: [TMDBPersonCredit]
    public var crew: [TMDBPersonCredit]
}

/// A director, cinematographer, actor… with their film credits.
public struct TMDBPerson: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var biography: String?
    public var birthday: String?
    public var deathday: String?
    public var placeOfBirth: String?
    public var profilePath: String?
    public var knownForDepartment: String?
    public var movieCredits: TMDBPersonCredits?

    enum CodingKeys: String, CodingKey {
        case id, name, biography, birthday, deathday
        case placeOfBirth = "place_of_birth"
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case movieCredits = "movie_credits"
    }
}

/// One film in a person's filmography, with every role they had on it.
public struct FilmographyEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let year: Int?
    public let posterPath: String?
    public let backdropPath: String?
    public let overview: String?
    public let voteAverage: Double?
    public let voteCount: Int
    public let roles: [String]
    public let departments: Set<String>
}

public enum Filmography {
    /// Department order used for the filter chips.
    public static let departmentOrder = [
        "Directing", "Writing", "Camera", "Acting", "Editing", "Sound", "Production", "Art",
        "Visual Effects", "Costume & Make-Up", "Lighting", "Crew",
    ]

    /// Merges cast and crew credits per film, newest first. Appearances as themselves are left out.
    public static func build(_ person: TMDBPerson) -> [FilmographyEntry] {
        struct Draft {
            var credit: TMDBPersonCredit
            var roles: [String] = []
            var departments = Set<String>()
        }
        var drafts: [Int: Draft] = [:]
        var order: [Int] = []

        func add(_ credit: TMDBPersonCredit, role: String, department: String) {
            if drafts[credit.id] == nil {
                drafts[credit.id] = Draft(credit: credit)
                order.append(credit.id)
            }
            if !(drafts[credit.id]!.roles.contains(role)) { drafts[credit.id]!.roles.append(role) }
            drafts[credit.id]!.departments.insert(department)
        }

        for credit in person.movieCredits?.crew ?? [] {
            add(credit, role: credit.job ?? "Crew", department: credit.department ?? "Crew")
        }
        for credit in person.movieCredits?.cast ?? [] {
            let character = (credit.character ?? "").trimmingCharacters(in: .whitespaces)
            let lowered = character.lowercased()
            if lowered == "self" || lowered.hasPrefix("self ") || lowered.contains("himself") || lowered.contains("herself")
                || lowered.contains("archive footage") { continue }
            add(credit, role: character.isEmpty ? "Actor" : "as \(character)", department: "Acting")
        }

        let entries = order.compactMap { id -> FilmographyEntry? in
            guard let d = drafts[id], let title = d.credit.title, !title.isEmpty else { return nil }
            return FilmographyEntry(
                id: id, title: title, year: yearFromDate(d.credit.releaseDate), posterPath: d.credit.posterPath,
                backdropPath: d.credit.backdropPath, overview: d.credit.overview, voteAverage: d.credit.voteAverage,
                voteCount: d.credit.voteCount ?? 0, roles: d.roles, departments: d.departments)
        }
        return entries.sorted { a, b in
            switch (a.year, b.year) {
            case let (x?, y?) where x != y: return x > y
            case (nil, _?): return true
            case (_?, nil): return false
            default: return a.voteCount > b.voteCount
            }
        }
    }

    /// Departments this person worked in, in a fixed order.
    public static func departments(in entries: [FilmographyEntry]) -> [String] {
        let present = Set(entries.flatMap { $0.departments })
        return departmentOrder.filter { present.contains($0) }
    }
}
