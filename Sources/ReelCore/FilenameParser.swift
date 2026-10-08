import Foundation

/// One audio track announced in a file name, e.g. "English TrueHD Atmos 7.1".
public struct AudioTrack: Equatable, Sendable {
    public var language: String?
    public var format: String

    public init(language: String?, format: String) {
        self.language = language
        self.format = format
    }
}

/// Everything Reel can learn from a file name alone. The file itself is never opened.
public struct ParsedFilename: Equatable, Sendable {
    public var title: String
    public var year: Int?
    public var resolution: String?
    public var source: String?
    public var hdr: String?
    public var videoCodec: String?
    public var audioTracks: [AudioTrack]
    public var isVideo: Bool
    public var isIncomplete: Bool
    public var looksLikeSample: Bool
    public var badges: [String]
}

public enum FilenameParser {
    static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "avi", "mov", "wmv", "ts", "m2ts", "mpg", "mpeg", "webm", "flv", "divx",
    ]
    static let otherExtensions: Set<String> = [
        "srt", "sub", "idx", "ass", "ssa", "nfo", "txt", "jpg", "jpeg", "png", "gif", "webp",
        "xml", "json", "db", "ini", "sfv", "md5", "url", "pdf", "iso", "img",
    ]
    static let incompleteExtensions: Set<String> = [
        "crdownload", "part", "download", "!qb", "tmp", "partial", "aria2", "opdownload",
    ]

    static let techWords: Set<String> = [
        "uhd", "4k", "hdr", "hdr10", "hdr10+", "dv", "dovi", "hevc", "x264", "x265", "h264", "h265",
        "avc", "bluray", "blu-ray", "bdrip", "brrip", "bdremux", "web-dl", "webdl", "webrip", "hdtv",
        "dvdrip", "dvdscr", "remux", "extended", "unrated", "imax", "repack", "multi", "esub", "esubs",
    ]

    static let languages: Set<String> = [
        "english", "hindi", "tamil", "telugu", "malayalam", "kannada", "bengali", "punjabi",
        "estonian", "russian", "french", "german", "spanish", "italian", "portuguese", "dutch",
        "swedish", "norwegian", "danish", "finnish", "polish", "czech", "hungarian", "turkish",
        "arabic", "hebrew", "persian", "japanese", "korean", "chinese", "mandarin", "cantonese",
        "thai", "multi", "dual",
    ]

    static let audioWords: Set<String> = [
        "truehd", "atmos", "dts", "dts-hd", "dtshd", "ddp", "dd", "dd+", "aac", "ac3", "eac3",
        "flac", "opus", "lpcm", "pcm", "dth",
    ]

    // MARK: - Public entry point

    public static func parse(_ path: String) -> ParsedFilename {
        let name = lastComponent(path)

        var incomplete = false
        let first = splitExtension(name)
        var base = first.base
        var ext = first.ext
        if incompleteExtensions.contains(ext) {
            incomplete = true
            let second = splitExtension(base)
            base = second.base
            ext = second.ext
        }
        let isVideo = videoExtensions.contains(ext)

        let words = base.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let sample = words.contains("sample")

        let ex = extractGroups(base)
        let allTokens = tokenize(ex.outside)

        var year: Int? = ex.yearFromGroup
        var titleTokens: [String]

        if let cut = ex.yearCut {
            let prefix = String(ex.outside.prefix(cut))
            var toks = tokenize(prefix)
            if let t = toks.firstIndex(where: { isTechToken($0) }), t > 0 {
                toks = Array(toks[..<t])
            }
            titleTokens = toks
        } else {
            let firstTech = allTokens.firstIndex(where: { isTechToken($0) }) ?? allTokens.count
            var yearIndex: Int? = nil
            if firstTech > 1 {
                for i in 1..<firstTech where yearValue(allTokens[i]) != nil {
                    yearIndex = i
                }
            }
            if let yi = yearIndex {
                year = yearValue(allTokens[yi])
                titleTokens = Array(allTokens[..<yi])
            } else {
                titleTokens = Array(allTokens[..<firstTech])
            }
        }

        while let last = titleTokens.last, last == "-" || last == "–" {
            titleTokens.removeLast()
        }
        if titleTokens.isEmpty { titleTokens = allTokens }
        // "Rosetta, Dardenne, 1999" → "Rosetta, Dardenne"
        let title = titleTokens.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",;: "))

        let rest = Array(allTokens.dropFirst(titleTokens.count))
        let lower = rest.map { $0.lowercased() }
        let heads = lower.map { token -> String in
            if let dash = token.firstIndex(of: "-") { return String(token[..<dash]) }
            return token
        }
        let pool = lower + heads
        func has(_ names: [String]) -> Bool { pool.contains(where: { names.contains($0) }) }

        // Resolution
        var resolution: String? = nil
        let resolutions = ["2160p", "1080p", "720p", "576p", "480p"]
        for t in lower where resolutions.contains(t) {
            resolution = t
            break
        }
        if resolution == nil, has(["4k", "uhd"]) { resolution = "2160p" }

        // Source
        let hasRemux = has(["remux", "bdremux"])
        var source: String? = nil
        if has(["bluray", "blu-ray", "bdrip", "brrip", "bdremux"]) {
            source = hasRemux ? "BluRay REMUX" : "BluRay"
        } else if has(["web-dl", "webdl"]) {
            source = "WEB-DL"
        } else if has(["webrip"]) {
            source = "WEBRip"
        } else if has(["hdtv"]) {
            source = "HDTV"
        } else if has(["dvdrip"]) {
            source = "DVDRip"
        } else if hasRemux {
            source = "REMUX"
        }

        // HDR
        var hdrParts: [String] = []
        if has(["dv", "dovi"]) { hdrParts.append("DV") }
        if has(["hdr", "hdr10", "hdr10+"]) { hdrParts.append("HDR") }
        let hdr: String? = hdrParts.isEmpty ? nil : hdrParts.joined(separator: " ")

        // Video codec
        var codec: String? = nil
        if has(["hevc", "x265", "h265"]) {
            codec = "HEVC"
        } else if has(["x264", "h264", "avc"]) {
            codec = "AVC"
        } else if has(["av1"]) {
            codec = "AV1"
        }

        // Audio
        var tracks: [AudioTrack] = []
        for group in ex.squareGroups {
            for segment in group.split(separator: "+") {
                if let track = parseAudioSegment(String(segment)) { tracks.append(track) }
            }
        }
        if tracks.isEmpty { tracks = fallbackAudio(rest) }

        // Badges
        var badges: [String] = []
        if resolution == "2160p" {
            badges.append("4K")
        } else if let r = resolution {
            badges.append(r)
        }
        if let h = hdr {
            if h.contains("DV") { badges.append("Dolby Vision") }
            if h.contains("HDR") { badges.append("HDR") }
        }
        if let s = source, s.contains("REMUX") { badges.append("REMUX") }
        if tracks.contains(where: { $0.format.contains("Atmos") }) { badges.append("Atmos") }

        return ParsedFilename(
            title: title,
            year: year,
            resolution: resolution,
            source: source,
            hdr: hdr,
            videoCodec: codec,
            audioTracks: tracks,
            isVideo: isVideo,
            isIncomplete: incomplete,
            looksLikeSample: sample,
            badges: badges
        )
    }

    // MARK: - Helpers

    static func lastComponent(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if let last = parts.last { return String(last) }
        return path
    }

    static func splitExtension(_ name: String) -> (base: String, ext: String) {
        guard let dot = name.lastIndex(of: ".") else { return (name, "") }
        let ext = String(name[name.index(after: dot)...]).lowercased()
        if videoExtensions.contains(ext) || otherExtensions.contains(ext) || incompleteExtensions.contains(ext) {
            return (String(name[..<dot]), ext)
        }
        return (name, "")
    }

    struct Extracted {
        var outside: String
        var squareGroups: [String]
        var yearCut: Int?
        var yearFromGroup: Int?
    }

    /// Removes [square] and (round) groups from the name. A round group holding a valid year is
    /// remembered (and where it sat); a round group of plain digits such as "(500)" stays in the title.
    static func extractGroups(_ s: String) -> Extracted {
        var outside = ""
        var squares: [String] = []
        var yearCut: Int? = nil
        var yearVal: Int? = nil
        var current = ""
        var closer: Character? = nil

        for ch in s {
            if let c = closer {
                if ch == c {
                    if c == "]" {
                        squares.append(current)
                        outside.append(" ")
                    } else {
                        let trimmed = current.trimmingCharacters(in: .whitespaces)
                        if let y = yearValue(trimmed) {
                            if yearVal == nil {
                                yearVal = y
                                yearCut = outside.count
                            }
                            outside.append(" ")
                        } else if !trimmed.isEmpty && isDigits(trimmed) {
                            outside.append("(" + trimmed + ")")
                        } else {
                            outside.append(" ")
                        }
                    }
                    current = ""
                    closer = nil
                } else {
                    current.append(ch)
                }
            } else if ch == "[" {
                closer = "]"
            } else if ch == "(" {
                closer = ")"
            } else {
                outside.append(ch)
            }
        }
        return Extracted(outside: outside, squareGroups: squares, yearCut: yearCut, yearFromGroup: yearVal)
    }

    static func tokenize(_ s: String) -> [String] {
        let u = s.replacingOccurrences(of: "_", with: " ")
        // Dots are word separators when they outnumber spaces ("Dune.Part.Two.2024. .HEVC"),
        // and part of the title otherwise ("Mr. Nobody (2009)").
        let dots = u.reduce(0) { $1 == "." ? $0 + 1 : $0 }
        let spaces = u.reduce(0) { $1 == " " ? $0 + 1 : $0 }
        let parts: [Substring] = dots > spaces
            ? u.split(whereSeparator: { $0 == " " || $0 == "." })
            : u.split(separator: " ")
        return parts.map { String($0) }.filter { !$0.isEmpty && $0 != "-" }
    }

    static func isDigits(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber }
    }

    static func isTechToken(_ token: String) -> Bool {
        let t = token.lowercased()
        if techWords.contains(t) { return true }
        if let dash = t.firstIndex(of: "-") {
            let head = String(t[..<dash])
            if techWords.contains(head) { return true }
        }
        if t.hasSuffix("p") || t.hasSuffix("i") {
            let digits = String(t.dropLast())
            if digits.count >= 3 && digits.count <= 4 && isDigits(digits) { return true }
        }
        if t.hasSuffix("bit") {
            let digits = String(t.dropLast(3))
            if isDigits(digits) { return true }
        }
        return false
    }

    /// Latest plausible release year (next year). Computed once.
    static let maxYear = Calendar(identifier: .gregorian).component(.year, from: Date()) + 1

    static func yearValue(_ s: String) -> Int? {
        guard s.count == 4, isDigits(s), let v = Int(s) else { return nil }
        return (1888...maxYear).contains(v) ? v : nil
    }

    static func parseAudioSegment(_ segment: String) -> AudioTrack? {
        let tokens = segment
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map { String($0) }
        guard let firstToken = tokens.first else { return nil }

        var language: String? = nil
        var rest = tokens
        if languages.contains(firstToken.lowercased()) {
            language = firstToken
            rest = Array(tokens.dropFirst())
        }
        rest = rest.filter { !$0.lowercased().hasSuffix("kbps") }
        let hasAudioWord = rest.contains(where: { audioWords.contains($0.lowercased()) })
        if language == nil && !hasAudioWord { return nil }
        if rest.isEmpty && language == nil { return nil }
        return AudioTrack(language: language, format: rest.joined(separator: " "))
    }

    static func fallbackAudio(_ tokens: [String]) -> [AudioTrack] {
        var names: [String] = []
        for token in tokens {
            let lowered = token.lowercased()
            if audioWords.contains(lowered) {
                if !names.contains(token) { names.append(token) }
            } else if lowered == "ma", let last = names.last, last.uppercased().hasPrefix("DTS-HD") {
                names.append(token)
            }
        }
        if names.isEmpty { return [] }
        return [AudioTrack(language: nil, format: names.joined(separator: " "))]
    }
}
