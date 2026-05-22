// swift-tools-version: 5.9
//
// open-computer-use (ocu)
// macOS computer use via Accessibility API + CGEvent, exposed as both an MCP
// stdio server and a CLI. https://github.com/nogu66/open-computer-use
//
import PackageDescription

let package = Package(
    name: "OpenComputerUse",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ocu", targets: ["ocu"]),
        .library(name: "OCUCore", targets: ["OCUCore"])
    ],
    targets: [
        .target(
            name: "OCUCore",
            path: "Sources/OCUCore"
        ),
        .executableTarget(
            name: "ocu",
            dependencies: ["OCUCore"],
            path: "Sources/ocu"
        ),
        .testTarget(
            name: "OCUCoreTests",
            dependencies: ["OCUCore"],
            path: "Tests/OCUCoreTests"
        )
    ]
)
