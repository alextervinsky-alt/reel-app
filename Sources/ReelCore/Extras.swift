import Foundation

// MARK: - Extras: everything that sits next to a film in its folder

/// What a file next to a film is.
public enum ExtraKind: String, Codable, Sendable, CaseIterable {
    // Videos, in the order they're shown.
    case trailer, interview, behindTheScenes, deletedScene, festival, short, commentary, gallery, bonus
    /// The film itself in pieces ("CD2", "Part 2").
    case part
    case sample
    // Other files.
    case subtitle, document, image, audio

    public var isVideo: Bool {
        switch self {
        case .subtitle, .document, .image, .audio: false
        default: true
        }
    }

    /// Bonus material (not a sample or a piece of the film).
    public var isBonus: Bool { isVideo && self != .part && self != .sample }

    public var label: String {
        switch self {
        case .trailer: "Trailer"
        case .interview: "Interview"
        case .behindTheScenes: "Behind the Scenes"
        case .deletedScene: "Deleted Scene"
        case .festival: "Festival & Press"
        case .short: "Short Film"
        case .commentary: "Commentary"
        case .gallery: "Gallery"
        case .bonus: "Bonus"
        case .part: "Part"
        case .sample: "Sample"
        case .subtitle: "Subtitles"
        case .document: "Document"
        case .image: "Image"
        case .audio: "Audio"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExtraKind(rawValue: raw) ?? .bonus
    }

    // MARK: Recognising kinds from names

    /// Words and phrases in a file name that say what kind of extra it is (checked in this order).
    static let keywords: [(ExtraKind, [String])] = [
        (.sample, ["sample"]),
        (.trailer, ["trailer", "trailers", "teaser", "tv spot", "tv spots", "promo"]),
        (.deletedScene, ["deleted", "extended scene", "alternate ending", "alternate scene", "outtake", "outtakes",
                         "bloopers", "gag reel"]),
        (.behindTheScenes, ["making of", "the making", "behind the scenes", "bts", "featurette", "featurettes",
                            "on set", "on location"]),
        (.interview, ["interview", "interviews", "q a", "qa", "press conference", "in conversation"]),
        (.festival, ["cannes", "venice", "berlinale", "festival", "premiere", "sundance", "tiff"]),
        (.commentary, ["commentary"]),
        (.gallery, ["stills", "gallery", "photos"]),
        (.short, ["short film", "shorts"]),
        (.bonus, ["bonus", "extra", "extras", "special feature", "special features", "intro", "introduction",
                  "restoration", "video essay", "appreciation", "music video"]),
    ]

    /// Folder names for bonus material (Plex / Jellyfin / disc-rip conventions) and what they hold.
    static let folderKinds: [String: ExtraKind?] = [
        "extras": nil, "extra": nil, "bonus": nil, "bonus features": nil, "special features": nil,
        "featurettes": .behindTheScenes, "behind the scenes": .behindTheScenes, "deleted scenes": .deletedScene,
        "interviews": .interview, "trailers": .trailer, "shorts": .short, "sample": .sample, "samples": .sample,
        "subs": nil, "subtitles": nil, "artwork": nil, "covers": nil, "scans": nil,
    ]

    /// The kind a file name announces, if any ("Rosetta-Cannes" → festival).
    static func announced(in name: String) -> ExtraKind? {
        let padded = " " + TitleSimilarity.normalize(name) + " "
        for (kind, phrases) in keywords where phrases.contains(where: { padded.contains(" " + $0 + " ") }) {
            return kind
        }
        return nil
    }
}

/// A file that belongs to a film without being the film: bonus videos, subtitles, notes, artwork.
public struct FilmExtra: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Path from the drive (or film folder) root, like the film's own `relativePath`.
    public let relativePath: String
    public let size: Int64
    public let kind: ExtraKind

    public var id: String { relativePath }

    public init(relativePath: String, size: Int64, kind: ExtraKind) {
        self.relativePath = relativePath
        self.size = size
        self.kind = kind
    }

    public var fileName: String { FilenameParser.lastComponent(relativePath) }

    public var fileExtension: String { FilmExtra.split(fileName).ext }

    /// File name without the extension.
    public var baseName: String { FilmExtra.split(fileName).base }

    /// Folder the file is in, relative to the drive root ("" for the root).
    var folder: String {
        guard let slash = relativePath.lastIndex(of: "/") else { return "" }
        return String(relativePath[..<slash])
    }

