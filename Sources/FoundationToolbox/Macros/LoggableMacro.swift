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
/// - On `protocol`: emits a sibling extension that supplies default
///   implementations. Each conforming type gets its own cached
///   `os.Logger` / `OSLog` keyed by its runtime metatype identity.
///
/// > Note: Due to a Swift language restriction, `@Loggable` cannot be attached
/// > to an `extension` declaration. Attach it to the type or protocol instead.
///
/// - Parameters:
///   - accessLevel: The access level for generated properties. Defaults to `.private`.
///   - subsystem: Override the auto-generated subsystem with a string literal.
///     Defaults to `nil`, which generates `Bundle.main.bundleIdentifier ?? "<TypeName>"`
///     (or `Bundle(for: self).bundleIdentifier ?? "<TypeName>"` for classes).
///   - category: Override the auto-generated category with a string literal.
///     Defaults to `nil`, which generates `"<TypeName>"`.
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
@attached(member, names: named(_osLog), named(category), named(subsystem), named(logger))
@attached(extension, names: named(_osLog), named(category), named(subsystem), named(logger))
public macro Loggable(
    _ accessLevel: AccessLevel = .private,
    subsystem: StaticString? = nil,
    category: StaticString? = nil
) = #externalMacro(module: "FoundationToolboxMacros", type: "LoggableMacro")

#endif
