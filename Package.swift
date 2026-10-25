// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PowerOut",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PowerOut",
            path: "Sources/PowerOut",
            linkerSettings: [.linkedFramework("IOBluetooth")]
        )
    ]
)
