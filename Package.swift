// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

// Availability macros, so that a gated declaration reads `@available(SwiftStdlib 5.7, *)`
// rather than spelling four platform versions out at every site. The list and the version
// mapping are taken verbatim from upstream, which is the point: these names mean the same
// thing here as they do in the standard library and in swift-foundation, so a version read
// off a `.swiftinterface` can be used without re-deriving it.
//
// **These names must never appear in a macro's expansion.** `AvailabilityMacro` is a
// per-target compiler setting, and a macro expands into the *caller's* compilation unit,
// where it is not set — `LoggableMacro.loggerAvailability` and
// `SignpostableMacro.signposterAvailability` therefore keep spelling the platform versions
// out in full. Same rule as the one about a macro expanding to code that names a module the
// caller never imported, in a different disguise.
let availabilityMacros: KeyValuePairs<String, String> = [
    "SwiftStdlib 5.0": "macOS 10.14.4, iOS 12.2, watchOS 5.2, tvOS 12.2",
    "SwiftStdlib 5.1": "macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0",
    "SwiftStdlib 5.6": "macOS 12.3, iOS 15.4, watchOS 8.5, tvOS 15.4",
    "SwiftStdlib 5.7": "macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0",
    "SwiftStdlib 5.8": "macOS 13.3, iOS 16.4, watchOS 9.4, tvOS 16.4",
    "SwiftStdlib 5.9": "macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0",
    "SwiftStdlib 5.10": "macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4, visionOS 1.1",
    "SwiftStdlib 6.0": "macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0",
    "SwiftStdlib 6.1": "macOS 15.4, iOS 18.4, watchOS 11.4, tvOS 18.4, visionOS 2.4",
    "SwiftStdlib 6.2": "macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0",
    "SwiftStdlib 6.3": "macOS 26.4, iOS 26.4, watchOS 26.4, tvOS 26.4, visionOS 26.4",
    "SwiftStdlib 6.4": "macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0",
    "SwiftStdlib 6.5": "macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999",
]

