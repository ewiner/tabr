// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tabr",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ejbills/mediaremote-adapter.git", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "Tabr",
            dependencies: [
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter"),
            ],
            path: "Sources/Tabr"
        )
    ]
)
