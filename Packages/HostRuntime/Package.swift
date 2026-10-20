// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HostRuntime",
    platforms: [.macOS(.v12)],
    products: [.library(name: "HostRuntime", type: .static, targets: ["HostRuntime"])],
    targets: [.target(name: "HostRuntime"), .testTarget(name: "HostRuntimeTests", dependencies: ["HostRuntime"])]
)
