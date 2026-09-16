// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MegaBoomBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MegaBoomBar",
            path: "Sources/MegaBoomBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOBluetooth")
            ]
        )
    ]
)
