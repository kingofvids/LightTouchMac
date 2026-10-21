// swift-tools-version: 6.2
// LightTouchCore: the app's logic that needs no window: the device library and catalog, device records and boot
// pieces, the install and media pipelines, capture naming, the session's state machines and the input and zoom
// math. The app links it; LightTouchCoreTests (Swift Testing) is the Unit test plan's suite. Built like the app:
// MainActor by default with approachable concurrency.
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "LightTouchCore",
    platforms: [.macOS(.v12)],
    products: [.library(name: "LightTouchCore", type: .static, targets: ["LightTouchCore"])],
    dependencies: [
        .package(path: "../HostRuntime"),
        .package(path: "../FirmwareKit"),
        .package(path: "../DeviceServices"),
        .package(path: "../DeviceRuntime"),
        .package(path: "../SubprocessCompat"),
        .package(path: "../HostCompat"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
        // Backports @Observable to macOS 12 and 13 (Observation needs 14). On 14+ it forwards to Observation.
        .package(url: "https://github.com/pointfreeco/swift-perception.git", exact: "2.0.9"),
    ],
    targets: [
        .target(
            name: "LightTouchCore",
            dependencies: [
                .product(name: "HostRuntime", package: "HostRuntime"),
                .product(name: "FirmwareSchema", package: "FirmwareKit"),
                .product(name: "HostServiceWire", package: "DeviceServices"),
                .product(name: "HostServiceClient", package: "DeviceServices"),
                .product(name: "DeviceRuntime", package: "DeviceRuntime"),
                .product(name: "Subprocess", package: "SubprocessCompat"),
                .product(name: "HostCompat", package: "HostCompat"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "Perception", package: "swift-perception"),
            ],
            swiftSettings: settings
        ),
        // Gives each test process a private home and app state before any test runs.
        .target(name: "TestIsolation", path: "Tests/TestIsolation"),
        // The tests stay in the Swift 5 language mode for now (their fixtures share state across threads by design).
        .testTarget(
            name: "LightTouchCoreTests",
            dependencies: ["LightTouchCore", "TestIsolation"],
            swiftSettings: settings + [.swiftLanguageMode(.v5)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