    /// A readable name: the film's title, years and technical words are dropped,
    /// so "Rosetta-Cannes.avi" is "Cannes" and "Fallen.Angels.Trailer.1080p.mkv" is "Trailer".
    public func title(removing filmTitles: [String]) -> String {
        let outside = FilenameParser.extractGroups(baseName).outside
        var words = outside.split(whereSeparator: { " ._-".contains($0) }).map(String.init)
        let normalized = words.map { TitleSimilarity.normalize($0) }
        for film in filmTitles {
            let filmWords = TitleSimilarity.normalize(film).split(separator: " ").map(String.init)
            guard !filmWords.isEmpty else { continue }
            let start = normalized.first == "the" && filmWords.first != "the" ? 1 : 0
            let end = start + filmWords.count
            if words.count > end, Array(normalized[start..<end]) == filmWords {
                words.removeFirst(end)
                break
            }
        }
        while words.count > 1, let first = words.first, FilenameParser.yearValue(first) != nil {
            words.removeFirst()
        }
        if let cut = words.indices.first(where: {
            $0 > 0 && (FilenameParser.isTechToken(words[$0]) || FilenameParser.yearValue(words[$0]) != nil)
        }) {
            words = Array(words[..<cut])
        }
        let title = words.joined(separator: " ")
        guard let first = title.first else { return kind.label }
        return first.uppercased() + title.dropFirst()
    }

    // MARK: Subtitles

    /// "English", "Estonian"… read from the end of a subtitle's name ("Film.en.srt", "Film_English.srt").
    public var language: String? { FilmExtra.subtitleTags(baseName).language }

    /// "Forced" or "SDH" when the name says so.
    public var subtitleFlag: String? { FilmExtra.subtitleTags(baseName).flag }

    public var subtitleFormat: String {
        switch fileExtension {
        case "srt": "SRT"
        case "idx", "sub": "VobSub"
        case "ass", "ssa": "ASS"
        case "vtt": "WebVTT"
        case "sup": "PGS"
        default: fileExtension.uppercased()
        }
    }

    /// The name without language and flag tags: "Film.en.forced" → "Film". Matches a subtitle
    /// to the video it belongs to.
    var subtitleStem: String { FilmExtra.subtitleTags(baseName).stem }

    static let languageNames: [String: String] = {
        let table: [(String, [String])] = [
            ("English", ["en", "eng", "english"]), ("Estonian", ["et", "est", "estonian", "eesti"]),
            ("Russian", ["ru", "rus", "russian"]), ("Finnish", ["fi", "fin", "finnish"]),
            ("French", ["fr", "fre", "fra", "french"]), ("German", ["de", "ger", "deu", "german"]),
            ("Spanish", ["es", "spa", "spanish"]), ("Italian", ["it", "ita", "italian"]),
            ("Swedish", ["sv", "swe", "swedish"]), ("Norwegian", ["no", "nor", "norwegian"]),
            ("Danish", ["da", "dan", "danish"]), ("Dutch", ["nl", "dut", "nld", "dutch"]),
            ("Polish", ["pl", "pol", "polish"]), ("Portuguese", ["pt", "por", "portuguese"]),
            ("Japanese", ["ja", "jpn", "japanese"]), ("Korean", ["ko", "kor", "korean"]),
            ("Chinese", ["zh", "chi", "zho", "chs", "cht", "chinese"]), ("Latvian", ["lv", "lav", "latvian"]),
            ("Lithuanian", ["lt", "lit", "lithuanian"]), ("Ukrainian", ["uk", "ukr", "ukrainian"]),
            ("Czech", ["cs", "cze", "ces", "czech"]), ("Hungarian", ["hu", "hun", "hungarian"]),
            ("Turkish", ["tr", "tur", "turkish"]), ("Greek", ["el", "gre", "ell", "greek"]),
            ("Hebrew", ["he", "heb", "hebrew"]), ("Arabic", ["ar", "ara", "arabic"]),
        ]
        var names: [String: String] = [:]
        for (name, codes) in table { for code in codes { names[code] = name } }
        return names
    }()

    static let flagNames: [String: String] = ["forced": "Forced", "sdh": "SDH", "cc": "SDH", "hi": "SDH"]

