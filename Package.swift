// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalVoice",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LocalVoice", targets: ["LocalVoice"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "LocalVoice",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/LocalVoice",
            swiftSettings: [
                .unsafeFlags(["-enable-bare-slash-regex"]),
            ]
        ),
        .testTarget(
            name: "LocalVoiceTests",
            dependencies: ["LocalVoice"],
            path: "Tests"
        ),
    ]
)
