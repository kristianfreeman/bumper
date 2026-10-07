// swift-tools-version: 6.4
import PackageDescription

// Module graph (arrows = depends on):
//
//   AppFeatures ──► DesignSystem ──► AppCore ──► JellyfinAPI ──► Instrumentation
//        │                              ▲
//        ├──► VLCPlayback ──► PlaybackCore ┘   (PlaybackCore: AVPlayer backend + routing)
//        │         └──► VLCKit (Vendor/VLCKit.xcframework, fetched by scripts/fetch-vlckit.sh)
//        └──► JellyfinMocks (fixture server for UI / perf tests)
//
// Module names are deliberately brand-free. The user-facing product name lives
// in exactly one place: `Brand` (AppCore/Brand.swift), fed by the
// APP_DISPLAY_NAME build setting in project.yml.
//
// Baseline: Swift 6.4, Jellyfin 10.11+, tvOS 26+ (so the 2017 Apple TV 4K,
// which stops at tvOS 26, is supported). tvOS 27 APIs are used wherever
// available behind `#available`, with a tvOS 26 fallback only where needed.
//
// Everything below DesignSystem is platform-neutral so its tests run on macOS
// with plain `swift test` in seconds.

/// Every upcoming language feature the 6.4 toolchain offers that isn't already
/// on by default in Swift 6 mode.
let modernSwift: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
]

/// Non-UI modules additionally opt into strict memory safety: any `unsafe`
/// construct must be spelled out.
let safeSwift = modernSwift + [.strictMemorySafety()]

/// UI modules default to main-actor isolation (Swift 6.2+ "approachable
/// concurrency"): view code is main-actor unless it says otherwise.
let uiSwift = modernSwift + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "JellyfinAppKit",
    platforms: [.tvOS("26.0"), .iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "AppFeatures", targets: ["AppFeatures"]),
        // The iPhone companion's link to the TV (and the TV's to it).
        .library(name: "Companion", targets: ["Companion"]),
        // What the Top Shelf extension reads (Foundation only: extensions are small).
        .library(name: "TopShelf", targets: ["TopShelf"]),
    ],
    targets: [
        .target(name: "Instrumentation", swiftSettings: safeSwift),
        .target(name: "TopShelf", swiftSettings: safeSwift),
        .target(name: "JellyfinAPI", dependencies: ["Instrumentation"], swiftSettings: safeSwift),
        .target(name: "AppCore", dependencies: ["JellyfinAPI", "Instrumentation"], swiftSettings: safeSwift),
        .target(name: "PlaybackCore", dependencies: ["JellyfinAPI", "AppCore", "Instrumentation"], swiftSettings: safeSwift),
        // VideoLAN's official VLCKit 4 build, pinned by checksum (see
        // scripts/fetch-vlckit.sh). Local path so Xcode and `swift test` share
        // one ~900 MB copy instead of each caching a download.
        .binaryTarget(name: "VLCKit", path: "../../Vendor/VLCKit.xcframework"),
        .target(
            name: "VLCPlayback",
            dependencies: ["PlaybackCore", "JellyfinAPI", "AppCore", "Instrumentation", .target(name: "VLCKit", condition: .when(platforms: [.tvOS, .iOS, .macOS]))],
            swiftSettings: modernSwift
        ),
        .target(name: "JellyfinMocks", dependencies: ["JellyfinAPI"], swiftSettings: safeSwift),
        .target(name: "Companion", swiftSettings: modernSwift),
        // `swift run mock-media-server <dir>`: serves test clips to a real Apple TV over the LAN.
        .executableTarget(name: "mock-media-server", dependencies: ["JellyfinMocks"], path: "Sources/MockMediaServer", swiftSettings: modernSwift),
        .target(name: "DesignSystem", dependencies: ["AppCore", "JellyfinAPI", "Instrumentation"], swiftSettings: uiSwift),
        .target(
            name: "AppFeatures",
            dependencies: ["DesignSystem", "AppCore", "PlaybackCore", "VLCPlayback", "JellyfinAPI", "JellyfinMocks", "Instrumentation", "Companion", "TopShelf"],
            swiftSettings: uiSwift
        ),

        // Swift Testing throughout (no XCTest outside of UI tests).
        .testTarget(name: "JellyfinAPITests", dependencies: ["JellyfinAPI", "JellyfinMocks"], swiftSettings: modernSwift),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore", "JellyfinMocks"], swiftSettings: modernSwift),
        .testTarget(name: "PlaybackCoreTests", dependencies: ["PlaybackCore"], swiftSettings: modernSwift),
        .testTarget(name: "InstrumentationTests", dependencies: ["Instrumentation"], swiftSettings: modernSwift),
        .testTarget(name: "CompanionTests", dependencies: ["Companion"], swiftSettings: modernSwift),
        .testTarget(name: "TopShelfTests", dependencies: ["TopShelf"], swiftSettings: modernSwift),
        .testTarget(name: "AppFeaturesTests", dependencies: ["AppFeatures", "AppCore", "PlaybackCore", "JellyfinAPI", "JellyfinMocks"], swiftSettings: uiSwift),
    ]
)
