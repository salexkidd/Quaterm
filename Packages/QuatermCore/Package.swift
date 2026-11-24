// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuatermCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuatermCore", targets: ["QuatermCore"])
    ],
    targets: [
        .target(name: "QuatermCore"),
        .testTarget(name: "QuatermCoreTests", dependencies: ["QuatermCore"]),
    ]
)
