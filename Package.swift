// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dawn",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Dawn", path: "Sources/Dawn")
    ]
)
