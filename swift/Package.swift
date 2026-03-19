// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Flecs",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "Flecs",
            targets: ["Flecs"])
    ],
    targets: [
        .target(
            name: "Flecs",
            path: "Sources/Flecs"),
        .testTarget(
            name: "FlecsTests",
            dependencies: ["Flecs"],
            path: "Tests/FlecsTests")
    ]
)
