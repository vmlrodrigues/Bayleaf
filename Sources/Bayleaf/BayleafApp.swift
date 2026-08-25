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

    /// Brand at the left, the app's two verbs at the right — Mud's shape.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 7) {
                LogoMark(size: 18)
                Text("Bayleaf")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
        }
        // macOS 26 wraps every toolbar item in a Liquid Glass capsule, sized for a
        // standard control — a custom icon+label stack spills out of it. The brand is
        // a label, not a control, so it gets no background at all, which is what Mud's
        // title does too. The buttons below keep theirs, because they ARE controls.
        .sharedBackgroundVisibility(.hidden)
        // With the window title hidden there is no flexible gap in the middle of
        // the toolbar, so .primaryAction items sit next to the brand instead of at
        // the trailing edge. An explicit flexible spacer restores the split.
        ToolbarSpacer(.flexible)
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.openPanel() } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help("Open a PDF (⌘O)")

            Button { model.extract() } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help(model.selection.isEmpty
                  ? "Pick some pages first"
                  : "Extract \(model.selection.count) page\(model.selection.count == 1 ? "" : "s") (⌘E)")
            .disabled(model.selection.isEmpty)
        }
    }

    var body: some Scene {
        Window("Bayleaf", id: "main") {
            MainView()
                .environmentObject(model)
                // Bayleaf has one look, designed dark. System-theme support is a
                // spec'd follow-up, not an accident — see SPEC.md.
                .preferredColorScheme(.dark)
                .toolbar { toolbarContent }
        }
        // A real unified toolbar, the same thing Mud does with
        // `window.toolbarStyle = .unified`. This matters: with .hiddenTitleBar the
        // window still reserves the traffic-light strip as safe area, so a
        // hand-rolled header row lands *underneath* it and the chrome ends up two
        // rows tall (~53pt). A toolbar puts the brand and the buttons on the SAME
        // row as the traffic lights — one row, ~38pt, like every other Mac app.
        .windowToolbarStyle(.unified(showsTitle: false))
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
                Divider()
                // Dictation is a menu command purely so its shortcut is rebindable:
                // macOS lets anyone remap a menu item in System Settings > Keyboard >
                // Keyboard Shortcuts > App Shortcuts, matching on the item's exact
                // title. That is a whole settings screen this app never has to build —
                // and the reason this title must stay FIXED. If it toggled between
                // "Start"/"Stop", a custom binding would only ever match one of them.
                Button("Dictate") { AppModel.shared.toggleDictation() }
                    .keyboardShortcut("d", modifiers: .command)
            }
        }
    }
}
