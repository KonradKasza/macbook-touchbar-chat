// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TouchBarChat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TouchBarChatCore", targets: ["TouchBarChatCore"])
    ],
    targets: [
        .target(
            name: "TouchBarChatCore",
            path: "Sources/TouchBarChatCore"
        ),
        .testTarget(
            name: "TouchBarChatCoreTests",
            dependencies: ["TouchBarChatCore"],
            path: "Tests/TouchBarChatCoreTests"
        )
    ]
)
