// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tabr",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Tabr",
            path: "Sources/Tabr",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/System/Library/PrivateFrameworks"])
            ]
        )
    ]
)
