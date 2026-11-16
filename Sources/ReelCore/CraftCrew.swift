import Foundation

// The Cinematography tab and the Shot on filter were cut from 1.11 (decided 16 Nov: the facts were
// right but found for too few films). What stays: the Shot on values people removed, kept in Your
// Notes as they are, and the camera crew kept with a film's details.

/// What a film was shot on. Only stored now: the "Not right" choices in Your Notes
/// (`removedShotOn`) are kept as they are, so the raw values never change.
public enum ShotOn: String, Codable, CaseIterable, Sendable, Identifiable {
    case film, digital, anamorphic, imax, blackAndWhite

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .film: "Film"
        case .digital: "Digital"
        case .anamorphic: "Anamorphic"
        case .imax: "IMAX"
        case .blackAndWhite: "Black & white"
        }
    }
}

/// The film's camera, lighting and colour people on TMDB: which jobs are kept with its details.
public enum CraftCrew {
    /// TMDB's jobs kept with a film's details.
    public static let keptJobs: Set<String> = [
        "Director of Photography", "Additional Director of Photography", "Additional Photography",
        "Aerial Director of Photography", "Underwater Director of Photography", "Second Unit Director of Photography",
        "Steadicam Operator", "Camera Operator", "\"A\" Camera Operator", "\"B\" Camera Operator", "\"C\" Camera Operator",
        "Additional Camera Operator", "Gaffer", "Chief Lighting Technician", "Key Grip", "Digital Imaging Technician",
        "Colorist", "Digital Intermediate Colorist", "Supervising Colorist", "Senior Colorist", "Visual Effects Supervisor",
        "First Assistant Camera", "\"A\" First Assistant Camera", "First Assistant \"A\" Camera",
        "\"B\" First Assistant Camera", "First Assistant \"B\" Camera",
    ]
}
