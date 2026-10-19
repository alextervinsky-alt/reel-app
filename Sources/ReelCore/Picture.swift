import Foundation

/// What a file's picture is (HDR or SDR), so the TV can be set before Play: from your own
/// setting, else from what the file name proves. When nothing proves it, it's "not stated":
/// Reel never guesses SDR. The file itself is never opened.
public struct Picture: Equatable, Sendable {
    /// Why Reel says so, the most certain first.
    public enum Basis: Equatable, Sendable {
        /// You set it.
        case yours
        /// The file name says it ("DV HDR10", "SDR").
        case named
        /// The source can't carry HDR (a DVD, 720p or lower, a 1080p Blu-ray).
        case source
        /// A full release name (resolution and source or codec) with no HDR word: release names
        /// always say HDR, so it's SDR.
        case convention
        /// The film's own folder says it ("Dune (2021) 2160p DV/dune.mkv").
        case folder
        /// Nothing says.
        case notStated
    }

    /// Nil when not stated.
    public let range: DynamicRange?
    /// For Dolby Vision, the HDR layer it also carries.
    public let fallback: DynamicRange?
    public let basis: Basis
    /// Why, for the tag's help: "the file name says DV HDR10", "1080p Blu-ray: SDR only".
    public let reason: String

    public var isHDR: Bool { range?.isHDR ?? false }
    public var isKnown: Bool { range != nil }

    /// "HDR · Dolby Vision + HDR10", "SDR", or nil when not stated.
    public var label: String? {
        guard let range else { return nil }
        guard range.isHDR else { return "SDR" }
        if range == .hdr { return "HDR" }
        return "HDR · " + range.rawValue + (fallback.map { " + " + $0.rawValue } ?? "")
    }

    /// Words a search can find it by ("HDR", "Dolby Vision", "SDR").
    public var searchWords: [String] {
        guard let range else { return [] }
        if !range.isHDR { return ["SDR"] }
        return ["HDR", range.rawValue] + (fallback.map { [$0.rawValue] } ?? [])
    }

    /// The choices you can make in the film's "…" menu.
    public static let choices: [DynamicRange] = [.dolbyVision, .hdr, .sdr]

    /// - Parameters:
    ///   - name: the file name, parsed.
    ///   - ownFolder: the film's own folder name, parsed: only when the folder holds this film alone
    ///     (a collection folder, "4K HDR Films", says nothing about each film in it).
    ///   - yours: what you set, which always wins.
    public static func of(_ name: ParsedFilename, ownFolder: ParsedFilename? = nil, yours: DynamicRange? = nil) -> Picture {
        if let yours {
            return Picture(range: yours, fallback: nil, basis: .yours, reason: "You set this")
        }
        if let found = proven(by: name, what: "the file name") { return found }
        if let folder = ownFolder, let found = proven(by: folder, what: "the film's folder") {
            return Picture(range: found.range, fallback: found.fallback, basis: .folder, reason: found.reason)
        }
        let why = name.anyResolution == "2160p"
            ? "4K, and the file name doesn't say HDR or SDR"
            : "The file name doesn't say HDR or SDR"
        return Picture(range: nil, fallback: nil, basis: .notStated, reason: why)
    }

    /// What one name proves, or nil.
    static func proven(by parsed: ParsedFilename, what: String) -> Picture? {
        if let range = parsed.dynamicRange {
            let said = range == .sdr ? "SDR" : (parsed.hdr ?? range.rawValue)
            return Picture(range: range, fallback: parsed.fallbackRange, basis: .named, reason: "\(what.prefix(1).uppercased() + what.dropFirst()) says \(said)")
        }
        let resolution = parsed.anyResolution
        if parsed.isDVD {
            return Picture(range: .sdr, fallback: nil, basis: .source, reason: "A DVD: always SDR")
        }
        if let resolution, ["720p", "576p", "480p"].contains(resolution) {
            return Picture(range: .sdr, fallback: nil, basis: .source, reason: "\(resolution): SDR")
        }
        guard resolution == "1080p" else { return nil }
        // HDR Blu-rays are 4K discs only; a 1080p copy of one says "UHD".
        let bluRay = parsed.anySource.map { $0.hasPrefix("BluRay") || $0 == "REMUX" } ?? false
        if bluRay, !parsed.mentionsUHD {
            return Picture(range: .sdr, fallback: nil, basis: .source, reason: "A 1080p Blu-ray: HDR is only on 4K Blu-rays")
        }
        if parsed.anySource != nil || parsed.videoCodec != nil {
            return Picture(range: .sdr, fallback: nil, basis: .convention,
                           reason: "A 1080p release name without HDR: release names always say HDR")
        }
        return nil
    }
}

extension Picture {
    /// The folder each film has to itself, by film id: its folder's name, when no other film on
    /// that drive shares the folder. A film at the top of a drive, or in a folder of several
    /// films (a collection, "4K HDR"), has none.
    public static func ownFolders(_ films: [FilmEntry]) -> [String: String] {
        func folder(_ film: FilmEntry) -> String? {
            let parent = (film.relativePath as NSString).deletingLastPathComponent
            return parent.isEmpty ? nil : parent
        }
        var count: [String: Int] = [:]
        for film in films { if let parent = folder(film) { count[film.driveID + "/" + parent, default: 0] += 1 } }
        var result: [String: String] = [:]
        for film in films {
            guard let parent = folder(film), count[film.driveID + "/" + parent] == 1 else { continue }
            result[film.id] = (parent as NSString).lastPathComponent
        }
        return result
    }

    /// One file's picture in a library: your setting for it, its name, then its own folder.
    public static func of(_ film: FilmEntry, ownFolders: [String: String], yours: [String: DynamicRange]) -> Picture {
        of(film.parsed, ownFolder: ownFolders[film.id].map { FilenameParser.parse($0) }, yours: yours[film.fileKey])
    }
}
