import Foundation

/// What a file's picture is (HDR or SDR), so the TV can be set before Play: from your own
/// setting, else from what the file name proves. When nothing proves it, it's "not stated":
/// Reel never guesses SDR. The file itself is never opened.
public struct FilePicture: Equatable, Sendable {
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
        /// The film's own folder says it ("Dune (2021) 2160p DV/dune.mkv"), or the folder of the
        /// collection it's part of ("The Fast and the Furious - Complete Collection 1080p HDR10/…").
        case folder
        /// Nothing proves it, but the kind of release makes it likely: a 4K Blu-ray is HDR10 as
        /// standard; a 4K web release or a 1080p file whose name doesn't say HDR is most likely SDR.
        case likely
        /// Nothing to go on (a file renamed by hand, "2013. Furious 6.mkv").
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
    /// An inference, said as one ("Likely SDR").
    public var isGuess: Bool { basis == .likely || basis == .convention }

    /// "HDR · Dolby Vision + HDR10", "SDR", or nil when not stated.
    public var label: String? {
        guard let range else { return nil }
        if isGuess { return "Likely " + (range.isHDR ? range.rawValue : "SDR") }
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
    ///   - ownFolder: the film's folder name, parsed: only when the folder holds this film alone, or
    ///     is named as one collection (see `isCollection`). A folder of assorted films ("4K HDR
    ///     Films") says nothing about each film in it.
    ///   - yours: what you set, which always wins.
    public static func of(_ name: ParsedFilename, ownFolder: ParsedFilename? = nil, yours: DynamicRange? = nil) -> FilePicture {
        if let yours {
            return FilePicture(range: yours, fallback: nil, basis: .yours, reason: "You set this")
        }
        // What proves it first, the file's name then its folder; only then what's likely, the
        // same order (a folder that says "HDR10" beats a guess from the file's name).
        let byName = proven(by: name, what: "the file name")
        if let byName, !byName.isGuess { return byName }
        let byFolder = ownFolder.flatMap { proven(by: $0, what: "the film's folder") }
        if let byFolder, !byFolder.isGuess {
            return FilePicture(range: byFolder.range, fallback: byFolder.fallback, basis: .folder, reason: byFolder.reason)
        }
        if let byName { return byName }
        if let byFolder { return byFolder }
        if let guess = likely(name) { return guess }
        let why = name.anyResolution == "2160p"
            ? "4K, and the file name doesn't say HDR or SDR"
            : "The file name doesn't say HDR or SDR"
        return FilePicture(range: nil, fallback: nil, basis: .notStated, reason: why)
    }

    /// What the kind of release makes likely, when nothing proves it; nil when the name says
    /// nothing about the release at all.
    static func likely(_ parsed: ParsedFilename) -> FilePicture? {
        let bluRay = parsed.anySource.map { $0.hasPrefix("BluRay") || $0 == "REMUX" } ?? false
        switch parsed.anyResolution {
        case "2160p" where bluRay:
            return FilePicture(range: .hdr10, fallback: nil, basis: .likely,
                               reason: "A 4K Blu-ray whose name doesn't say: 4K Blu-rays are HDR10 as standard, so likely HDR10")
        case "2160p":
            return FilePicture(range: .sdr, fallback: nil, basis: .likely,
                               reason: "A 4K release whose name doesn't say HDR: release names usually say it when it is, so likely SDR")
        case "1080p":
            return FilePicture(range: .sdr, fallback: nil, basis: .likely,
                               reason: "A 1080p file whose name doesn't say HDR: likely SDR")
        default:
            return nil
        }
    }

    /// What one name proves, or nil.
    static func proven(by parsed: ParsedFilename, what: String) -> FilePicture? {
        if let range = parsed.dynamicRange {
            let said = range == .sdr ? "SDR" : (parsed.hdr ?? range.rawValue)
            return FilePicture(range: range, fallback: parsed.fallbackRange, basis: .named, reason: "\(what.prefix(1).uppercased() + what.dropFirst()) says \(said)")
        }
        let resolution = parsed.anyResolution
        if parsed.isDVD {
            return FilePicture(range: .sdr, fallback: nil, basis: .source, reason: "A DVD: always SDR")
        }
        if let resolution, ["720p", "576p", "480p"].contains(resolution) {
            return FilePicture(range: .sdr, fallback: nil, basis: .source, reason: "\(resolution): SDR")
        }
        guard resolution == "1080p" else { return nil }
        // HDR Blu-rays are 4K discs only; a 1080p copy of one says "UHD".
        let bluRay = parsed.anySource.map { $0.hasPrefix("BluRay") || $0 == "REMUX" } ?? false
        if bluRay, !parsed.mentionsUHD {
            return FilePicture(range: .sdr, fallback: nil, basis: .source, reason: "A 1080p Blu-ray: HDR is only on 4K Blu-rays")
        }
        if parsed.anySource != nil || parsed.videoCodec != nil {
            return FilePicture(range: .sdr, fallback: nil, basis: .convention,
                           reason: "A 1080p release name without HDR: release names usually say HDR when it is, so likely SDR")
        }
        return nil
    }
}

extension FilePicture {
    /// Whether a folder of several films is named as one release of them all: "Complete
    /// Collection", "Trilogy", "Saga", "Box Set", or a span of years ("(2001-2021)"). What its name
    /// says about the picture is then said of every film in it.
    public static func isCollection(_ folderName: String) -> Bool {
        let lower = folderName.lowercased()
        if lower.range(of: #"\b(?:collection|trilogy|duology|quadrilogy|pentalogy|hexalogy|anthology|saga|box ?set|boxset|complete series)\b"#,
                       options: .regularExpression) != nil { return true }
        return lower.range(of: #"\b(?:19|20)\d{2}\s*[-–]\s*(?:19|20)\d{2}\b"#, options: .regularExpression) != nil
    }

    /// The folder that speaks for each film, by film id: its folder's name, when no other film on
    /// that drive shares the folder, or when the folder is named as one collection and at least two
    /// thirds of its films are of one TMDB collection (so "Criterion Collection DV" holding
    /// assorted films says nothing). A film at the top of a drive, or in a folder of assorted
    /// films ("4K HDR"), has none.
    public static func ownFolderNames(_ films: [FilmEntry]) -> [String: String] {
        func folder(_ film: FilmEntry) -> String? {
            let parent = (film.relativePath as NSString).deletingLastPathComponent
            return parent.isEmpty ? nil : parent
        }
        var count: [String: Int] = [:]
        var collections: [String: [Int: Int]] = [:]
        for film in films {
            guard let parent = folder(film) else { continue }
            let key = film.driveID + "/" + parent
            count[key, default: 0] += 1
            if let collection = film.tmdb?.collection?.id { collections[key, default: [:]][collection, default: 0] += 1 }
        }
        var result: [String: String] = [:]
        for film in films {
            guard let parent = folder(film), let shared = count[film.driveID + "/" + parent] else { continue }
            let name = (parent as NSString).lastPathComponent
            let together = collections[film.driveID + "/" + parent]?.values.max() ?? 0
            if shared == 1 || (isCollection(name) && together * 3 >= shared * 2) { result[film.id] = name }
        }
        return result
    }

    /// The films' own folders, read (see `ownFolderNames`), by film id. `parsed` keeps the folder
    /// names already read, so a library is read once, not on every redraw.
    public static func ownFolders(_ films: [FilmEntry], parsed: inout [String: ParsedFilename]) -> [String: ParsedFilename] {
        var result: [String: ParsedFilename] = [:]
        for (id, name) in ownFolderNames(films) {
            if let known = parsed[name] {
                result[id] = known
            } else {
                let read = FilenameParser.parse(name)
                parsed[name] = read
                result[id] = read
            }
        }
        return result
    }

    /// One file's picture in a library: your setting for it, its name, then its own folder.
    public static func of(_ film: FilmEntry, ownFolders: [String: ParsedFilename], yours: [String: DynamicRange]) -> FilePicture {
        of(film.parsed, ownFolder: ownFolders[film.id], yours: yours[film.fileKey])
    }
}
