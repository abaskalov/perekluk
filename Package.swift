// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Perekluk",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Perekluk",
            path: "Sources/Perekluk",
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
