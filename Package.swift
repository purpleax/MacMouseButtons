// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacMouseButtons",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic and event synthesis: no UI, fully unit-testable.
        .target(name: "MacMouseButtonsCore"),
        // The menu bar app.
        .executableTarget(name: "MacMouseButtons", dependencies: ["MacMouseButtonsCore"]),
        // End-to-end check against a running copy of the app.
        .executableTarget(name: "macmousebuttons-check", dependencies: ["MacMouseButtonsCore"]),
        .testTarget(name: "MacMouseButtonsCoreTests", dependencies: ["MacMouseButtonsCore"]),
    ]
)
