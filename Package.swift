// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Purser",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Purser",
            path: "Sources/Purser"
        ),
        .testTarget(
            name: "PurserTests",
            dependencies: ["Purser"],
            path: "Tests/PurserTests"
        ),
    ]
)
