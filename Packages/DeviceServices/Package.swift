// swift-tools-version: 6.0
// One device's host services (installation_proxy, AFC, springboardservices, notification_proxy, lockdown reads).
// HostServiceWire: what the app and the services helper share (the typed request/event protocol, errors, paths).
// HostServiceClient: the app's side, which runs every operation in a LightTouchServices process per endpoint.
// The engine that calls libimobiledevice is the LightTouchServices target's own (LightTouchServices/Engine): it
// links the vendored C library, which a package can't see.
import PackageDescription

let package = Package(
    name: "DeviceServices",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "HostServiceWire", type: .static, targets: ["HostServiceWire"]),
        .library(name: "HostServiceClient", type: .static, targets: ["HostServiceClient"]),
    ],
    dependencies: [.package(path: "../SubprocessCompat"), .package(path: "../HostCompat")],
    targets: [
        .target(name: "HostServiceWire", dependencies: [.product(name: "HostCompat", package: "HostCompat")]),
        .target(
            name: "HostServiceClient",
            dependencies: [
                "HostServiceWire",
                .product(name: "Subprocess", package: "SubprocessCompat"),
                .product(name: "HostCompat", package: "HostCompat"),
            ]
        ),
        .testTarget(name: "HostServiceWireTests", dependencies: ["HostServiceWire"]),
    ]
)
