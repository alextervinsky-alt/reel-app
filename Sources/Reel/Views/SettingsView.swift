#if os(macOS)
import SwiftUI
import ReelCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var token = ""
    @State private var checking = false
    @State private var tokenMessage: String?
    @State private var cacheSize: Int64?
    @State private var omdbKey = ""
    @State private var timings: [Timing] = []

    var body: some View {
        Form {
            Section("Film information") {
                LabeledContent("TMDB") {
                    Text(model.hasToken ? "Connected" : "Not connected")
                        .foregroundStyle(model.hasToken ? Color.green : Color.orange)
                }
                HStack {
                    SecureField(model.hasToken ? "Replace token" : "API Read Access Token", text: $token)
                    if checking { ProgressView().controlSize(.small) }
                    Button("Save") { saveToken() }
                        .disabled(token.isEmpty || checking)
                }
                if let tokenMessage {
                    Text(tokenMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Hide story details of films I haven't watched", isOn: Binding(
                    get: { model.spoilerSafe }, set: { model.setSpoilerSafe($0) }))
                Picker("Play films with", selection: Binding(get: { model.player }, set: { model.setPlayer($0) })) {
                    ForEach(PlayerChoice.allCases.filter { PlayerChoice.installed.contains($0) || $0 == model.player }) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                Toggle("Play full screen", isOn: Binding(get: { model.playFullScreen }, set: { model.setPlayFullScreen($0) }))
                if !model.notForMe.isEmpty {
                    LabeledContent("Not for me") {
                        HStack(spacing: 10) {
                            Text(model.notForMe.count == 1 ? "1 film" : "\(model.notForMe.count) films").foregroundStyle(.secondary)
                            Button("Suggest Them Again") { model.clearNotForMe() }
                        }
                    }
                }
            } header: {
                Text("Watching")
            } footer: {
                Text("Reviews and Behind the Film keep the story, twists and ending hidden until a film is marked watched (each can be shown anyway). Trailers are the studio's full trailer (a teaser only when there's no trailer), never a clip or a short promo, and play inside Reel. Films you mark Not for Me in For You or Explore aren't suggested again. IINA and VLC load subtitle files next to the film on their own, and start full screen when Play full screen is on (always in Cinema mode). The first time, macOS asks whether Reel may control VLC: that's what puts VLC in full screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Cinema mode", isOn: Binding(get: { model.cinemaMode }, set: { model.setCinemaMode($0) }))
            } header: {
                Text("On the TV")
            } footer: {
                Text("Full screen, large posters and big buttons for choosing from the sofa with the mouse. Also in the View menu and the sidebar (⇧⌘C). Films then open full screen in IINA or VLC.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("OMDb") {
                    Text(model.omdbKey.isEmpty ? "Not set" : "Set")
                        .foregroundStyle(model.omdbKey.isEmpty ? Color.orange : Color.green)
                }
                HStack {
                    SecureField(model.omdbKey.isEmpty ? "OMDb key" : "New OMDb key", text: $omdbKey)
                    Button("Save") {
                        model.setOMDbKey(omdbKey)
                        omdbKey = ""
                    }
                    .disabled(omdbKey.isEmpty)
                }
            } header: {
                Text("Ratings")
            } footer: {
                Text("IMDb, Rotten Tomatoes and Metacritic scores come from OMDb. Paste your free key from omdbapi.com once; it's kept only in Documents › Reel › Settings.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if model.drives.isEmpty {
                    Text("No drives yet.").foregroundStyle(.secondary)
                }
                ForEach(model.drives) { drive in
                    HStack {
                        Image(systemName: model.mounted[drive.id] != nil ? "externaldrive.fill" : "externaldrive")
                            .foregroundStyle(model.mounted[drive.id] != nil ? Color.green : Color.secondary)
                        TextField("Name", text: Binding(
                            get: { drive.name },
                            set: { model.renameDrive(drive.id, to: $0) }
                        ))
                        .textFieldStyle(.plain)
                        Spacer()
                        Text(drive.lastKnownPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Picker("Role", selection: Binding(get: { drive.isBackup }, set: { model.setBackup(drive.id, $0) })) {
                            Text("Main").tag(false)
                            Text("Backup").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                Button("Add Drive…") { model.chooseDrive() }
            } header: {
                Text("Drives")
            } footer: {
                Text("Main is where you add films. Backup is a copy of it: Reel plays from the main drive when both are connected, and lists films missing from the Backup (or only half copied) under Not on Backup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Location") {
                    Button("Documents › Reel") { model.showReelFolder() }
                        .buttonStyle(.link)
                }
                LabeledContent("Image cache") {
                    HStack {
                        Text(cacheSize.map { Format.bytes($0) } ?? "…")
                            .foregroundStyle(.secondary)
                        Button("Clear") {
                            model.clearImageCache()
                            cacheSize = 0
                        }
                    }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Your notes, library and posters stay in one folder. The image cache is limited to 400 MB and skips iCloud and Time Machine. Reel never writes to your film drives.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(model.pictureCounts(), id: \.basis.title) { count in
                    LabeledContent(count.basis.title) {
                        Text(count.files.formatted()).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("HDR or SDR")
            } footer: {
                Text("How Reel knows whether to turn on HDR on your Mac for each file, from its name: what the name says, what the file is (a 1080p Blu-ray or an H.264 file can't be HDR), or what the kind of release makes likely, which the tag says as “Likely”. You can set any file in the film's … menu › Picture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                let coverage = model.craftCoverage()
                LabeledContent("Live-action films with Shot on") {
                    Text("\(coverage.tagged) of \(coverage.read)").monospacedDigit().foregroundStyle(.secondary)
                }
                LabeledContent("Read from one text alone (usually Wikipedia)") {
                    Text(coverage.articleOnly.formatted()).monospacedDigit().foregroundStyle(.secondary)
                }
                if coverage.waiting > 0 {
                    LabeledContent("Still to read") {
                        Text(coverage.waiting.formatted()).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Shot On")
            } footer: {
                Text("A film gets Shot on only when something Reel reads says how it was shot: its Wikipedia article, American Cinematographer, British Cinematographer, Kodak, No Film School or an article Wikipedia cites. For many films none of them does. Animated films aren't counted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !model.removedShotOn.isEmpty {
                Section {
                    ForEach(model.removedShotOn.sorted { $0.key < $1.key }, id: \.key) { id, kinds in
                        let title = model.films.first { $0.tmdb?.id == id }?.displayTitle ?? "A film no longer in the library"
                        ForEach(kinds.sorted { $0.rawValue < $1.rawValue }, id: \.self) { kind in
                            LabeledContent(title) {
                                HStack(spacing: 10) {
                                    Text(kind.title).foregroundStyle(.secondary)
                                    Button("Put Back") { model.restoreShotOn(kind, for: id) }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Shot On You Removed")
                } footer: {
                    Text("Tags you said were wrong (right-click Shot on on a film's page). They aren't shown, filtered or searched for that film.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !model.craftChanges.isEmpty {
                Section {
                    ForEach(model.craftChanges.prefix(40)) { change in
                        LabeledContent(change.title) {
                            Text(Self.shotOn(change.before) + "  →  " + Self.shotOn(change.after)).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Shot On, Read Again")
                } footer: {
                    Text("Films whose Shot on changed when Reel read about them again, since it opened. Point at Shot on on a film's page to see the sentence behind it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !timings.isEmpty {
                Section {
                    ForEach(timings) { timing in
                        LabeledContent(timing.id) {
                            Text(Self.format(timing.time)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Performance")
                } footer: {
                    Text("How long the last of each took, since Reel opened.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        // A fixed height that fits a laptop screen; the form scrolls (it used to grow to fit everything).
        .frame(width: 560, height: 580)
        .task {
            timings = model.timings.map { Timing(id: $0.key, time: $0.value) }.sorted { $0.id < $1.id }
            cacheSize = await model.imageCacheSize()
        }
    }

    private struct Timing: Identifiable {
        let id: String
        let time: Duration
    }

    /// "Film · Anamorphic", or "nothing".
    private static func shotOn(_ kinds: [ShotOn]) -> String {
        kinds.isEmpty ? "nothing" : kinds.map(\.title).joined(separator: " · ")
    }

    /// "0.42 s", "12 ms"
    private static func format(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return seconds < 1 ? "\(Int((seconds * 1000).rounded())) ms" : String(format: "%.2f s", seconds)
    }

    private func saveToken() {
        checking = true
        tokenMessage = nil
        let candidate = token
        Task {
            if let problem = await model.connect(token: candidate) {
                tokenMessage = problem
            } else {
                tokenMessage = "Saved and working."
                token = ""
            }
            checking = false
        }
    }
}
#endif
