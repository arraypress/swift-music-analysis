// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MusicAnalysis",
    // MusicUnderstanding ships with the 27-era SDKs; there is no fallback
    // implementation, so the floor is honest rather than aspirational.
    platforms: [
        .macOS("27.0"),
        .iOS("27.0"),
        .tvOS("27.0"),
        .watchOS("27.0"),
        .visionOS("27.0")
    ],
    products: [
        .library(
            name: "MusicAnalysis",
            targets: ["MusicAnalysis"]
        ),
    ],
    targets: [
        .target(
            name: "MusicAnalysis"
        ),
        .testTarget(
            name: "MusicAnalysisTests",
            dependencies: ["MusicAnalysis"]
        ),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
