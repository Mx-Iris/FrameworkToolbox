#if canImport(os)

import os.log
import Foundation

/// Automatically generates logging infrastructure for the annotated type.
///
/// Applying `@Loggable` generates all logging properties directly as members,
/// without requiring conformance to any protocol.
///
/// - Parameter accessLevel: The access level for generated properties. Defaults to `.internal`.
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
/// You can also specify a different access level:
///
///     @Loggable(.public)
///     class MyPublicService { }
@attached(member, names: named(_osLog), named(category), named(subsystem), named(logger))
public macro Loggable(_ accessLevel: AccessLevel = .internal) = #externalMacro(module: "FoundationToolboxMacros", type: "LoggableMacro")

#endif
