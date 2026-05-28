// swift-tools-version: 6.2

import PackageDescription

// Standalone example package: a dynamic library that uses `@DyldInterpose`
// from FrameworkToolbox to swap two libc functions (`puts`, `printf`).
//
// This package only produces the dylib. A separate host package
// (`Examples/DyldInterposeDemoHost`) links against this dylib and runs the
// hook end-to-end. Splitting lib and host into two packages is required
// because SwiftPM treats same-package target-to-target dependencies as
// static linkage; only cross-package dependencies honor
// `.library(type: .dynamic)`.

let package = Package(
    name: "DyldInterposeDemoLib",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "DyldInterposeDemoLib",
            type: .dynamic,
            targets: ["DyldInterposeDemoLib"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "DyldInterposeDemoLib",
            dependencies: [
                .product(name: "SwiftStdlibToolbox", package: "FrameworkToolbox"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("Extern"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
