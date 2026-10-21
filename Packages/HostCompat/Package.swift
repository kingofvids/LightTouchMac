// swift-tools-version: 6.0
// HostCompat: Duration, ContinuousClock, SuspendingClock, Task.sleep(for:), NSLock.withLock and OSAllocatedUnfairLock arrived in macOS 13. These stand in for
// the subset Light Touch uses so the app can deploy to macOS 12. Named Host* so they never collide with (or get
// shadowed by) the standard library's; the sources use them by those names.
import PackageDescription

let package = Package(
    name: "HostCompat",
    platforms: [.macOS(.v12)],
    products: [.library(name: "HostCompat", type: .static, targets: ["HostCompat"])],
    targets: [
        .target(name: "HostCompat"),
        .testTarget(name: "HostCompatTests", dependencies: ["HostCompat"]),
    ],
    swiftLanguageModes: [.v5]
)
