#if canImport(os)

import os.log
import Foundation

/// Automatically generates logging infrastructure for the annotated type.
///
/// Applying `@Loggable` generates all logging properties directly as members,
/// without requiring conformance to any protocol.
///
/// Example:
///
///     @Loggable
///     struct MyService { }
///
///     // Expands to:
///     // struct MyService {
///     //     static let _loggableSwiftLogger = Logging.Logger(label: "MyService")
///     //     static var category: String { "MyService" }
///     //     static var subsystem: String { Bundle.main.bundleIdentifier ?? "MyService" }
///     //     @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
///     //     static let logger = os.Logger(subsystem: subsystem, category: category)
///     //     @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
///     //     var logger: os.Logger { Self.logger }
///     // }
@attached(member, names: named(_loggableSwiftLogger), named(category), named(subsystem), named(logger))
public macro Loggable() = #externalMacro(module: "FoundationToolboxMacros", type: "LoggableMacro")

#endif
