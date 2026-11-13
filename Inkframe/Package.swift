// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Inkframe",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "Inkframe",
            dependencies: ["HotKey"],
            path: "Sources",
            resources: [
                .process("../Resources")
            ]
        ),
        .testTarget(
            name: "InkframeTests",
            dependencies: ["Inkframe"],
            path: "Tests"
        )
    ]
)
