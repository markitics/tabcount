// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "tabcount",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "tabcount", targets: ["TabCount"]),
    ],
    targets: [
        .target(name: "TabCountCore"),
        .executableTarget(
            name: "TabCount",
            dependencies: ["TabCountCore"]
        ),
    ]
)
