// swift-tools-version: 6.2

import PackageDescription

// Standalone example package: an executable that links against the
// `DyldInterposeDemoLib` dynamic library and exercises the hooked symbols.
//
// At launch, dyld scans every loaded image's `__DATA,__interpose` section —
// including the demo library's — and rewrites the corresponding import
// slots in this host, so calls to `puts` / `printfRef` are redirected to
// the dylib's replacement implementations.

let package = Package(
    name: "DyldInterposeDemoHost",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(path: "../DyldInterposeDemoLib"),
    ],
    targets: [
        .executableTarget(
            name: "DyldInterposeDemoHost",
            dependencies: [
                .product(name: "DyldInterposeDemoLib", package: "DyldInterposeDemoLib"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("Extern"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
