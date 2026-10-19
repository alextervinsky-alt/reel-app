#if os(macOS)
import Foundation
import ReelCore

/// HDR or SDR, to set the TV before Play (see `FilePicture`): your setting, else what the file name
/// or the film's own folder proves, else "not stated".
extension AppModel {
    func picture(of copy: FilmEntry) -> FilePicture {
        FilePicture.of(copy, ownFolders: ownFolders, yours: pictures)
    }

    /// The copies whose picture is shown: the one Play opens first, then the others.
    func pictureCopies(of film: FilmEntry) -> [FilmEntry] {
        let all = copies(of: film)
        guard let playing = onlineCopy(of: film) else { return all }
        return [playing] + all.filter { $0.id != playing.id }
    }

    /// What you set for the file Play opens (and every copy of the same file), nil for the name's.
    func yourPicture(for film: FilmEntry) -> DynamicRange? {
        pictureCopies(of: film).first.flatMap { pictures[$0.fileKey] }
    }

    /// Sets the picture of the file Play opens (and every copy of the same file); nil goes back to
    /// what the name says.
    func setPicture(_ range: DynamicRange?, for film: FilmEntry) {
        guard let copy = pictureCopies(of: film).first else { return }
        pictures[copy.fileKey] = range
        scheduleSave(.notes)
        // Search finds it by its new picture.
        itemCache[film.personalKey] = nil
        scheduleRebuild()
    }

    /// How many files' pictures are known and why (Settings › Performance), each file once.
    func pictureCounts() -> [(basis: FilePicture.Basis, files: Int)] {
        var seen = Set<String>()
        var counts: [FilePicture.Basis: Int] = [:]
        for film in films where seen.insert(film.fileKey).inserted {
            counts[picture(of: film).basis, default: 0] += 1
        }
        let order: [FilePicture.Basis] = [.yours, .named, .source, .convention, .folder, .notStated]
        return order.compactMap { basis in counts[basis].map { (basis, $0) } }
    }
}

extension FilePicture.Basis {
    /// For Settings › Performance.
    var title: String {
        switch self {
        case .yours: "Set by you"
        case .named: "The file name says"
        case .source: "SDR by its source (DVD, 720p, 1080p Blu-ray)"
        case .convention: "SDR by release-name convention"
        case .folder: "The film's own folder says"
        case .notStated: "Not stated"
        }
    }
}
#endif
