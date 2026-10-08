#if os(macOS)
import Foundation
import ReelCore

/// Finds where each drive is mounted right now, by the volume's built-in ID.
enum DriveLocator {
    /// Volume ID → mount points. A block-level clone (e.g. a backup made with Disk Utility's
    /// Restore) has the same ID as the original, so one ID can be mounted twice.
    static func mountedVolumes() -> [String: [URL]] {
        let keys: [URLResourceKey] = [.volumeUUIDStringKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? []
        var map: [String: [URL]] = [:]
        for url in urls {
            if let id = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString {
                map[id, default: []].append(url)
            }
        }
        return map
    }

    /// Where each drive is right now. Touches the disk, so call it off the main thread when possible.
    static func locate(_ drives: [Drive]) -> [String: URL] {
        guard !drives.isEmpty else { return [:] }
        let volumes = mountedVolumes()
        var result: [String: URL] = [:]
        var taken = Set<String>()

        func place(_ drive: Drive, at volume: URL) {
            let url = drive.folderInVolume.isEmpty
                ? volume
                : volume.appendingPathComponent(drive.folderInVolume, isDirectory: true)
            if isFolder(url) {
                result[drive.id] = url
                taken.insert(volume.path + "|" + drive.folderInVolume)
            }
        }

        // First the drives found where they were last time, then the rest on any free mount.
        let withID = drives.filter { $0.volumeUUID != nil }
        for drive in withID {
            let mounts = volumes[drive.volumeUUID!] ?? []
            if let exact = mounts.first(where: { lastKnownPath(drive, matches: $0) }) {
                place(drive, at: exact)
            }
        }
        for drive in withID where result[drive.id] == nil {
            let mounts = volumes[drive.volumeUUID!] ?? []
            if let free = mounts.first(where: { !taken.contains($0.path + "|" + drive.folderInVolume) }) {
                place(drive, at: free)
            }
        }
        for drive in drives where drive.volumeUUID == nil {
            let url = URL(fileURLWithPath: drive.lastKnownPath, isDirectory: true)
            if isFolder(url) { result[drive.id] = url }
        }
        return result
    }

    private static func lastKnownPath(_ drive: Drive, matches volume: URL) -> Bool {
        let expected = drive.folderInVolume.isEmpty
            ? volume.path
            : volume.appendingPathComponent(drive.folderInVolume).path
        return expected == drive.lastKnownPath
    }

    static func makeDrive(for url: URL) -> Drive {
        let keys: Set<URLResourceKey> = [.volumeURLKey, .volumeUUIDStringKey, .volumeLocalizedNameKey]
        let values = try? url.resourceValues(forKeys: keys)
        let path = url.standardizedFileURL.path
        var folder = ""
        if let volumePath = values?.volume?.standardizedFileURL.path, path.hasPrefix(volumePath) {
            folder = String(path.dropFirst(volumePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let name = folder.isEmpty ? (values?.volumeLocalizedName ?? url.lastPathComponent) : url.lastPathComponent
        var drive = Drive(name: name, volumeUUID: values?.volumeUUIDString, folderInVolume: folder, lastKnownPath: path)
        // If the volume ID doesn't lead back to this exact folder (e.g. a folder on the Mac's
        // own disk), recognise it by its path instead.
        if drive.volumeUUID != nil, locate([drive])[drive.id]?.standardizedFileURL.path != path {
            drive.volumeUUID = nil
            drive.folderInVolume = ""
        }
        return drive
    }

    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// Moves data from the first build's location (~/Library/Application Support/Reel) into
/// Documents/Reel and removes the web cache and cookie folders that build left behind.
enum StorageMigration {
    static func run(into folder: ReelFolder) {
        let fm = FileManager.default
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let old = library.appendingPathComponent("Application Support/Reel", isDirectory: true)

        if fm.fileExists(atPath: old.path) {
            try? fm.createDirectory(at: folder.root, withIntermediateDirectories: true)
            let moves: [(String, URL)] = [
                ("you.json", folder.notes),
                ("library.json", folder.library),
                ("settings.json", folder.settings),
            ]
            for (name, target) in moves {
                let source = old.appendingPathComponent(name)
                if fm.fileExists(atPath: source.path) && !fm.fileExists(atPath: target.path) {
                    try? fm.moveItem(at: source, to: target)
                }
            }
            let oldCopies = old.appendingPathComponent("Safety copies", isDirectory: true)
            if let names = try? fm.contentsOfDirectory(atPath: oldCopies.path) {
                try? fm.createDirectory(at: folder.safetyCopies, withIntermediateDirectories: true)
                for name in names where name.hasPrefix("you-") {
                    let target = folder.safetyCopies.appendingPathComponent("Your Notes \(name.dropFirst(4))")
                    try? fm.moveItem(at: oldCopies.appendingPathComponent(name), to: target)
                }
            }
            // Remove the old folder only once the notes are safely in the new place.
            if !fm.fileExists(atPath: old.appendingPathComponent("you.json").path) {
                try? fm.removeItem(at: old)
            }
        }

        if let bundleID = Bundle.main.bundleIdentifier {
            for leftover in ["Caches/\(bundleID)", "HTTPStorages/\(bundleID)", "HTTPStorages/\(bundleID).binarycookies"] {
                let url = library.appendingPathComponent(leftover)
                if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
            }
        }
    }
}
#endif
