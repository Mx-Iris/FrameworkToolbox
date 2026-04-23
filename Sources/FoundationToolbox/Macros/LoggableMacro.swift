#if canImport(os)

import os.log
import Foundation

/// Automatically generates logging infrastructure for the annotated type.
///
/// Applying `@Loggable` generates all logging properties directly as members,
/// without requiring conformance to any protocol.
///
/// - Parameters:
///   - accessLevel: The access level for generated properties. Defaults to `.private`.
///   - subsystem: Override the auto-generated subsystem with a string literal.
///     Defaults to `nil`, which generates `Bundle.main.bundleIdentifier ?? "<TypeName>"`
///     (or `Bundle(for: self).bundleIdentifier ?? "<TypeName>"` for classes).
///   - category: Override the auto-generated category with a string literal.
///     Defaults to `nil`, which generates `"<TypeName>"`.
///
/// Example:
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
/// You can also specify a different access level or override subsystem/category:
///
///     @Loggable(.public)
///     class MyPublicService { }
///
///     @Loggable(.internal, subsystem: "com.example.app", category: "Network")
///     struct NetworkService { }
@attached(member, names: named(_osLog), named(category), named(subsystem), named(logger))
public macro Loggable(
    _ accessLevel: AccessLevel = .private,
    subsystem: StaticString? = nil,
    category: StaticString? = nil
) = #externalMacro(module: "FoundationToolboxMacros", type: "LoggableMacro")

#endif
