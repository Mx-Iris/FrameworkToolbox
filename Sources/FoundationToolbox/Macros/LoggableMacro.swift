#if canImport(os)

import os.log
import Foundation

/// Automatically generates logging infrastructure for the annotated declaration.
///
/// Applying `@Loggable` generates all logging properties directly as members,
/// without requiring conformance to any protocol. The macro adapts to the kind
/// of declaration it is attached to:
///
/// - On `struct`, `class`, `enum`, or `actor`: emits stored properties for the
///   logger and `OSLog`, evaluated once per type at first access.
/// - On `protocol`: emits both **protocol requirements** (so conforming types
///   may override them and protocol-extension call sites dispatch dynamically)
///   and a **sibling extension** providing default implementations. Each
///   conforming type gets its own cached `os.Logger` / `OSLog` keyed by its
///   runtime metatype identity. The default-implementation extension picks up
///   its access level from the protocol declaration itself.
///
/// > Note: Due to a Swift language restriction, `@Loggable` cannot be attached
/// > to an `extension` declaration. Attach it to the type or protocol instead.
///
/// - Parameters:
///   - accessLevel: The access level for generated properties. Defaults to `.private`.
///   - asProtocolRequirement: Only meaningful when attached to a `protocol`.
///     When `true` (the default), the macro emits protocol requirements so
///     conforming types may override them and protocol-extension call sites
///     dispatch dynamically. When `false`, only the default-implementation
///     extension is emitted — conforming types cannot override, and all call
///     sites resolve statically to the default implementation. Use the latter
///     when you want the logging properties to be "frozen" for all conformers.
///   - subsystem: Override the auto-generated subsystem with a string literal.
///     Defaults to `nil`, which generates `Bundle.main.bundleIdentifier ?? "<TypeName>"`
///     (or `Bundle(for: self).bundleIdentifier ?? "<TypeName>"` for classes).
///   - category: Override the auto-generated category with a string literal.
///     Defaults to `nil`, which generates `"<TypeName>"`.
///
/// Besides the type-level default logger, the macro always generates
/// `logger(for:)` / `_osLog(for:)` accessors taking a ``LogCategory``, backed
/// by a shared per-subsystem/category cache. Declare categories as static
/// members on ``LogCategory`` and select one per call site with
/// `#log(.debug, category: .network, "…")`.
///
/// Example — concrete type:
///
///     @Loggable
///     struct MyService { }
///
///     // Expands to:
///     // struct MyService {
///     //     static var category: String { "MyService" }
///     //     static var subsystem: String { Bundle.main.bundleIdentifier ?? "MyService" }
///     //     static let _osLog = OSLog(subsystem: subsystem, category: category)
///     //     @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
///     //     static let logger = os.Logger(subsystem: subsystem, category: category)
///     //     @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
///     //     var logger: os.Logger { Self.logger }
///     // }
///
/// Example — protocol:
///
///     @Loggable
///     protocol Networking { }
///
///     // Expands to (alongside the protocol):
///     // extension Networking {
///     //     static var category: String { String(describing: self) }
///     //     static var subsystem: String { Bundle.main.bundleIdentifier ?? String(describing: self) }
///     //     static var _osLog: OSLog { LoggableMacro._sharedOSLog(for: self, subsystem: subsystem, category: category) }
///     //     @available(...) static var logger: os.Logger {
///     //         LoggableMacro._sharedLogger(for: self, subsystem: subsystem, category: category)
///     //     }
///     //     @available(...) var logger: os.Logger { Self.logger }
///     // }
///
/// You can also specify a different access level or override subsystem/category:
///
///     @Loggable(.public)
///     class MyPublicService { }
///
///     @Loggable(.internal, subsystem: "com.example.app", category: "Network")
///     struct NetworkService { }
///
/// Or declare named categories on ``LogCategory`` and pick one per call site:
///
///     extension LogCategory {
///         static let network = LogCategory("network")
///         static let persistence = LogCategory("persistence")
///     }
///
///     @Loggable
///     struct SyncService {
///         func run() {
///             #log(.debug, category: .network, "request issued")
///             #log(.info, category: .persistence, "records saved")
///         }
///     }
@attached(member, names: named(_osLog), named(category), named(subsystem), named(logger))
@attached(extension, names: named(_osLog), named(category), named(subsystem), named(logger))
public macro Loggable(
    _ accessLevel: AccessLevel = .private,
    subsystem: StaticString? = nil,
    category: StaticString? = nil
) = #externalMacro(module: "FoundationToolboxMacros", type: "LoggableMacro")

/// Overload of `@Loggable` that exposes the `asProtocolRequirement` switch
/// (see the parameter documentation on the main `@Loggable` declaration).
@attached(member, names: named(_osLog), named(category), named(subsystem), named(logger))
@attached(extension, names: named(_osLog), named(category), named(subsystem), named(logger))
public macro Loggable(
    _ accessLevel: AccessLevel = .private,
    asProtocolRequirement: Bool,
    subsystem: StaticString? = nil,
    category: StaticString? = nil
) = #externalMacro(module: "FoundationToolboxMacros", type: "LoggableMacro")

#endif
