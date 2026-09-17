// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BoomBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "BoomBar",
            path: "Sources/BoomBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOBluetooth")
            ]
        )
    ]
)
