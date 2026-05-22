// swift-tools-version: 5.9
//
// open-computer-use (ocu)
// macOS computer use via Accessibility API + CGEvent, exposed as both an MCP
// stdio server and a CLI. https://github.com/nogu66/open-computer-use
//
import PackageDescription

var products: [Product] = [
    .library(name: "OCUCore", targets: ["OCUCore"])
]

var targets: [Target] = [
    .target(
        name: "OCUCore",
        path: "Sources/OCUCore"
    ),
    .testTarget(
        name: "OCUCoreTests",
        dependencies: ["OCUCore"],
        path: "Tests/OCUCoreTests"
    )
]

#if os(macOS)
products.insert(.executable(name: "ocu", targets: ["ocu"]), at: 0)
targets.insert(
    .executableTarget(
        name: "ocu",
        dependencies: ["OCUCore"],
        path: "Sources/ocu"
    ),
    at: 1
)
#endif

let package = Package(
    name: "OpenComputerUse",
    platforms: [
        .macOS(.v13)
    ],
    products: products,
    targets: targets
)
