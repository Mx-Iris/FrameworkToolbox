// swift-tools-version: 6.2

import PackageDescription

// Standalone example package: a single executable that hooks two libc
// functions with `@DyldDynamicInterpose`, applies the hooks partway through
// `main`, then takes them back.
//
// Note what is *not* here: a dynamic library. The static `@DyldInterpose`
// demo needs one, because dyld only honors `__DATA,__interpose` in a dylib —
// which is why that demo is split across `DyldInterposeDemoLib` and
// `DyldInterposeDemoHost`. Dynamic interposing is applied by the program
// itself rather than by dyld, so a plain executable is enough.

let package = Package(
    name: "DyldDynamicInterposeDemo",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "DyldDynamicInterposeDemo",
            dependencies: [
                .product(name: "SwiftStdlibToolbox", package: "FrameworkToolbox"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
