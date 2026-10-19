import Foundation

/// The picture words in a release name, read from the whole name (dots, spaces, brackets and
/// words run together: "DV.HDR10+", "[DV HDR10]", "Dolby.Vision.And.HDR10.PLUS", "HDR10+REMUX",
/// "DV.P7"). Release names list every picture format the file carries, so a format not named is
/// one it doesn't have ("DV HDR10" has no HDR10+).
public struct PictureWords: Equatable, Sendable {
    public var dolbyVision = false
    public var hdr10Plus = false
    /// HDR10, or "HDR" alone (HDR10 by convention).
    public var hdr10 = false
    public var hlg = false
    public var sdr = false
    /// Converted from HDR to SDR ("tonemapped", "HDR to SDR").
    public var toneMapped = false
    /// The Dolby Vision profile when named ("DV.P7", "DoVi P8", "FEL"): 5 has no HDR10 layer.
    public var dolbyVisionProfile: Int?
    /// "HDR" itself (not only "HDR10"), to write it as the name does.
    var saysHDR = false

    public init() {}

    public static func read(_ name: String) -> PictureWords {
        let lower = name.lowercased()
        func has(_ pattern: String) -> Bool { lower.range(of: pattern, options: .regularExpression) != nil }
        var words = PictureWords()
        words.toneMapped = has(#"tone[ ._-]?map|(?<![a-z0-9])hdr[ ._-]?(?:to|2)[ ._-]?sdr(?![a-z])"#)
        words.dolbyVision = has(#"(?<![a-z0-9])(?:dovi|dolby[ ._-]?vision|dv(?=hdr|[^a-z0-9]|$))"#)
        // "DVHDR10", "4KHDR": run together after DV or 4K.
        let start = #"(?:(?<=dv)|(?<=4k)|(?<![a-z0-9]))"#
        words.hdr10Plus = has(start + #"hdr10(?:\+|p(?![a-z0-9])|plus(?![a-z])|[ ._-]plus(?![a-z]))|"# + start + #"hdr\+"#)
        // "HDRip" is a rip of an HD source, not HDR.
        words.saysHDR = has(start + #"hdr(?![a-z]|10)"#)
        words.hdr10 = words.saysHDR || has(start + #"hdr10(?![0-9])"#)
        words.hlg = has(#"(?<![a-z0-9])hlg(?![a-z0-9])"#)
        words.sdr = has(#"(?<![a-z0-9])sdr(?![a-z0-9])"#)
        if words.dolbyVision {
            if let found = lower.range(of: #"(?<![a-z0-9])(?:dv|dovi)[ ._-]?p([578])(?![0-9])|(?<![a-z0-9])profile[ ._-]?([578])(?![0-9])|(?<![a-z0-9])p([578])(?:\.\d)?(?![a-z0-9])"#,
                                       options: .regularExpression) {
                words.dolbyVisionProfile = lower[found].last { $0.isNumber && "578".contains($0) }.flatMap { Int(String($0)) }
            } else if has(#"(?<![a-z0-9])(?:fel|mel)(?![a-z0-9])"#) {
                words.dolbyVisionProfile = 7
            }
            // Profile 8.4 sits on HLG (phones).
            if words.dolbyVisionProfile == 8, has(#"(?<![0-9])8\.4(?![0-9])"#) { words.hlg = true }
        }
        // Converted to SDR: its HDR words are what it was made from, not what it is.
        if words.toneMapped {
            words = PictureWords()
            words.toneMapped = true
            words.sdr = true
        }
        return words
    }

    /// As a name writes it, short: "DV HDR10+", "DV HDR", "DV", "HDR10", "HLG"; nil for none.
    public var written: String? {
        if toneMapped { return "SDR" }
        var parts: [String] = []
        if dolbyVision { parts.append("DV") }
        if hdr10Plus {
            parts.append("HDR10+")
        } else if saysHDR {
            parts.append("HDR")
        } else if hdr10 {
            parts.append("HDR10")
        } else if hlg {
            parts.append("HLG")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// What the name says the picture is, the richest first; SDR only when it says so.
    public var dynamicRange: DynamicRange? {
        if toneMapped { return .sdr }
        if dolbyVision { return .dolbyVision }
        if hdr10Plus { return .hdr10Plus }
        if hdr10 { return .hdr10 }
        if hlg { return .hlg }
        return sdr ? .sdr : nil
    }
}

/// What a file's picture is, for one choice before Play: whether to switch the Mac's display to
/// HDR. A Mac sends HDR to the TV in one form (HDR10) whatever the file carries, so Dolby Vision,
/// HDR10+ and HDR10 files all need the same setting; the format is kept as detail. From your own
/// setting, else what the file name (or the film's own folder) proves, else what the kind of
/// release makes likely, said as a guess. The file itself is never opened.
public struct FilePicture: Equatable, Sendable {
    /// What to set the Mac to.
    public enum Setting: String, Equatable, Sendable {
        case hdr = "HDR"
        case sdr = "SDR"
    }

    /// The HDR formats a file carries.
    public enum Format: String, Equatable, Sendable {
        case dolbyVisionHDR10Plus = "Dolby Vision + HDR10+"
        case dolbyVisionHDR10 = "Dolby Vision + HDR10"
        case dolbyVisionHLG = "Dolby Vision + HLG"
        /// Dolby Vision with no HDR10 layer (profile 5, as streaming services send it): players
        /// that can't read Dolby Vision show it in wrong colours.
        case dolbyVisionOnly = "Dolby Vision only"
        /// Dolby Vision, whether there's an HDR10 layer unknown.
        case dolbyVision = "Dolby Vision"
        case hdr10Plus = "HDR10+"
        case hdr10 = "HDR10"
        case hlg = "HLG"

        /// Words a search can find it by.
        var searchWords: [String] {
            switch self {
            case .dolbyVisionHDR10Plus: ["Dolby Vision", "HDR10+", "HDR10"]
            case .dolbyVisionHDR10: ["Dolby Vision", "HDR10"]
            case .dolbyVisionHLG: ["Dolby Vision", "HLG"]
            case .dolbyVisionOnly, .dolbyVision: ["Dolby Vision"]
            case .hdr10Plus: ["HDR10+", "HDR10"]
            case .hdr10: ["HDR10"]
            case .hlg: ["HLG"]
            }
        }
    }

    /// Why Reel says so, the most certain first.
    public enum Basis: Equatable, Sendable {
        /// You set it.
        case yours
        /// The file name says it ("DV HDR10", "SDR").
        case named
        /// The film's own folder says it ("Dune (2021) 2160p DV/dune.mkv"), or the folder of the
        /// collection it's part of ("The Fast and the Furious - Complete Collection 1080p HDR10/…").
        case folder
        /// What the file is can't carry HDR: a DVD, 720p or lower, a 1080p Blu-ray, an H.264 (AVC),
        /// VC-1 or MPEG-2 file (HDR video is made in HEVC or AV1).
        case source
        /// Nothing proves it, but the kind of release makes it likely: a 4K Blu-ray is HDR10 as
        /// standard; a 4K web release or a 1080p file whose name doesn't say HDR is most likely SDR
        /// (release names say HDR when it is).
        case likely
        /// Nothing to go on (a file renamed by hand, "2013. Furious 6.mkv").
        case notStated
    }

    /// Nil when not stated.
    public let setting: Setting?
    /// The HDR format, when known.
    public let format: Format?
    public let basis: Basis
    /// Why, for the tag's help: "the file name says DV HDR10", "a 1080p Blu-ray: HDR is only on 4K Blu-rays".
    public let reason: String
    /// How sure: 5 a name's own words, 4 what the file can't be, 3 a folder's words, 2 a 1080p
    /// Blu-ray, 1 likely (the file's name over its folder's on a tie).
    var strength = 0

    public var isHDR: Bool { setting == .hdr }
    public var isKnown: Bool { setting != nil }
    /// An inference, said as one ("Likely SDR").
    public var isGuess: Bool { basis == .likely }
    /// Dolby Vision with no HDR10 layer: worth knowing before Play.
    public var isDolbyVisionOnly: Bool { format == .dolbyVisionOnly }

    /// "HDR", "SDR", "Likely HDR", "HDR · Dolby Vision only", or nil when not stated.
    public var label: String? {
        guard let setting else { return nil }
        if isGuess { return "Likely " + setting.rawValue }
        return isDolbyVisionOnly ? "HDR · Dolby Vision only" : setting.rawValue
    }

    /// Words a search can find it by ("HDR", "Dolby Vision", "SDR").
    public var searchWords: [String] {
        guard let setting else { return [] }
        return [setting.rawValue] + (format?.searchWords ?? [])
    }

    /// What you can set in the film's "…" menu (all the Mac's display knows).
    public static let choices: [DynamicRange] = [.hdr, .sdr]

    /// - Parameters:
    ///   - name: the file name, parsed.
    ///   - ownFolder: the film's folder name, parsed: only when the folder holds this film alone, or
    ///     is named as one collection (see `isCollection`). A folder of assorted films ("4K HDR
    ///     Films") says nothing about each film in it.
    ///   - yours: what you set, which always wins (an older Reel's "Dolby Vision" is HDR).
    public static func of(_ name: ParsedFilename, ownFolder: ParsedFilename? = nil, yours: DynamicRange? = nil) -> FilePicture {
        // What proves it first, the file's name then its folder; only then what's likely, the
        // same order (a folder that says "HDR10" beats a guess from the file's name).
        let byName = read(name, what: "the file name")
        let byFolder = ownFolder.flatMap { read($0, what: "the film's folder") }.map {
            $0.basis == .named ? FilePicture(setting: $0.setting, format: $0.format, basis: .folder, reason: $0.reason, strength: 3) : $0
        }
        // The strongest says it: a name's own words, then what the file can't be (a DVD, H.264…),
        // then its folder's words (a 1080p "BluRay" in a folder that says HDR10 is a copy of a 4K
        // disc), then a 1080p Blu-ray, then what's likely.
        let found = [byName, byFolder].compactMap { $0 }.max { $0.strength < $1.strength }
        if let yours {
            let setting: Setting = yours.isHDR ? .hdr : .sdr
            // The format the name says, when it agrees.
            let format = setting == .hdr && found?.setting == .hdr && found?.isGuess == false ? found?.format : nil
            return FilePicture(setting: setting, format: format, basis: .yours, reason: "You set this")
        }
        if let found { return found }
        let why = name.anyResolution == "2160p"
            ? "4K, and the file name doesn't say HDR or SDR (4K files can be either)"
            : "The file name doesn't say HDR or SDR, or what kind of release it is"
        return FilePicture(setting: nil, format: nil, basis: .notStated, reason: why)
    }

    /// What one name says, proves or makes likely; nil when it says nothing about the picture.
    static func read(_ parsed: ParsedFilename, what: String) -> FilePicture? {
        let words = parsed.pictureWords
        let source = parsed.anySource ?? ""
        let disc = source.hasPrefix("BluRay") || source == "REMUX"
        let web = source == "WEB" || source.hasPrefix("WEB")
        let subject = what.prefix(1).uppercased() + what.dropFirst()
        // Said outright.
        if words.toneMapped {
            return FilePicture(setting: .sdr, format: nil, basis: .named, reason: "\(subject) says it was converted from HDR to SDR", strength: 5)
        }
        if words.sdr, !words.dolbyVision, !words.hdr10, !words.hdr10Plus, !words.hlg {
            return FilePicture(setting: .sdr, format: nil, basis: .named, reason: "\(subject) says SDR", strength: 5)
        }
        if words.dynamicRange?.isHDR == true {
            let (kind, why) = Self.format(of: words, disc: disc, web: web)
            let said = words.written ?? "HDR"
            return FilePicture(setting: .hdr, format: kind, basis: .named, reason: "\(subject) says \(said)" + (why.map { ": " + $0 } ?? ""), strength: 5)
        }
        // What the file is can't carry HDR.
        if parsed.isDVD {
            return FilePicture(setting: .sdr, format: nil, basis: .source, reason: "A DVD: always SDR", strength: 4)
        }
        let resolution = parsed.anyResolution
        if let resolution, ["720p", "576p", "480p"].contains(resolution) {
            return FilePicture(setting: .sdr, format: nil, basis: .source, reason: "\(resolution): HDR releases are 1080p or 4K", strength: 4)
        }
        // HDR Blu-rays are 4K discs only; a 1080p copy of one says "UHD".
        if resolution == "1080p", disc, !parsed.mentionsUHD {
            return FilePicture(setting: .sdr, format: nil, basis: .source, reason: "A 1080p Blu-ray: HDR is only on 4K Blu-rays", strength: 2)
        }
        if let codec = parsed.videoCodec, ["AVC", "VC-1", "MPEG-2", "XviD"].contains(codec) {
            return FilePicture(setting: .sdr, format: nil, basis: .source,
                               reason: "\(codec == "AVC" ? "H.264 (AVC)" : codec) video: HDR releases are made in HEVC or AV1", strength: 4)
        }
        // Likely, from the kind of release.
        switch resolution {
        case "2160p" where disc:
            return FilePicture(setting: .hdr, format: .hdr10, basis: .likely,
                               reason: "A 4K Blu-ray whose name doesn't say: 4K Blu-rays are HDR10 as standard", strength: 1)
        case "2160p" where web:
            return FilePicture(setting: .sdr, format: nil, basis: .likely,
                               reason: "A 4K web release whose name doesn't say HDR: web releases name HDR and Dolby Vision when they have them", strength: 1)
        case "1080p" where parsed.mentionsUHD:
            return FilePicture(setting: .sdr, format: nil, basis: .likely,
                               reason: "A 1080p copy of a 4K disc whose name doesn't say HDR: copies that keep HDR say so", strength: 1)
        case "1080p":
            return FilePicture(setting: .sdr, format: nil, basis: .likely,
                               reason: "A 1080p file whose name doesn't say HDR: 1080p releases are almost always SDR", strength: 1)
        default:
            return nil
        }
    }

    /// The format a name's HDR words make, and why when it's worked out ("DV" alone on a 4K
    /// Blu-ray: its Dolby Vision always sits on HDR10).
    static func format(of words: PictureWords, disc: Bool, web: Bool) -> (Format, String?) {
        guard words.dolbyVision else {
            return (words.hdr10Plus ? .hdr10Plus : words.hdr10 ? .hdr10 : .hlg, nil)
        }
        if words.hdr10Plus { return (.dolbyVisionHDR10Plus, nil) }
        if words.hdr10 { return (.dolbyVisionHDR10, nil) }
        if words.hlg { return (.dolbyVisionHLG, nil) }
        switch words.dolbyVisionProfile {
        case 5: return (.dolbyVisionOnly, "Dolby Vision profile 5 has no HDR10 layer")
        case 7, 8: return (.dolbyVisionHDR10, "Dolby Vision profile \(words.dolbyVisionProfile ?? 7) sits on HDR10")
        default: break
        }
        if disc { return (.dolbyVisionHDR10, "a 4K Blu-ray's Dolby Vision always sits on HDR10") }
        if web { return (.dolbyVisionOnly, "a web release named only DV usually has no HDR10 layer (Dolby Vision profile 5)") }
        return (.dolbyVision, nil)
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
