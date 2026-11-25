// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShopDemo",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ShopCore", path: "Sources/ShopCore"),
        .executableTarget(name: "Shop", dependencies: ["ShopCore"], path: "Sources/Shop"),
        .testTarget(name: "ShopCoreTests", dependencies: ["ShopCore"], path: "Tests/ShopCoreTests"),
    ]
)
