// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MusicAnalysis",
    // MusicUnderstanding and Core AI ship with the 27-era SDKs and there is
    // no fallback, so everything that touches them is
    // `@available(macOS 27, …)`. The 26 floors only let a tool that links
    // this still run there (vid analyze skips beats on 26).
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
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
