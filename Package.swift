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
        .library(
            name: "FrameworkToolboxMacro",
            targets: ["FrameworkToolboxMacro"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            "509.1.0" ..< "602.0.0"
        ),
    ],
    targets: [
        .target(
            name: "FrameworkToolbox",
            dependencies: [
                "FrameworkToolboxMacro",
            ]
        ),
        .target(
            name: "SwiftStdlibToolbox",
            dependencies: [
                "FrameworkToolbox",
                "FrameworkToolboxMacro",
            ]
        ),
        .target(
            name: "FoundationToolbox",
            dependencies: [
                "FrameworkToolbox",
                "SwiftStdlibToolbox",
                "FrameworkToolboxMacro",
            ]
        ),
        .target(
            name: "FrameworkToolboxMacro",
            dependencies: [
                "FrameworkToolboxMacroPlugins",
            ]
        ),
        .macro(
            name: "FrameworkToolboxMacroPlugins",
            dependencies: [
                .SwiftSyntax,
                .SwiftSyntaxMacros,
                .SwiftCompilerPlugin,
                .SwiftSyntaxBuilder,
            ]
        ),
        .testTarget(
            name: "FrameworkToolboxTests",
            dependencies: ["FrameworkToolbox"]
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
}
