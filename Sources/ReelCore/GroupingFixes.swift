import Foundation

/// Regrouping done by hand, kept in Your Notes and applied after every scan. Paths are relative to
/// the drive's film folder, so a fix made on Films also holds on its Backup mirror.
public struct GroupingFixes: Codable, Equatable, Sendable {
    /// A file Reel took for a film → the film it belongs to.
    public var extraOf: [String: String]
    /// Files Reel took for extras that are films of their own.
    public var films: Set<String>

    public init(extraOf: [String: String] = [:], films: Set<String> = []) {
        self.extraOf = extraOf
        self.films = films
    }

    public var isEmpty: Bool { extraOf.isEmpty && films.isEmpty }

    public func isFixed(_ path: String) -> Bool { extraOf[path] != nil || films.contains(path) }

    /// "This is an extra of …" (replaces any earlier fix of the file).
    public mutating func makeExtra(_ path: String, of filmPath: String) {
        guard path != filmPath else { return }
        films.remove(path)
        extraOf[path] = filmPath
        // A film that becomes an extra can't keep other files as its own extras.
        for (extra, owner) in extraOf where owner == path { extraOf[extra] = filmPath }
    }

    /// "This is a film".
    public mutating func makeFilm(_ path: String) {
        extraOf[path] = nil
        films.insert(path)
    }

    public mutating func reset(_ path: String) {
        extraOf[path] = nil
        films.remove(path)
    }

    /// Applies the fixes to a drive's grouped files. Fixes whose files aren't on this drive are skipped.
    public func apply(to scanned: [ScannedFile]) -> [ScannedFile] {
        guard !isEmpty else { return scanned }
        var result = scanned

        // Extras that are films: taken out of their film and listed on their own.
        for path in films.sorted() {
            guard !result.contains(where: { $0.relativePath == path }),
                  let owner = result.firstIndex(where: { $0.extras.contains { $0.relativePath == path } }),
                  let extra = result[owner].extras.first(where: { $0.relativePath == path }) else { continue }
            result[owner].extras.removeAll { $0.relativePath == path }
            result.append(ScannedFile(relativePath: path, fileName: extra.fileName, size: extra.size, modified: nil))
        }

        // Films that are extras: folded into their film, along with their own extras.
        for (path, filmPath) in extraOf.sorted(by: { $0.key < $1.key }) {
            guard let i = result.firstIndex(where: { $0.relativePath == path }),
                  result.contains(where: { $0.relativePath == filmPath }) else { continue }
            let moved = result.remove(at: i)
            guard let target = result.firstIndex(where: { $0.relativePath == filmPath }) else { continue }
            let kind = ExtraKind.announced(in: FilmExtra.split(moved.fileName).base) ?? .bonus
            result[target].extras += [FilmExtra(relativePath: moved.relativePath, size: moved.size, kind: kind)] + moved.extras
            result[target].extras.sort { $0.relativePath < $1.relativePath }
        }
        return result.sorted { $0.relativePath < $1.relativePath }
    }
}
