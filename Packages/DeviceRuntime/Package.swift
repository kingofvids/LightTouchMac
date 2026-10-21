// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeviceRuntime",
    platforms: [.macOS(.v12)],
    products: [.library(name: "DeviceRuntime", type: .static, targets: ["DeviceRuntime"])],
    dependencies: [.package(path: "../HostRuntime"), .package(path: "../HostCompat")],
    targets: [
        .target(name: "LTMLinkC", publicHeadersPath: "."),
        .target(name: "DeviceRuntime", dependencies: ["HostRuntime", "LTMLinkC", .product(name: "HostCompat", package: "HostCompat")]),
        .executableTarget(name: "RendezvousTestPeer", dependencies: ["LTMLinkC"]),
        .testTarget(name: "DeviceRuntimeTests", dependencies: ["DeviceRuntime", "RendezvousTestPeer"]),
    ]
)
