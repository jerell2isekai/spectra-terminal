// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spectra",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // System library target wrapping libghostty
        .systemLibrary(
            name: "GhosttyKit",
            path: "Sources/GhosttyKit",
            pkgConfig: nil,
            providers: []
        ),
        // Main executable
        .executableTarget(
            name: "Spectra",
            dependencies: ["GhosttyKit"],
            path: "Sources/Spectra",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                // libghostty static library (built by scripts/build-ghostty.sh)
                .unsafeFlags(["-L../lib"]),
                .linkedLibrary("ghostty"),
            ]
        ),
    ]
)
