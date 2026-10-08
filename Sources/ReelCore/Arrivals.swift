import Foundation

// MARK: - New arrivals

/// Films that turned up on a drive recently. A copy counts when it was found after its drive's
/// `arrivalsSince` (so a drive's first scan, or the library as it was before Reel 1.0, never
/// counts), and the film stays new for 14 days from its earliest copy.
public enum Arrivals {
    public static let window: TimeInterval = 14 * 86_400

    public struct Copy: Sendable {
        public let addedAt: Date
        /// The drive's `arrivalsSince`; nil while the drive hasn't finished its first scan.
        public let since: Date?
        /// Promoted from an extra by hand: not a real arrival.
        public let regrouped: Bool

        public init(addedAt: Date, since: Date?, regrouped: Bool = false) {
            self.addedAt = addedAt
            self.since = since
            self.regrouped = regrouped
        }
    }

    /// When the film arrived, if it counts as new right now. The earliest copy decides: a film
    /// that was already on Films doesn't become new when it's copied to the Backup.
    public static func arrival(of copies: [Copy], now: Date) -> Date? {
        guard let first = copies.min(by: { $0.addedAt < $1.addedAt }), !first.regrouped,
              let since = first.since, first.addedAt > since,
              now.timeIntervalSince(first.addedAt) < window else { return nil }
        return first.addedAt
    }

    /// "Today", "Yesterday", "3 days ago".
    public static func label(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Added today"
        case 1: return "Added yesterday"
        default: return "Added \(days) days ago"
        }
    }
}

// MARK: - Wishlist

/// A wishlist film that turned up in the library.
public struct WishlistArrival: Codable, Equatable, Sendable {
    public let id: Int
    public let date: Date

    public init(id: Int, date: Date) {
        self.id = id
        self.date = date
    }
}

public enum WishlistCleanup {
    /// Splits the wishlist into films still wanted and films now in the library. Only films Reel
    /// is sure about count (`owned` holds confirmed and automatic matches, never "check match").
    public static func split(_ wishlist: [WishlistFilm], owned: Set<Int>) -> (kept: [WishlistFilm], arrived: [WishlistFilm]) {
        var kept: [WishlistFilm] = []
        var arrived: [WishlistFilm] = []
        for film in wishlist {
            if owned.contains(film.id) { arrived.append(film) } else { kept.append(film) }
        }
        return (kept, arrived)
    }

    /// Adds new arrivals and drops ones past the New Arrivals window.
    public static func record(_ arrived: [WishlistFilm], into existing: [WishlistArrival], now: Date) -> [WishlistArrival] {
        var result = existing.filter { now.timeIntervalSince($0.date) < Arrivals.window }
        let known = Set(result.map { $0.id })
        result += arrived.filter { !known.contains($0.id) }.map { WishlistArrival(id: $0.id, date: now) }
        return result
    }
}

// MARK: - Backup check

/// Films on the main drives without a full copy on a backup drive. Compares the last scan of
/// each drive (no drive needs to be connected), by film and file size, so different folder
/// names on the mirror don't matter.
public enum BackupCheck {
    public enum Problem: String, Sendable {
        /// No copy of the film on any backup drive.
        case missing
        /// The backup copy has a different size: an unfinished or damaged copy.
        case incomplete
    }

    public struct Gap: Equatable, Sendable {
        /// `FilmEntry.personalKey` of the film on the main drive.
        public let key: String
        public let entryID: String
        public let problem: Problem
    }

    /// - Only backup drives that have been scanned count (an empty one would make everything "missing").
    /// - Only main drives the backup mirrors are compared: ones with at least one film on the backup.
    public static func gaps(in films: [FilmEntry], backupDrives: Set<String>) -> [Gap] {
        var backupSizes: [String: Set<Int64>] = [:]
        var backupNames: [String: Set<Int64>] = [:]
        for film in films where backupDrives.contains(film.driveID) {
            backupSizes[film.personalKey, default: []].insert(film.size)
            backupNames[film.fileName, default: []].insert(film.size)
        }
        guard !backupSizes.isEmpty else { return [] }

        let main = films.filter { !backupDrives.contains($0.driveID) }
        let mirrored = Set(main.filter { backupSizes[$0.personalKey] != nil || backupNames[$0.fileName] != nil }.map { $0.driveID })
        var result: [Gap] = []
        for film in main where mirrored.contains(film.driveID) {
            // A copy of the same size counts, as the same film (renamed on the mirror) or the same file.
            let copied = backupSizes[film.personalKey]?.contains(film.size) == true
                || backupNames[film.fileName]?.contains(film.size) == true
            guard !copied else { continue }
            // The same file name with another size is a copy that didn't finish.
            let problem: Problem = backupNames[film.fileName] == nil ? .missing : .incomplete
            result.append(Gap(key: film.personalKey, entryID: film.id, problem: problem))
        }
        return result
    }
}
