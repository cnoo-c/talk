// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FnVoiceInput",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FnVoiceInput", targets: ["FnVoiceInput"])
    ],
    targets: [
        .executableTarget(
            name: "FnVoiceInput",
            path: "Sources/FnVoiceInput"
        )
    ]
)
