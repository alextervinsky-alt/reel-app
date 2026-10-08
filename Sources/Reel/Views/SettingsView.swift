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
            } header: {
                Text("Watching")
            } footer: {
                Text("Reviews and Behind the Film keep the story, twists and ending hidden until a film is marked watched (each can be shown anyway), and Reel plays the official teaser rather than the full trailer, since it shows less. Trailers are only ever the studio's own, and play inside Reel. IINA and VLC load subtitle files next to the film on their own, and start full screen when Play full screen is on (always in Cinema mode). The first time, macOS asks whether Reel may control VLC: that's what puts VLC in full screen.")
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
