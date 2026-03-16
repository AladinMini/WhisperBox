// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperBox",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WhisperBox", targets: ["WhisperBox"])
    ],
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "WhisperBox",
            dependencies: ["SwiftWhisper"],
            path: "Sources/WhisperBox",
            resources: [
                .copy("../../Resources/Info.plist")
            ]
        )
    ]
)
