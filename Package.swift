// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Framelet",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Framelet", targets: ["Framelet"])],
    targets: [
        .target(name: "RecorderCore"),
        .executableTarget(name: "Framelet", dependencies: ["RecorderCore"]),
        .testTarget(name: "RecorderCoreTests", dependencies: ["RecorderCore"])
    ]
)