    /// Language and flag tags at the end of a name. Two-letter codes only count as their own
    /// dot-separated part ("Film.et.srt"), so "Luc et Jean-Pierre" isn't Estonian.
    static func subtitleTags(_ base: String) -> (stem: String, language: String?, flag: String?) {
        var parts = base.components(separatedBy: ".")
        var language: String?
        var flag: String?
        while parts.count > 1, let last = parts.last?.lowercased() {
            if flag == nil, let f = flagNames[last] {
                flag = f
            } else if language == nil, let l = languageNames[last] {
                language = l
            } else {
                break
            }
            parts.removeLast()
        }
        var stem = parts.joined(separator: ".")
        if language == nil {
            // "Film_English", "Film - eng": a full name or three-letter code as the last word.
            let words = stem.split(whereSeparator: { !$0.isLetter })
            if words.count > 1, let last = words.last?.lowercased(), last.count >= 3, let l = languageNames[last] {
                language = l
                if let range = stem.range(of: String(words.last!), options: .backwards) {
                    stem = String(stem[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " ._-"))
                }
            }
        }
        return (stem, language, flag)
    }

    // MARK: File types

    static let subtitleExtensions: Set<String> = ["srt", "sub", "idx", "ass", "ssa", "vtt", "sup", "smi"]
    static let documentExtensions: Set<String> = ["txt", "nfo", "pdf", "rtf", "md", "doc", "docx", "htm", "html"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "tif", "tiff", "bmp", "heic"]
    static let audioExtensions: Set<String> = ["flac", "mp3", "m4a", "aac", "ac3", "dts", "wav", "ogg", "opus", "mka"]
    static let junkExtensions: Set<String> = ["exe", "url", "lnk", "torrent", "nzb", "sfv", "md5", "par2", "db", "ini"]

    static func split(_ name: String) -> (base: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        let ext = name[name.index(after: dot)...]
        guard (1...5).contains(ext.count), ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { return (name, "") }
        return (String(name[..<dot]), ext.lowercased())
    }

    /// Release-group adverts that come with downloads ("www.example.com.jpg", a site name in a .txt).
    static func isAdvert(_ base: String) -> Bool {
        let lower = base.lowercased()
        if ["rarbg", "yts", "proxies", "do_not_mirror", "www.", "torrent", "eztv", "ettv"].contains(where: lower.contains) {
            return true
        }
        let domainEndings = [".com", ".net", ".org", ".to", ".ag", ".mx", ".lt", ".am", ".se", ".me", ".io", ".cc", ".tv"]
        return domainEndings.contains(where: { lower.hasSuffix($0) || lower.contains($0 + ".") || lower.contains($0 + " ") })
    }
}

/// A film's extras sorted for showing.
public struct ExtrasCatalog: Equatable, Sendable {
    public struct Video: Identifiable, Equatable, Sendable {
        public let file: FilmExtra
        /// Subtitles made for this video (same name).
        public let subtitles: [FilmExtra]
        public var id: String { file.id }
    }

    /// Bonus material: trailers, interviews, behind the scenes…
    public var videos: [Video] = []
    /// The film's own subtitles, one per track (an .idx/.sub pair counts once).
    public var subtitles: [FilmExtra] = []
    /// Further pieces of the film, samples, notes, artwork and audio.
    public var otherFiles: [FilmExtra] = []


    public init(_ extras: [FilmExtra]) {
        // An .idx/.sub pair is one subtitle track: keep the .idx (the readable half).
        let idxNames = Set(extras.filter { $0.fileExtension == "idx" }.map { $0.folder + "/" + $0.baseName.lowercased() })
        let subtitleFiles = extras.filter {
            $0.kind == .subtitle && !($0.fileExtension == "sub" && idxNames.contains($0.folder + "/" + $0.baseName.lowercased()))
        }
        let bonus = extras.filter { $0.kind.isBonus }
        let videoStems = Set(bonus.map { $0.baseName.lowercased() })
        var perVideo: [String: [FilmExtra]] = [:]
        for subtitle in subtitleFiles {
            let stem = subtitle.subtitleStem.lowercased()
            if videoStems.contains(stem) {
                perVideo[stem, default: []].append(subtitle)
            } else {
                subtitles.append(subtitle)
            }
        }
        let order = Dictionary(uniqueKeysWithValues: ExtraKind.allCases.enumerated().map { ($1, $0) })
        videos = bonus
            .sorted { (order[$0.kind] ?? 0, $0.fileName.lowercased()) < (order[$1.kind] ?? 0, $1.fileName.lowercased()) }
            .map { Video(file: $0, subtitles: perVideo[$0.baseName.lowercased()] ?? []) }
        subtitles.sort { ($0.language ?? "~", $0.fileName) < ($1.language ?? "~", $1.fileName) }
        otherFiles = extras
            .filter { !$0.kind.isBonus && $0.kind != .subtitle }
            .sorted { (order[$0.kind] ?? 0, $0.fileName.lowercased()) < (order[$1.kind] ?? 0, $1.fileName.lowercased()) }
    }
}

