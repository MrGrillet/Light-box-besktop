// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "NetworkTypes",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "NetworkTypes",
            targets: ["NetworkTypes"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NetworkTypes",
            dependencies: []),
    ]
) 