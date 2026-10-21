// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HostRuntime",
    platforms: [.macOS(.v12)],
    products: [.library(name: "HostRuntime", type: .static, targets: ["HostRuntime"])],
    dependencies: [.package(path: "../HostCompat")],
    targets: [
        .target(name: "HostRuntime", dependencies: [.product(name: "HostCompat", package: "HostCompat")]),
        .testTarget(name: "HostRuntimeTests", dependencies: ["HostRuntime"]),
    ]
)
