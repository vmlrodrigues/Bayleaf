import AppKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Finder "Open With", or dropping a PDF on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { AppModel.shared.load(url: url) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct BayleafApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    // Sparkle. Constructed once with the App and starts its scheduled checker.
    // Headless CLI runs never construct BayleafApp, so the updater stays inert there.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        Window("Bayleaf", id: "main") {
            MainView()
                .environmentObject(model)
                // Bayleaf has one look, designed dark. System-theme support is a
                // spec'd follow-up, not an accident — see SPEC.md.
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updaterController.checkForUpdates(nil) }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…") { AppModel.shared.openPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Extract Pages") { AppModel.shared.extract() }
                    .keyboardShortcut("e", modifiers: .command)
                Button("Select All Pages") { AppModel.shared.selectAll() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Clear Selection") { AppModel.shared.selectNone() }
            }
        }
    }
}
