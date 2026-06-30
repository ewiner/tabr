// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tabr",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/ejbills/mediaremote-adapter.git", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "Tabr",
            dependencies: [
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter"),
            ],
            path: "Sources/Tabr",
            linkerSettings: [
                // Leave room in the Mach-O header so build.sh can rewrite the
                // libMediaRemoteAdapter dependency into a (longer) framework path
                // without a relink. See the framework repackaging in build.sh.
                .unsafeFlags(["-Xlinker", "-headerpad_max_install_names"])
            ]
        )
    ]
)
