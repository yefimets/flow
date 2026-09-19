// swift-tools-version:5.9
import PackageDescription

// whisper.cpp is built once by scripts/build-whisper.sh into Vendor/whisper (static libraries + headers).
let whisperLib = Context.packageDirectory + "/Vendor/whisper/lib"

let package = Package(
    name: "flow",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CWhisper",
            path: "Vendor/whisper",
            sources: ["src"],
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-L" + whisperLib]),
                .linkedLibrary("whisper"),
                .linkedLibrary("parakeet"),
                .linkedLibrary("ggml"),
                .linkedLibrary("ggml-metal"),
                .linkedLibrary("ggml-cpu"),
                .linkedLibrary("ggml-base"),
                .linkedLibrary("c++"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "flow",
            dependencies: ["CWhisper"],
            path: "Sources/flow",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
