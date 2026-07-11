// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BrightnessController",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "DDCKit", targets: ["DDCKit"]),
        .executable(name: "BrightnessBar", targets: ["BrightnessBar"]),
    ],
    targets: [
        .target(
            name: "DDCKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "BrightnessBar",
            dependencies: ["DDCKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