/// Finds the person a bonus video is about: "Chris Doyle.mkv" → Christopher Doyle, cinematographer.
public enum ExtraPeople {
    public static func person(in title: String, among people: [(name: String, role: String)]) -> (name: String, role: String)? {
        let words = Set(TitleSimilarity.normalize(title).split(separator: " ").map(String.init))
        guard !words.isEmpty else { return nil }
        for person in people {
            let parts = TitleSimilarity.normalize(person.name).split(separator: " ").map(String.init)
            guard parts.count >= 2, let first = parts.first, let last = parts.last, last.count >= 3,
                  words.contains(last) else { continue }
            if words.contains(first) || words.contains(where: { $0.count >= 3 && first.hasPrefix($0) }) {
                return person
            }
        }
        return nil
    }
}

// MARK: - Grouping files into films

/// Works out, from a folder listing, which video is the film and which files are its extras.
///
/// - The drive root is a shelf: every film file there is a film; files named like one of them
///   (subtitles, a trailer) go with it.
/// - A folder with one film is that film's folder: everything else in it, and in its subfolders,
///   is an extra (bonus videos, samples, subtitles, notes, artwork).
/// - A folder with several films is a collection: files go with the film they're named after.
/// - Bonus folders ("Extras", "Featurettes", "Trailers"…) next to the film's own folder go with it.
enum FilmGrouping {
    struct File {
        let relativePath: String
        let folder: String
        let name: String
        let size: Int64
        let modified: Date?
        let parsed: ParsedFilename
        let normalizedTitle: String
        let normalizedName: String

        init(relativePath: String, size: Int64, modified: Date?) {
            self.relativePath = relativePath
            let slash = relativePath.lastIndex(of: "/")
            folder = slash.map { String(relativePath[..<$0]) } ?? ""
            name = slash.map { String(relativePath[relativePath.index(after: $0)...]) } ?? relativePath
            self.size = size
            self.modified = modified
            parsed = FilenameParser.parse(name)
            normalizedTitle = TitleSimilarity.normalize(parsed.title)
            normalizedName = TitleSimilarity.normalize(FilmExtra.split(name).base)
        }

        var base: String { FilmExtra.split(name).base }
        var announcedKind: ExtraKind? { ExtraKind.announced(in: FilmExtra.split(name).base) }
    }

    final class Film {
        let main: File
        var extras: [FilmExtra] = []
        init(main: File) { self.main = main }
    }

