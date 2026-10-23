// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BetterDisplayClone",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "BetterDisplayClone",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "BetterDisplayCloneTests",
            dependencies: ["BetterDisplayClone"]
        ),
    ]
)
