#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

@main
struct ReelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Reel", id: "library") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1240, height: 820)
        // No hidden "Saved Application State" folder; Reel opens fresh each time.
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Drive…") { model.chooseDrive() }
                    .keyboardShortcut("o")
                Button("Rescan Drives") { Task { await model.rescanAll() } }
                    .keyboardShortcut("r")
            }
            CommandGroup(before: .toolbar) {
                Toggle("Cinema Mode", isOn: Binding(get: { model.cinemaMode }, set: { model.setCinemaMode($0) }))
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}

/// Quit when the window closes, so Reel never lingers in the background.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#else
@main
struct ReelApp {
    static func main() {
        print("Reel is a Mac app. This stub only exists so the project also builds on Linux.")
    }
}
#endif