    static func group(_ files: [File], minimumSize: Int64) -> [ScannedFile] {
        var byFolder: [String: [File]] = [:]
        var children: [String: Set<String>] = [:]
        for file in files {
            byFolder[file.folder, default: []].append(file)
            var folder = file.folder
            while !folder.isEmpty {
                let parent = folder.lastIndex(of: "/").map { String(folder[..<$0]) } ?? ""
                let (inserted, _) = children[parent, default: []].insert(folder)
                if !inserted { break }
                folder = parent
            }
        }

        var films: [Film] = []
        func isCandidate(_ f: File) -> Bool {
            f.parsed.isVideo && f.size >= minimumSize && !f.parsed.looksLikeSample
        }

        func walk(_ folder: String, owner: Film?, inBonus: Bool) -> (films: [Film], orphans: [File]) {
            let here = (byFolder[folder] ?? []).sorted { $0.size > $1.size }
            var inSubtree: [Film] = []
            var orphans: [File] = []
            var owner = owner
            let inBonus = inBonus || (owner == nil && isBonusFolder(folder))

            if let current = owner {
                for file in here {
                    if isCandidate(file) && !insideBonusFolder(file.folder) && !isExtra(file, of: current.main) {
                        let film = Film(main: file)
                        films.append(film)
                        inSubtree.append(film)
                    } else {
                        attach(file, to: current)
                    }
                }
            } else if inBonus {
                orphans = here
            } else if folder.isEmpty {
                // The drive root: a shelf of films. A video that calls itself a trailer, interview…
                // goes with the film it's named after; "The Interview (2014)" is still a film.
                var shelf: [Film] = []
                for file in here where isCandidate(file) && file.announcedKind == nil {
                    shelf.append(Film(main: file))
                }
                var named: [Film] = []
                for file in here where isCandidate(file) && file.announcedKind != nil
                    && namesake(of: file, in: shelf) == nil && file.parsed.year != nil {
                    named.append(Film(main: file))
                }
                shelf += named
                let filmPaths = Set(shelf.map { $0.main.relativePath })
                for file in here where !filmPaths.contains(file.relativePath) {
                    if let film = namesake(of: file, in: shelf) { attach(file, to: film) }
                }
                films += shelf
                inSubtree += shelf
            } else {
                let candidates = here.filter(isCandidate)
                if let main = pickMain(candidates) {
                    var folderFilms = [Film(main: main)]
                    for other in candidates where other.relativePath != main.relativePath && !isExtra(other, of: main) {
                        folderFilms.append(Film(main: other))
                    }
                    films += folderFilms
                    inSubtree += folderFilms
                    let rest = here.filter { file in !folderFilms.contains { $0.main.relativePath == file.relativePath } }
                    if folderFilms.count == 1 {
                        owner = folderFilms[0]
                        for file in rest { attach(file, to: folderFilms[0]) }
                    } else {
                        for file in rest {
                            if let film = namesake(of: file, in: folderFilms) { attach(file, to: film) }
                        }
                    }
                } else {
                    orphans = here
                }
            }

            for child in (children[folder] ?? []).sorted() {
                let result = walk(child, owner: owner, inBonus: inBonus)
                inSubtree += result.films
                orphans += result.orphans
            }
            // A bonus folder or loose files beside a single film's folder belong to that film.
            if owner == nil, !folder.isEmpty, !orphans.isEmpty, inSubtree.count == 1 {
                for file in orphans { attach(file, to: inSubtree[0]) }
                orphans = []
            }
            return (inSubtree, orphans)
        }

        _ = walk("", owner: nil, inBonus: false)

        return films.map { film in
            ScannedFile(relativePath: film.main.relativePath, fileName: film.main.name, size: film.main.size,
                        modified: film.main.modified,
                        extras: film.extras.sorted { $0.relativePath < $1.relativePath })
        }
        .sorted { $0.relativePath < $1.relativePath }
    }

    // MARK: Which video is the film

    /// The biggest video that doesn't call itself a trailer, interview…; the first part of a
    /// film split in pieces ("CD1").
    static func pickMain(_ candidates: [File]) -> File? {
        guard var main = candidates.first(where: { $0.announcedKind == nil }) ?? candidates.first else { return nil }
        if let piece = part(main), piece.number > 1,
           let first = candidates.first(where: { other in
               guard let otherPiece = part(other) else { return false }
               return otherPiece.number == 1 && otherPiece.rest == piece.rest
           }) {
            main = first
        }
        return main
    }

    /// Whether `file`, in the same folder as the film `main`, is bonus material rather than another film.
    static func isExtra(_ file: File, of main: File) -> Bool {
        if let a = part(file), let b = part(main), a.rest == b.rest, a.number != b.number { return true }
        let small = Double(file.size) < 0.4 * Double(main.size)
        let ownYear = file.parsed.year != nil && file.parsed.year != main.parsed.year
        let related = relatedTitles(file.normalizedTitle, main.normalizedTitle)
        if file.announcedKind != nil { return !(ownYear && !small) } // "The Interview (2014)" is a film
        if ownYear { return false }                                       // another film from another year
        if small { return file.parsed.year == nil || related }            // "Chris Doyle.mkv", "Rosetta-Cannes.avi"
        return file.parsed.year == nil && main.parsed.year != nil && related
    }

    static func relatedTitles(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.hasPrefix(b + " ") || b.hasPrefix(a + " ") || TitleSimilarity.similarity(a, b) >= 0.85
    }

