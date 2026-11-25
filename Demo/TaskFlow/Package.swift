// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TaskFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TaskFlowCore", path: "Sources/TaskFlowCore"),
        .executableTarget(name: "TaskFlow", dependencies: ["TaskFlowCore"], path: "Sources/TaskFlow"),
        .testTarget(name: "TaskFlowCoreTests", dependencies: ["TaskFlowCore"], path: "Tests/TaskFlowCoreTests"),
    ]
)
