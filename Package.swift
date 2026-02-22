// swift-tools-version: 6.1
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
            name: "SwiftStdlibToolbox",
            targets: ["SwiftStdlibToolbox"]
        ),
        .library(
            name: "FoundationToolbox",
            targets: ["FoundationToolbox"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "509.1.0" ..< "602.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "FrameworkToolbox",
            dependencies: [
                "FrameworkToolboxMacros",
            ]
        ),
        .target(
            name: "SwiftStdlibToolbox",
            dependencies: [
                "FrameworkToolbox",
                "SwiftStdlibToolboxMacros",
            ]
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
//                .MacroToolkit,
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
//                .MacroToolkit,
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
//                .MacroToolkit,
            ]
        ),
        .executableTarget(
            name: "FrameworkToolboxClient",
            dependencies: ["FrameworkToolbox"]
        ),
        .executableTarget(
            name: "SwiftStdlibToolboxClient",
            dependencies: ["SwiftStdlibToolbox"]
        ),
        .executableTarget(
            name: "FoundationToolboxClient",
            dependencies: ["FoundationToolbox"]
        ),
        
        .testTarget(
            name: "FrameworkToolboxTests",
            dependencies: [
                "FrameworkToolbox",
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
//    static let MacroToolkit = Target.Dependency.product(
//        name: "MacroToolkit",
//        package: "swift-macro-toolkit"
//    )
}