    /// "Film CD2", "Film.Part.2", "Film disc2" → (2, "film").
    static func part(_ file: File) -> (number: Int, rest: String)? {
        let words = file.normalizedName.split(separator: " ").map(String.init)
        let markers = ["cd", "disc", "disk", "part", "pt"]
        for (i, word) in words.enumerated() {
            var number: Int?
            var width = 1
            if let marker = markers.first(where: { word.hasPrefix($0) }), word.count == marker.count + 1,
               let digit = Int(word.dropFirst(marker.count)), (1...9).contains(digit) {
                number = digit
            } else if markers.contains(word), i + 1 < words.count, words[i + 1].count == 1,
                      let digit = Int(words[i + 1]), (1...9).contains(digit) {
                number = digit
                width = 2
            }
            if let number {
                var rest = words
                rest.removeSubrange(i..<(i + width))
                return (number, rest.joined(separator: " "))
            }
        }
        return nil
    }

    // MARK: Bonus folders

    /// A bonus folder ("Extras", "Featurettes"…). At the top of the drive, "Shorts" and "Bonus"
    /// could be someone's own shelf of films, so only the unmistakable names count there.
    static func isBonusFolder(_ folder: String) -> Bool {
        let slash = folder.lastIndex(of: "/")
        let name = (slash.map { String(folder[folder.index(after: $0)...]) } ?? folder).lowercased()
        guard ExtraKind.folderKinds.keys.contains(name) else { return false }
        return slash != nil || !["shorts", "bonus", "artwork", "covers", "scans"].contains(name)
    }

    static func insideBonusFolder(_ folder: String) -> Bool {
        var current = folder
        while !current.isEmpty {
            if isBonusFolder(current) { return true }
            guard let slash = current.lastIndex(of: "/") else { return false }
            current = String(current[..<slash])
        }
        return false
    }

    /// The film a loose file is named after: "Film.en.srt" or "Film - Trailer.mkv" beside "Film.mkv".
    static func namesake(of file: File, in films: [Film]) -> Film? {
        let base = file.base.lowercased()
        let named = films.first { film in
            let filmBase = film.main.base.lowercased()
            guard base.hasPrefix(filmBase) else { return false }
            // "Up.srt" goes with "Up.mkv", "Upgrade.srt" doesn't.
            guard let next = base.dropFirst(filmBase.count).first else { return true }
            return " ._-([".contains(next)
        }
        if let named { return named }
        guard file.parsed.isVideo, file.announcedKind != nil else { return nil }
        return films.first { film in
            film.main.normalizedTitle.count >= 3 && (relatedTitles(file.normalizedTitle, film.main.normalizedTitle)
                || file.normalizedName.hasPrefix(film.main.normalizedTitle + " "))
        }
    }

    // MARK: Attaching files

    static func attach(_ file: File, to film: Film) {
        guard let kind = kind(of: file, filmFolder: film.main.folder) else { return }
        film.extras.append(FilmExtra(relativePath: file.relativePath, size: file.size, kind: kind))
    }

    /// What a file is, or nil when it isn't worth showing (adverts, checksums, unfinished downloads).
    static func kind(of file: File, filmFolder: String) -> ExtraKind? {
        let (base, ext) = FilmExtra.split(file.name)
        if file.parsed.isIncomplete { return nil }
        if file.parsed.isVideo {
            if file.parsed.looksLikeSample { return .sample }
            if let announced = ExtraKind.announced(in: base) { return announced }
            if part(file) != nil { return .part }
            return folderKind(file.folder, below: filmFolder) ?? .bonus
        }
        if FilmExtra.junkExtensions.contains(ext) || FilmExtra.isAdvert(base) { return nil }
        if FilmExtra.subtitleExtensions.contains(ext) { return .subtitle }
        if FilmExtra.documentExtensions.contains(ext) { return .document }
        if FilmExtra.imageExtensions.contains(ext) { return .image }
        if FilmExtra.audioExtensions.contains(ext) { return .audio }
        return nil
    }

    /// The kind a bonus folder announces ("Trailers" → trailer), looking up to the film's folder.
    static func folderKind(_ folder: String, below filmFolder: String) -> ExtraKind? {
        var current = folder
        while !current.isEmpty && current != filmFolder {
            let name = current.split(separator: "/").last.map { $0.lowercased() } ?? ""
            if let kind = ExtraKind.folderKinds[name] ?? nil { return kind }
            guard let slash = current.lastIndex(of: "/") else { break }
            current = String(current[..<slash])
        }
        return nil
    }
}
