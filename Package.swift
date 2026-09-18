// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "flow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "flow",
            path: "Sources/flow",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
