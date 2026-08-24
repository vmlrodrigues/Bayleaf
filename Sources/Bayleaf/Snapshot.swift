import AppKit
import SwiftUI

// Renders the real UI (same views, same model) to PNGs, headless. Exists so a
// change can be eyeballed — or shown to someone — without launching the app.
@MainActor
enum Snapshot {
    static func capture(source: String, outDir: String) async {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let model = AppModel.shared
        model.snapshotMode = true

        write(render(), to: "\(outDir)/1-empty.png")

        model.load(url: URL(fileURLWithPath: source))
        model.generateAllThumbnails()
        write(render(), to: "\(outDir)/2-loaded.png")

        model.selection = [3, 4, 5, 9]
        model.askText = "grab 3 to 5 and page 9"
        write(render(), to: "\(outDir)/3-selection.png")

        print("snapshots written to \(outDir)")
    }

    private static func render() -> NSImage? {
        let content = MainView()
            .environmentObject(AppModel.shared)
            .frame(width: 1180, height: 760)
            .preferredColorScheme(.dark)
            // ImageRenderer doesn't resolve preferredColorScheme; force the
            // environment so .primary text renders white as it does in the window.
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.nsImage
    }

    private static func write(_ image: NSImage?, to path: String) {
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("warning: couldn't render \(path)\n".utf8))
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("  \(path)")
        } catch {
            FileHandle.standardError.write(Data("warning: \(error.localizedDescription)\n".utf8))
        }
    }
}
