// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bayleaf",
    // macOS 26 (Tahoe): FoundationModels (on-device Apple Intelligence) is the whole
    // point of the Ask feature, and it does not exist before Tahoe. The machine it runs
    // on must be Apple Silicon on macOS 26+ — see SPEC.md for the back-deployment option.
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Bayleaf",
            path: "Sources/Bayleaf",
            // Swift 5 mode, same reasoning as ClawBar: AppKit/AVAudioEngine plumbing
            // fights strict concurrency for no safety gain in an app this size. The
            // model layer is @MainActor-annotated throughout regardless.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
