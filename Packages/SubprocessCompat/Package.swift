// swift-tools-version: 6.0
// SubprocessCompat: the slice of swift-subprocess 1.0 that Light Touch uses, on Foundation.Process, so the app can
// deploy to macOS 12 (swift-subprocess itself needs macOS 13). The module is named `Subprocess` on purpose: call
// sites keep `import Subprocess` and `Subprocess.run(...)` unchanged. Only the subset the app calls is implemented.
import PackageDescription

let package = Package(
    name: "SubprocessCompat",
    platforms: [.macOS(.v12)],
    products: [.library(name: "Subprocess", targets: ["Subprocess"])],
    targets: [
        .target(name: "Subprocess")
    ],
    // Plain Swift 5 mode: this is a thin Foundation wrapper and its Process/FileHandle plumbing is not Sendable-clean.
    swiftLanguageModes: [.v5]
)
