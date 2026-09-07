// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Catoshi",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Catoshi", targets: ["Catoshi"])
    ],
    targets: [
        .executableTarget(
            name: "Catoshi",
            path: "Sources/Catoshi"
        ),
        .testTarget(name: "CatoshiTests", dependencies: ["Catoshi"], path: "Tests/CatoshiTests")
    ]
)
