// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SystemMonitor",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SystemMonitor",
            targets: ["SystemMonitor"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SystemMonitor",
            dependencies: [],
            path: "SystemMonitor",
            exclude: [
                // Handled by Xcode project; exclude to silence SPM warnings
                "Info.plist",
                "SystemMonitor.entitlements",
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
