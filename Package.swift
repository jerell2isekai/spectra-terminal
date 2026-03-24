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
            resources: [
                .copy("Resources/AppIcon.icns"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Security"),
                // libghostty static library (built by scripts/build-ghostty.sh)
                // Uses Context.packageDirectory for reliable path resolution in SPM build sandbox
                .unsafeFlags(["-L\(Context.packageDirectory)/lib"]),
                .linkedLibrary("ghostty"),
                // libghostty includes C++ dependencies (SPIRV-Cross, glslang)
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
