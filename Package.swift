// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FrameworkToolbox",
    platforms: [.iOS(.v11), .macOS(.v10_13), .watchOS(.v4), .tvOS(.v11), .macCatalyst(.v13)],
    products: [
        .library(
            name: "FrameworkToolbox",
            targets: ["FrameworkToolbox"]
        ),
        .library(
            name: "SwiftStdlibToolbox",
            targets: ["SwiftStdlibToolbox"]
        ),
        .library(
            name: "FoundationToolbox",
            targets: ["FoundationToolbox"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "FrameworkToolbox",
            dependencies: []),
        .target(
            name: "SwiftStdlibToolbox",
            dependencies: ["FrameworkToolbox"]
        ),
        .target(
            name: "FoundationToolbox",
            dependencies: ["FrameworkToolbox"]
        ),
        .testTarget(
            name: "FrameworkToolboxTests",
            dependencies: ["FrameworkToolbox"]
        ),
    ]
)