let availabilityMacroSettings: [SwiftSetting] = availabilityMacros.map { name, platforms in
    .enableExperimentalFeature("AvailabilityMacro=\(name): \(platforms)")
}

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
            // the stdlib or Foundation layers (notably `DyldToolbox`, for
            // `Mutex`) can still use them. Both `SwiftStdlibToolbox` and,
            // through it, `FoundationToolbox` re-export this target, so existing
            // call sites importing either one keep working unchanged.
            name: "OSToolbox",
            targets: ["OSToolbox"]
        ),
        .library(
            // dyld interposing — `@DyldInterpose`, `@DyldDynamicInterpose`, and
            // the runtime that reads their sections back. Split out so that a
            // consumer wanting only the binary-level hooks does not drag in the
            // Swift-extension layers above (`SwiftStdlibToolbox`,
            // `FoundationToolbox`) — and, in the other direction, so that a
            // consumer of those layers no longer links the arm64e
            // pointer-authentication C shim only these hooks need.
            // It does sit on `OSToolbox` (and through it `FrameworkToolbox`)
            // for `Mutex`. `SwiftStdlibToolbox` re-exports this target, so
            // existing call sites keep working unchanged.
            //
            // Deliberately a static library rather than `.dynamic`:
            // `@DyldDynamicInterpose` reads the `__DATA,__dyn_interpose` section
            // of the *calling* image (`#dsohandle` is a default argument, so it
            // is evaluated at the call site), and static embedding is what makes
            // "whoever declares the interpose owns the section" hold.
            name: "DyldToolbox",
            targets: ["DyldToolbox"]
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
            //
            // The flip side of `.dynamic`: Xcode builds a dynamic product's
            // transitive targets as shared dynamic frameworks too, switching
            // every client in the workspace to @rpath-linking them. That is
            // why the target below must stay macro-only — see its comment and
            // the `objc-runtime-toolbox-self-contained-leaf` proposal.
            name: "ObjCRuntimeToolbox",
            type: .dynamic,
            targets: ["ObjCRuntimeToolbox"]
        ),
    ],
    dependencies: [
        // Floor is 600.0.0 because `@Loggable` / `@Signpostable` read
        // `MacroExpansionContext.lexicalContext` to detect a type nested inside a
        // generic one, and that API landed in 600.0.0 — neither 509.1.0 nor 510.0.3
        // has it. Costs nothing in practice: this package's tools version is 6.2, so
        // the old floor was only ever nominal.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0" ..< "604.0.0"),
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
                // Only to re-export it — see `SwiftStdlibToolbox/Exported.swift`.
                // Nothing in this target's own sources touches dyld interposing.
                "DyldToolbox",
            ]
        ),
        .target(
            name: "DyldToolbox",
            dependencies: [
                // For `Mutex`, guarding the bookkeeping `revertAll()` needs.
                "OSToolbox",
                "DyldToolboxMacros",
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
                // Macro-only on purpose — a macro target is a compile-time
                // plugin and never enters the product's link closure. Any
                // runtime target dependency added here becomes part of the
                // `.dynamic` product's transitive closure, which Xcode builds
                // as shared dynamic frameworks for the whole workspace; nested
                // executables without an rpath (daemons, XPC helpers) then
                // crash at dyld time. This is what broke RuntimeViewer's
                // SMAppService daemon in 0.10.0. Guarded by
                // `PackageTopologyGuardTests`; see the
                // `objc-runtime-toolbox-self-contained-leaf` proposal.
                "ObjCRuntimeToolboxMacros",
            ]
        ),
        .target(
            name: "MacroToolbox",
            dependencies: [
                .SwiftSyntax,
                .SwiftSyntaxMacros,
                // `LockPropertyParser` builds syntax from string literals
                // (`ExprSyntax("nil")`), and that conformance is SwiftSyntaxBuilder's.
                // It used to resolve only because `SwiftSyntaxMacros` pulls the module
                // into the search path — an undeclared dependency of exactly the kind
                // Xcode 27's `VALIDATE_DEPENDENCIES` reports.
                .SwiftSyntaxBuilder,
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
            name: "DyldToolboxMacros",
            dependencies: [
                // Deliberately no `MacroToolbox`: what lives there is the
                // lock-macro shared machinery (`LockMacroProtocol`,
                // `LockPropertyParser`), none of which these macros use.
                .SwiftSyntax,
                .SwiftSyntaxMacros,
                .SwiftCompilerPlugin,
                .SwiftSyntaxBuilder,
                .SwiftDiagnostics,
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
        // Guards that `@Loggable` / `@Signpostable` / `#log` / `#signpost` never
        // expand to code requiring Foundation. It has to be a separate target
        // from `OSToolboxClient`: conformance lookup is module-wide, so a single
        // `import Foundation` anywhere in a target would hand `String: CVarArg`
        // to every file in it and defeat the guard. No file here may import
        // Foundation.
        .executableTarget(
            name: "OSToolboxNoFoundationClient",
            dependencies: ["OSToolbox"]
        ),
        .executableTarget(
            name: "SwiftStdlibToolboxClient",
            dependencies: ["SwiftStdlibToolbox"]
        ),
        .executableTarget(
            name: "DyldToolboxClient",
            dependencies: ["DyldToolbox"]
        ),
        .executableTarget(
            name: "FoundationToolboxClient",
            dependencies: ["FoundationToolbox"]
        ),
        // Guards that a single `import FoundationToolbox` is enough — see the comment at
        // the top of the target's `main.swift`. It must stay a target of its own:
        // `FoundationToolboxClient` imports other modules for unrelated reasons, and any
        // one of those silently satisfies what the macros expand to.
        .executableTarget(
            name: "FoundationToolboxSoleImportClient",
            dependencies: ["FoundationToolbox"]
        ),
        .executableTarget(
            name: "CoreFoundationToolboxClient",
            dependencies: ["CoreFoundationToolbox"]
        ),
        // Guards that a single `import CoreFoundationToolbox` is enough — see the comment at
        // the top of the target's `main.swift`. It must stay a target of its own:
        // `CoreFoundationToolboxClient` imports other modules for unrelated reasons, and any
        // one of those silently satisfies what the macros expand to.
        .executableTarget(
            name: "CoreFoundationToolboxSoleImportClient",
            dependencies: ["CoreFoundationToolbox"]
        ),
        .executableTarget(
            name: "ObjCRuntimeToolboxClient",
            dependencies: ["ObjCRuntimeToolbox"]
        ),
        // Guards that a single `import ObjCRuntimeToolbox` is enough — see the comment at
        // the top of the target's `main.swift`. It must stay a target of its own:
        // `ObjCRuntimeToolboxClient` imports other modules for unrelated reasons, and any
        // one of those silently satisfies what the macros expand to.
        .executableTarget(
            name: "ObjCRuntimeToolboxSoleImportClient",
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
            name: "DyldToolboxTests",
            dependencies: [
                "DyldToolbox",
            ]
        ),
        .testTarget(
            name: "DyldToolboxMacroTests",
            dependencies: [
                "DyldToolboxMacros",
                .product(name: "MacroTesting", package: "swift-macro-testing"),
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

// Applied here rather than on each target: there are 39 of them, and a setting that has to
// be remembered every time a target is added is a setting that will be forgotten.
// `PointerAuthenticationSupport` is excluded because it is a C target with no Swift to
// compile.
for target in package.targets where target.name != "PointerAuthenticationSupport" {
    target.swiftSettings = (target.swiftSettings ?? []) + availabilityMacroSettings
}
