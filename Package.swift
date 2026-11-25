// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DevHub",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DevHub", targets: ["DevHub"]),
    ],
    targets: [
        // All logic, no UI — unit-testable.
        .target(
            name: "DevHubCore",
            path: "Sources/DevHubCore"
        ),
        // SwiftUI menu bar app.
        .executableTarget(
            name: "DevHub",
            dependencies: ["DevHubCore"],
            path: "Sources/DevHub"
        ),
        .testTarget(
            name: "DevHubCoreTests",
            dependencies: ["DevHubCore"],
            path: "Tests/DevHubCoreTests"
        ),
    ]
)
