#if os(macOS)
import AppKit
import ReelCore

extension AppModel {
    func film(id: String) -> FilmEntry? {
        films.first { $0.id == id }
    }

    /// Every copy of the film, main drive first. Read from `films`, so views showing copies
    /// follow every change.
    func copies(of film: FilmEntry) -> [FilmEntry] {
        let key = film.personalKey
        let all = films.filter { $0.personalKey == key }
        return all.filter { drive($0.driveID)?.isBackup != true } + all.filter { drive($0.driveID)?.isBackup == true }
    }

    func drive(_ id: String) -> Drive? {
        drives.first { $0.id == id }
    }

    func fileURL(_ film: FilmEntry) -> URL? {
        mounted[film.driveID]?.appendingPathComponent(film.relativePath)
    }

    var backupDrives: [Drive] { drives.filter { $0.isBackup } }

    // MARK: - Adding and removing drives

    func chooseDrive() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Drive"
        panel.message = "Choose your film drive, or the folder on it that holds your films."
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addDrive(at: url)
    }

    func addDrive(at url: URL) {
        var drive = DriveLocator.makeDrive(for: url)
        let duplicate = drives.first { existing in
            guard let id = existing.volumeUUID, let newID = drive.volumeUUID else {
                // Recognised by path (e.g. a folder on the Mac's own disk).
                return existing.volumeUUID == nil && drive.volumeUUID == nil && existing.lastKnownPath == drive.lastKnownPath
            }
            // Same volume and folder, unless it's a clone mounted somewhere else.
            let mountedAt = mounted[existing.id]?.path
            return id == newID && existing.folderInVolume == drive.folderInVolume
                && (mountedAt == nil || mountedAt == drive.lastKnownPath)
        }
        if let duplicate {
            notice = "\(duplicate.name) is already in Reel."
            return
        }
        // Main and Backup drives often share a name: the second one is the Backup.
        if drives.contains(where: { $0.name == drive.name }) {
            drive.name += " (Backup)"
            drive.isBackup = true
        }
        drives.append(drive)
        scheduleSave(.settings)
        refreshMounts()
    }

    func renameDrive(_ id: String, to name: String) {
        guard let i = drives.firstIndex(where: { $0.id == id }) else { return }
        drives[i].name = name
        scheduleSave(.settings)
    }

    /// Marks a drive as the mirror of the others (or not).
    func setBackup(_ id: String, _ isBackup: Bool) {
        guard let i = drives.firstIndex(where: { $0.id == id }), drives[i].isBackup != isBackup else { return }
        drives[i].isBackup = isBackup
        scheduleSave(.settings)
        rebuild()
    }

    /// Forgets a drive and its files. Notes stay (they belong to films, not files).
    func removeDrive(_ id: String) {
        drives.removeAll { $0.id == id }
        mounted[id] = nil
        scheduleSave(.settings)
        setFilms(films.filter { $0.driveID != id })
        rebuild()
    }

    /// Drives that were scanned before Reel 1.0 start counting arrivals now, so the library as it
    /// is never shows up as new. A drive that has never been scanned starts after its first scan.
    func startArrivalsForExistingDrives() {
        let scanned = Set(films.map { $0.driveID })
        let now = Date()
        var changed = false
        for i in drives.indices where drives[i].arrivalsSince == nil && scanned.contains(drives[i].id) {
            drives[i].arrivalsSince = now
            changed = true
        }
        if changed { scheduleSave(.settings) }
    }

    // MARK: - Mounting and scanning

    /// Re-checks which drives are connected. The disk checks run in the background, so a slow or
    /// sleeping drive never freezes the window.
    func refreshMounts() {
        // Before the library is read, mounts are left to the end of start-up.
        guard isLoaded else { return }
        mountRefresh?.cancel()
        let current = drives
        mountRefresh = Task {
            let now = await Task.detached(priority: .userInitiated) { DriveLocator.locate(current) }.value
            guard !Task.isCancelled else { return }
            applyMounts(now)
        }
    }

    /// Takes in which drives are connected; every drive that just appeared (including the ones
    /// connected when Reel opens) is scanned.
    func applyMounts(_ now: [String: URL]) {
        // Drives removed while the check was running are ignored.
        let now = now.filter { entry in drives.contains { $0.id == entry.key } }
        let newlyMounted = Set(now.keys).subtracting(mounted.keys)
        if now != mounted {
            mounted = now
            rebuild()
        }
        for i in drives.indices {
            if let url = now[drives[i].id], drives[i].lastKnownPath != url.path {
                drives[i].lastKnownPath = url.path
                scheduleSave(.settings)
            }
        }
        for drive in drives where newlyMounted.contains(drive.id) {
            Task { await scan(drive) }
        }
    }

    func rescanAll() async {
        mutateFilms { list in
            for i in list.indices where list[i].matchState == .failed { list[i].matchState = .pending }
        }
        let current = drives
        applyMounts(await Task.detached(priority: .userInitiated) { DriveLocator.locate(current) }.value)
        for drive in drives where mounted[drive.id] != nil {
            await scan(drive)
        }
        await lookUpPending()
    }

    /// Reads the drive's folder listing (names, sizes, dates only) and updates the library.
    /// - Parameter announcing: says how many films are new when done (not after a regrouping).
    func scan(_ drive: Drive, announcing: Bool = true) async {
        guard isLoaded, let url = mounted[drive.id], !scanning.contains(drive.id) else { return }
        scanning.insert(drive.id)
        defer { scanning.remove(drive.id) }

        let name = drive.name
        let id = drive.id
        reading[id] = "Reading \(name)…"
        // The folder listing reports how many files it has read so far.
        let counted: @Sendable (Int) -> Void = { [weak self] files in
            Task { @MainActor in
                guard let self, self.reading[id] != nil else { return }
                self.reading[id] = "Reading \(name)… \(files.formatted()) files"
            }
        }
        let fixes = groupingFixes
        let (found, stillThere) = await measure("Scan", label: "Reading \(name)") {
            await Task.detached(priority: .userInitiated) {
                (DriveScanner.scan(root: url, fixes: fixes, progress: counted), DriveLocator.isFolder(url))
            }.value
        }
        reading[id] = nil

        // Ejected or removed from Reel during the scan: the list may be incomplete, so don't use it.
        guard stillThere, let index = drives.firstIndex(where: { $0.id == drive.id }), mounted[drive.id] != nil else { return }
        let known = films.filter { $0.driveID == drive.id }
        if found.isEmpty && !known.isEmpty {
            notice = "Reel couldn't see any films on \(drive.name) just now, so nothing was changed. If macOS asked for permission, allow it and press ⌘R."
            return
        }

        let now = Date()
        // A drive Reel knows nothing about yet (new, or Library.json was lost) starts counting
        // arrivals after this scan, so its films don't all show up as new.
        let firstScan = drives[index].arrivalsSince == nil || known.isEmpty
        if firstScan { drives[index].arrivalsSince = now }
        drives[index].lastScanned = now
        scheduleSave(.settings)

        // Files that appear because of a regrouping by hand aren't arrivals: they're dated back.
        let stamp = announcing ? now : (drives[index].arrivalsSince ?? now)
        setFilms(LibraryMerge.apply(scan: found, driveID: drive.id, to: films, now: stamp))
        // Regrouping by hand is a rescan too, but nothing arrived.
        if announcing {
            // New entries are the ones stamped with this scan's time (moved files keep theirs).
            let added = films.filter { $0.driveID == drive.id && $0.addedAt == now }.count
            if firstScan {
                announce(added == 1 ? "Found 1 film on \(drive.name)" : "Found \(added) films on \(drive.name)")
            } else if added > 0 {
                announce(added == 1 ? "1 new film on \(drive.name)" : "\(added) new films on \(drive.name)")
            }
        }
        await lookUpPending()
    }

    // MARK: - Backup

    /// When the Backup was last read (the oldest, with several), for "last scanned 12 days ago".
    var lastBackupScan: Date? {
        backupDrives.compactMap { $0.lastScanned }.min()
    }

    // MARK: - Grouping fixes

    /// Whether the user regrouped this file by hand (offers "Undo Regrouping").
    func isRegrouped(_ path: String) -> Bool {
        groupingFixes.isFixed(path)
    }

    /// "This is an extra of …": the file is folded into another film on the next scan (done now).
    func makeExtra(_ film: FilmEntry, of owner: FilmEntry) {
        groupingFixes.makeExtra(film.relativePath, of: owner.relativePath)
        applyGroupingFixes()
    }

    /// "This is a film": an extra becomes a film of its own.
    func makeFilm(_ extra: FilmExtra) {
        groupingFixes.makeFilm(extra.relativePath)
        applyGroupingFixes()
    }

    func resetGrouping(_ path: String) {
        groupingFixes.reset(path)
        applyGroupingFixes()
    }

    private func applyGroupingFixes() {
        warnIfNotesReadOnly()
        scheduleSave(.notes)
        let connected = drives.filter { mounted[$0.id] != nil }
        if connected.isEmpty {
            notice = "The change is saved and will show the next time the drive is connected."
            return
        }
        Task {
            for drive in connected { await scan(drive, announcing: false) }
        }
    }
}
#endif
