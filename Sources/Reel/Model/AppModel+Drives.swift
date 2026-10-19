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

    /// How much room is left on each connected drive (read from the volume, nothing written).
    func readFreeSpace() {
        var result: [String: Int64] = [:]
        for (id, url) in mounted {
            if let free = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity {
                result[id] = Int64(free)
            }
        }
        if result != freeSpace { freeSpace = result }
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
        for id in newlyMounted { mountCount[id, default: 0] += 1 }
        if now != mounted {
            mounted = now
            rebuild()
            readFreeSpace()
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

    /// Reads the drive's folder listing (names, sizes, dates only) and updates the library. Only a
    /// scan that read the whole drive while it stayed connected removes films (see `ScanVerdict`).
    /// - Parameter announcing: says how many films are new when done (not after a regrouping).
    func scan(_ drive: Drive, announcing: Bool = true) async {
        guard isLoaded, let url = mounted[drive.id] else { return }
        guard !scanning.contains(drive.id) else {
            // Already reading it: read it again afterwards, so what changed meanwhile isn't missed.
            rescanWanted[drive.id] = (rescanWanted[drive.id] ?? true) && announcing
            return
        }
        scanning.insert(drive.id)
        var ended = false
        defer { if !ended { endScan(drive.id) } }

        let name = drive.name
        let id = drive.id
        let connection = mountCount[id]
        reading[id] = "Reading \(name)…"
        // The folder listing reports how many files it has read so far.
        let counted: @Sendable (Int) -> Void = { [weak self] files in
            Task { @MainActor in
                guard let self, self.reading[id] != nil else { return }
                self.reading[id] = "Reading \(name)… \(files.formatted()) files"
            }
        }
        let fixes = groupingFixes
        let (result, folderThere) = await measure("Scan", label: "Reading \(name)") {
            // Cancelling this scan stops the listing too. The drive is checked off the main thread
            // as well: a drive that is going away can take a while to answer.
            let listing = Task.detached(priority: .userInitiated) {
                let scan = DriveScanner.scan(root: url, fixes: fixes, progress: counted, isCancelled: { Task.isCancelled })
                return (scan, DriveLocator.isFolder(url))
            }
            return await withTaskCancellationHandler { await listing.value } onCancel: { listing.cancel() }
        }
        reading[id] = nil

        // The same drive, at the same place, connected the whole time; and still in Reel.
        let stillThere = folderThere && mounted[id] == url && mountCount[id] == connection
            && drives.contains { $0.id == id }
        var verdict = ScanVerdict.of(Task.isCancelled ? DriveScan(files: [], cancelled: true) : result,
                                     driveID: id, known: films, driveStillThere: stillThere)
        // A removal you confirmed goes ahead on this complete read, if the films missing are ones you
        // confirmed. The answer is used once, whatever this read found.
        let confirmed = removalConfirmed.removeValue(forKey: id)
        var missing: Set<String> = []
        if case .confirmRemovals = verdict {
            missing = Set(LibraryMerge.unseen(scan: result.files, driveID: id, in: films).map(\.id))
            if let confirmed, missing.isSubset(of: confirmed) { verdict = .apply }
        }
        // A question about this drive is answered by this scan (asked again below if still true).
        if pendingRemoval?.driveID == id { pendingRemoval = nil }
        switch verdict {
        case .discard(.nothingSeen):
            notice = "Reel couldn't see any films on \(name) just now, so nothing was changed. If macOS asked for permission, allow it and press ⌘R."
            return
        case .discard:
            // Disconnected or stopped: the listing may be incomplete, so it isn't used.
            return
        case .keepUnseen(let unreadable):
            let first = unreadable.first.map { $0.isEmpty ? name : "“\($0)”" } ?? name
            let more = unreadable.count > 1 ? " and \(unreadable.count - 1) more" : ""
            notice = "Reel couldn't read \(first)\(more) on \(name), so no films were removed. Press ⌘R to try again."
        case .confirmRemovals(let count):
            pendingRemoval = PendingRemoval(driveID: id, driveName: name, count: count, films: missing)
        case .apply:
            break
        }
        guard let index = drives.firstIndex(where: { $0.id == id }) else { return }

        let now = Date()
        let known = films.filter { $0.driveID == id }
        // A drive Reel knows nothing about yet (new, or Library.json was lost) starts counting
        // arrivals after this scan, so its films don't all show up as new.
        let firstScan = drives[index].arrivalsSince == nil || known.isEmpty
        if firstScan { drives[index].arrivalsSince = now }
        // "Last read in full" (the Backup's checklist): only when it was.
        if verdict == .apply { drives[index].lastScanned = now }
        scheduleSave(.settings)
        readFreeSpace()

        // Files that appear because of a regrouping by hand aren't arrivals: they're dated back.
        let stamp = announcing ? now : (drives[index].arrivalsSince ?? now)
        let before = films.filter { $0.driveID == id }
        setFilms(LibraryMerge.apply(scan: result.files, driveID: id, to: films, now: stamp, keepingUnseen: verdict != .apply))
        // A file replaced in place by one of another size is still that film: its fix and notes follow.
        carryOver(LibraryMerge.resized(before: before, after: films.filter { $0.driveID == id }))
        // Files that just appeared may settle fixes and notes saved under a file name alone.
        upgradeFileIdentities()
        // Regrouping by hand is a rescan too, but nothing arrived.
        if announcing {
            // New entries are the ones stamped with this scan's time (moved files keep theirs).
            let added = films.filter { $0.driveID == id && $0.addedAt == now }.count
            if firstScan {
                announce(added == 1 ? "Found 1 film on \(name)" : "Found \(added) films on \(name)")
            } else if added > 0 {
                announce(added == 1 ? "1 new film on \(name)" : "\(added) new films on \(name)")
            }
        }
        // The drive is free for another read (a confirmed removal, ⌘R) while film info is looked up.
        ended = true
        endScan(id)
        await lookUpPending()
    }

    private func endScan(_ id: String) {
        scanning.remove(id)
        if let announcing = rescanWanted.removeValue(forKey: id), let again = drives.first(where: { $0.id == id }) {
            Task { await scan(again, announcing: announcing) }
        }
    }

    /// You confirmed that the films a scan didn't find are gone. The drive is read again, and that
    /// read removes them, as long as it's complete, the drive stays connected, and no more films
    /// are missing than you were asked about. Disconnected meanwhile: nothing happens.
    func confirmPendingRemoval(_ pending: PendingRemoval) {
        if pendingRemoval?.driveID == pending.driveID { pendingRemoval = nil }
        guard mounted[pending.driveID] != nil, let drive = drives.first(where: { $0.id == pending.driveID }) else { return }
        removalConfirmed[pending.driveID] = pending.films
        Task { await scan(drive, announcing: false) }
    }

    /// Fixes and notes saved under a file's old size move to its new one (see `LibraryMerge.resized`).
    func carryOver(_ moves: [(from: String, to: String)]) {
        guard !moves.isEmpty else { return }
        var changed = false
        for move in moves {
            if let fix = corrections[move.from], corrections[move.to] == nil {
                corrections[move.to] = fix
                // A copy elsewhere still at the old size keeps it too.
                if !films.contains(where: { $0.fileKey == move.from }) { corrections[move.from] = nil }
                changed = true
            }
            // Never into notes another file already has (two same-named files swapping sizes).
            let to = FileIdentity.unidentifiedPrefix + move.to
            if personal.records[to] == nil { migratePersonal(from: FileIdentity.unidentifiedPrefix + move.from, to: to) }
        }
        if changed { scheduleSave(.notes) }
    }

    /// You kept them: nothing is removed, and the next scan asks again if they're still missing.
    func keepPendingRemoval() {
        pendingRemoval = nil
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
