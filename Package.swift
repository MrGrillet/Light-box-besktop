// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "LightBoxDesktop",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "LightBoxDesktop",
            targets: ["LightBoxDesktop"]),
    ],
    dependencies: [
        .package(
            name: "WebRTC",
            url: "https://github.com/stasel/WebRTC.git",
            .upToNextMajor(from: "111.0.0")
        )
    ],
    targets: [
        .target(
            name: "LightBoxDesktop",
            dependencies: ["WebRTC"]),
        .testTarget(
            name: "LightBoxDesktopTests",
            dependencies: ["LightBoxDesktop"]),
    ]
) 