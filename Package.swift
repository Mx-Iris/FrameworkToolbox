// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "FrameworkToolbox",
    platforms: [.iOS(.v13), .macOS(.v10_15), .watchOS(.v6), .tvOS(.v13), .macCatalyst(.v13), .visionOS(.v1)],
    products: [
        .library(
            name: "FrameworkToolbox",
            targets: ["FrameworkToolbox"]
        ),
        .library(
            // Holds every abstraction layered directly on Apple's `os` module —
            // `Mutex`, `@Loggable`/`#log`, `@OSAllocatedUnfairLock`. It sits
            // below `SwiftStdlibToolbox` so that targets which must not pull in
            // the stdlib or Foundation layers (notably `ObjCRuntimeToolbox`)
            // can still use them. Both `SwiftStdlibToolbox` and, through it,
            // `FoundationToolbox` re-export this target, so existing call sites
            // importing either one keep working unchanged.
            name: "OSToolbox",
            targets: ["OSToolbox"]
        ),
        .library(
            name: "SwiftStdlibToolbox",
            targets: ["SwiftStdlibToolbox"]
        ),
        .library(
            name: "FoundationToolbox",
            targets: ["FoundationToolbox"]
        ),
        .library(
            name: "CoreFoundationToolbox",
            targets: ["CoreFoundationToolbox"]
        ),
        .library(
            // `.dynamic` keeps the runtime side-table (sharedSideTable,
            // sharedSubclassCache, sentinelAssociationKey) as a single
            // process-wide copy. Without it, every dylib that statically
            // embeds this library would get its own state — `isInstalled`
            // would lie across module boundaries and the associated-object
            // key for the dealloc sentinel would differ between dylibs.
            name: "ObjCRuntimeToolbox",
            type: .dynamic,
            targets: ["ObjCRuntimeToolbox"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "509.1.0" ..< "604.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", from: "0.6.5"),
    ],
    targets: [
        .target(
            name: "FrameworkToolbox",
            dependencies: [
                "FrameworkToolboxMacros",
            ]
        ),
        .target(
            name: "OSToolbox",
            dependencies: [
                // For `AccessLevel`, the parameter type of `@Loggable`.
                "FrameworkToolbox",
                "OSToolboxMacros",
            ]
        ),
        .target(
            name: "SwiftStdlibToolbox",
            dependencies: [
                "FrameworkToolbox",
                "OSToolbox",
                "SwiftStdlibToolboxMacros",
                "PointerAuthenticationSupport",
            ]
        ),
        // C shim for the arm64e pointer-authentication intrinsics Swift has no
        // spelling for. Needed by `DyldDynamicInterpose` to compare and rewrite
        // signed `__auth_got` slots; a no-op on arm64 and x86_64.
        .target(
            name: "PointerAuthenticationSupport"
        ),
        .target(
            name: "FoundationToolbox",
            dependencies: [
                "FrameworkToolbox",
                "SwiftStdlibToolbox",
                "FoundationToolboxMacros",
            ]
        ),
        .target(
            name: "CoreFoundationToolbox",
            dependencies: [
                "FrameworkToolbox",
            ]
        ),
        .target(
            name: "ObjCRuntimeToolbox",
            dependencies: [
                "OSToolbox",
                "ObjCRuntimeToolboxMacros",
            ]
        ),
        .target(
            name: "MacroToolbox",
            dependencies: [
                .SwiftSyntax,
                .SwiftSyntaxMacros,
                .SwiftDiagnostics,
            ]
        ),
        .macro(
            name: "FrameworkToolboxMacros",
            dependencies: [
                .SwiftSyntax,
                .SwiftSyntaxMacros,
                .SwiftCompilerPlugin,
                .SwiftSyntaxBuilder,
            ]
        ),
        .macro(
            name: "OSToolboxMacros",
            dependencies: [
                "MacroToolbox",
                .SwiftSyntax,
                .SwiftSyntaxMacros,
                .SwiftCompilerPlugin,
                .SwiftSyntaxBuilder,
                .SwiftDiagnostics,
            ]
        ),
        .macro(
            name: "SwiftStdlibToolboxMacros",
            dependencies: [
                "MacroToolbox",
                .SwiftSyntax,
                .SwiftSyntaxMacros,
                .SwiftCompilerPlugin,
                .SwiftSyntaxBuilder,
            ]
        ),
        .macro(
            name: "FoundationToolboxMacros",
            dependencies: [
                "MacroToolbox",
                .SwiftSyntax,
                .SwiftSyntaxMacros,
                .SwiftCompilerPlugin,
                .SwiftSyntaxBuilder,
                .SwiftDiagnostics,
            ]
        ),
        .macro(
            name: "ObjCRuntimeToolboxMacros",
            dependencies: [
                "MacroToolbox",
                .SwiftSyntax,
                .SwiftSyntaxMacros,
                .SwiftCompilerPlugin,
                .SwiftSyntaxBuilder,
                .SwiftDiagnostics,
            ]
        ),
        .executableTarget(
            name: "FrameworkToolboxClient",
            dependencies: ["FrameworkToolbox"]
        ),
        .executableTarget(
            name: "OSToolboxClient",
            dependencies: ["OSToolbox"]
        ),
        .executableTarget(
            name: "SwiftStdlibToolboxClient",
            dependencies: ["SwiftStdlibToolbox"]
        ),
        .executableTarget(
            name: "FoundationToolboxClient",
            dependencies: ["FoundationToolbox"]
        ),
        .executableTarget(
            name: "CoreFoundationToolboxClient",
            dependencies: ["CoreFoundationToolbox"]
        ),
        .executableTarget(
            name: "ObjCRuntimeToolboxClient",
            dependencies: ["ObjCRuntimeToolbox"]
        ),

        .testTarget(
            name: "FrameworkToolboxTests",
            dependencies: [
                "FrameworkToolbox",
            ]
        ),
        .testTarget(
            name: "OSToolboxTests",
            dependencies: [
                "OSToolbox",
            ]
        ),
        .testTarget(
            name: "OSToolboxMacroTests",
            dependencies: [
                "OSToolboxMacros",
                "MacroToolbox",
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ]
        ),
        .testTarget(
            name: "SwiftStdlibToolboxTests",
            dependencies: [
                "SwiftStdlibToolbox",
                "MacroToolbox",
            ]
        ),
        .testTarget(
            name: "FoundationToolboxTests",
            dependencies: [
                "FoundationToolbox",
                "MacroToolbox",
            ]
        ),
        .testTarget(
            name: "CoreFoundationToolboxTests",
            dependencies: [
                "CoreFoundationToolbox",
            ]
        ),
        .testTarget(
            name: "ObjCRuntimeToolboxTests",
            dependencies: [
                "ObjCRuntimeToolbox",
            ]
        ),
        .testTarget(
            name: "ObjCRuntimeToolboxMacroTests",
            dependencies: [
                "ObjCRuntimeToolboxMacros",
                "MacroToolbox",
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ]
        ),

        .testTarget(
            name: "FrameworkToolboxMacroTests",
            dependencies: [
                "FrameworkToolboxMacros",
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ]
        ),
        .testTarget(
            name: "SwiftStdlibToolboxMacroTests",
            dependencies: [
                "SwiftStdlibToolboxMacros",
                "MacroToolbox",
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ]
        ),
        .testTarget(
            name: "FoundationToolboxMacroTests",
            dependencies: [
                "FoundationToolboxMacros",
                "MacroToolbox",
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)

extension Target.Dependency {
    static let SwiftSyntax = Target.Dependency.product(
        name: "SwiftSyntax",
        package: "swift-syntax"
    )
    static let SwiftSyntaxMacros = Target.Dependency.product(
        name: "SwiftSyntaxMacros",
        package: "swift-syntax"
    )
    static let SwiftCompilerPlugin = Target.Dependency.product(
        name: "SwiftCompilerPlugin",
        package: "swift-syntax"
    )
    static let SwiftSyntaxMacrosTestSupport = Target.Dependency.product(
        name: "SwiftSyntaxMacrosTestSupport",
        package: "swift-syntax"
    )
    static let SwiftSyntaxBuilder = Target.Dependency.product(
        name: "SwiftSyntaxBuilder",
        package: "swift-syntax"
    )
    static let SwiftDiagnostics = Target.Dependency.product(
        name: "SwiftDiagnostics",
        package: "swift-syntax"
    )
}
