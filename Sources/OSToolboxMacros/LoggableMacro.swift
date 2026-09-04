import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct LoggableMacro: MemberMacro, ExtensionMacro {

    /// The floor for `os.Logger` — three OS versions above this package's own,
    /// which is why the generated code carries a legacy `os_log` path at all.
    static let loggerAvailability = "@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)"

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        if declaration.is(ProtocolDeclSyntax.self) {
            // Honor the `asProtocolRequirement:` opt-out: when the user explicitly
            // freezes the implementation, we skip emitting requirements so all
            // call sites resolve statically against the default extension.
            guard extractBoolLiteral(labeled: "asProtocolRequirement", from: node) ?? true else {
                return []
            }
            return buildProtocolRequirements()
        }
        return buildConcreteMembers(
            node: node,
            declaration: declaration,
            // A generic context forbids static stored properties, so the live
            // handles have to come from the runtime cache instead of a
            // `static let`. This is what lets `@Loggable` go on a generic type.
            usesRuntimeCache: isInGenericContext(
                declaration: declaration,
                lexicalContext: context.lexicalContext
            )
        )
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(ProtocolDeclSyntax.self) else {
            return []
        }

        let members = buildProtocolDefaultImplementations(node: node, declaration: declaration)
        let memberBlock = members
            .map { indent($0.trimmedDescription, by: 4) }
            .joined(separator: "\n\n")

        let extensionSource: SyntaxNodeString = """
        extension \(type.trimmed) {
        \(raw: memberBlock)
        }
        """
        return [try ExtensionDeclSyntax(extensionSource)]
    }
}

// MARK: - Concrete (struct/class/enum/actor) generation

private func buildConcreteMembers(
    node: AttributeSyntax,
    declaration: some DeclGroupSyntax,
    usesRuntimeCache: Bool
) -> [DeclSyntax] {
    let accessLevel = extractAccessLevel(from: node)
    let accessPrefix = accessLevel == "internal" ? "" : "\(accessLevel) "
    let customSubsystem = extractStringLiteral(labeled: "subsystem", from: node)
    let customCategory = extractStringLiteral(labeled: "category", from: node)
    let enablement = extractEnablement(from: node)

    let typeNameLiteral = quoteString(staticTypeName(from: declaration))
    let categoryBody = customCategory ?? typeNameLiteral
    // No bundle-identifier fallback: an unspecified subsystem is the type name,
    // the same string the category defaults to. Deriving it from `Bundle` would
    // put Foundation in the expansion, which lands in the caller's file.
    let subsystemBody = customSubsystem ?? typeNameLiteral

    var members: [DeclSyntax] = [
        "\(raw: accessPrefix)nonisolated static var category: String { \(raw: categoryBody) }",
        "\(raw: accessPrefix)nonisolated static var subsystem: String { \(raw: subsystemBody) }",
    ]
    members.append(contentsOf: buildHandleMembers(
        accessPrefix: accessPrefix,
        enablement: enablement,
        usesRuntimeCache: usesRuntimeCache
    ))
    members.append("""
    \(raw: LoggableMacro.loggerAvailability)
    \(raw: accessPrefix)nonisolated var logger: os.Logger { Self.logger }
    """)
    members.append(contentsOf: buildCategoryAccessorMembers(
        accessPrefix: accessPrefix,
        enablement: enablement
    ))
    return members
}

/// The type-level `_osLog` / `logger` pair, in whichever of three shapes the
/// attribute and the surrounding context call for.
///
/// - `isEnabled: false` — the handles are `.disabled` constants and no storage
///   is emitted at all, so the optimizer can drop the logging path entirely.
/// - `usesRuntimeCache` — a generic context (or a protocol's default
///   implementations), where Swift permits no static stored property. The live
///   handle comes from the metatype-keyed process-wide cache.
/// - otherwise — the live handle is cached in a `static let` and the accessor
///   only tests the switches.
private func buildHandleMembers(
    accessPrefix: String,
    enablement: EnablementConfiguration,
    usesRuntimeCache: Bool
) -> [DeclSyntax] {
    let availability = LoggableMacro.loggerAvailability
    let condition = enablement.condition(
        switchEntryPoint: "LoggableMacro._isEnabled",
        categoryExpression: "category"
    )

    guard let condition else {
        return [
            "\(raw: accessPrefix)nonisolated static var _osLog: os.OSLog { .disabled }",
            """
            \(raw: availability)
            \(raw: accessPrefix)nonisolated static var logger: os.Logger { .disabled }
            """,
        ]
    }

    let liveOSLogExpression = usesRuntimeCache
        ? "LoggableMacro._sharedOSLog(for: self, subsystem: subsystem, category: category)"
        : "_enabledOSLog"
    let liveLoggerExpression = usesRuntimeCache
        ? "LoggableMacro._sharedLogger(for: self, subsystem: subsystem, category: category)"
        : "_enabledLogger"

    var members: [DeclSyntax] = []
    if enablement.needsEnabledHandleStorage, !usesRuntimeCache {
        members.append(
            "\(raw: accessPrefix)nonisolated static let _enabledOSLog = os.OSLog(subsystem: subsystem, category: category)"
        )
    }
    members.append("""
    \(raw: accessPrefix)nonisolated static var _osLog: os.OSLog {
        guard \(raw: condition) else {
            return .disabled
        }
        return \(raw: liveOSLogExpression)
    }
    """)
    if enablement.needsEnabledHandleStorage, !usesRuntimeCache {
        // Built over `_enabledOSLog` rather than `init(subsystem:category:)` so
        // that `logger` and `_osLog` sit on one underlying handle. The system
        // makes no promise that two `OSLog(subsystem:category:)` calls share
        // one, and `@Signpostable` already depends on that property to pair a
        // begin with its end.
        members.append("""
        \(raw: availability)
        \(raw: accessPrefix)nonisolated static let _enabledLogger = os.Logger(_enabledOSLog)
        """)
    }
    members.append("""
    \(raw: availability)
    \(raw: accessPrefix)nonisolated static var logger: os.Logger {
        guard \(raw: condition) else {
            return .disabled
        }
        return \(raw: liveLoggerExpression)
    }
    """)
    return members
}

/// Builds the per-category accessors backing the `#log(category: .name, ...)`
/// overload. Categories are values of the library's `LogCategory` struct, so
/// the accessors take any category and route through the shared
/// per-subsystem/category cache; the subsystem stays the annotated type's own.
///
/// The switches are consulted against the *call site's* category rather than
/// the type's own, which is what makes `LoggingControl.setEnabled(false, for:)`
/// reach these call sites.
private func buildCategoryAccessorMembers(
    accessPrefix: String,
    enablement: EnablementConfiguration
) -> [DeclSyntax] {
    let availability = LoggableMacro.loggerAvailability
    let condition = enablement.condition(
        switchEntryPoint: "LoggableMacro._isEnabled",
        categoryExpression: "category.name"
    )

    guard let condition else {
        return [
            """
            \(raw: accessPrefix)nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                .disabled
            }
            """,
            """
            \(raw: availability)
            \(raw: accessPrefix)nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
                .disabled
            }
            """,
        ]
    }

    return [
        """
        \(raw: accessPrefix)nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
            guard \(raw: condition) else {
                return .disabled
            }
            return LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
        }
        """,
        """
        \(raw: availability)
        \(raw: accessPrefix)nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
            guard \(raw: condition) else {
                return .disabled
            }
            return LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
        }
        """,
    ]
}

// MARK: - Protocol requirements

/// Protocol-internal declarations carry no access modifier, no `nonisolated`,
/// and no body — they're plain protocol requirements that conforming types may
/// satisfy with their own storage / computed properties.
///
/// The `isEnabled:` switch adds nothing here: it is resolved inside the default
/// implementations below, so no new requirement appears and existing conformers
/// keep compiling.
private func buildProtocolRequirements() -> [DeclSyntax] {
    return [
        "static var category: String { get }",
        "static var subsystem: String { get }",
        "static var _osLog: os.OSLog { get }",
        """
        \(raw: LoggableMacro.loggerAvailability)
        static var logger: os.Logger { get }
        """,
        """
        \(raw: LoggableMacro.loggerAvailability)
        var logger: os.Logger { get }
        """,
    ]
}

// MARK: - Protocol default implementations

/// The default-implementation extension. Its access modifier is derived from the
/// protocol's own access level so that conforming public/internal/etc. types can
/// actually pick up the default witness without re-implementing every property.
///
/// A protocol extension can hold no stored properties either, so this shares the
/// runtime-cache shape with the generic branch.
private func buildProtocolDefaultImplementations(
    node: AttributeSyntax,
    declaration: some DeclGroupSyntax
) -> [DeclSyntax] {
    let accessLevel = protocolAccessLevel(from: declaration)
    let accessPrefix = accessLevel == "internal" ? "" : "\(accessLevel) "
    let customSubsystem = extractStringLiteral(labeled: "subsystem", from: node)
    let customCategory = extractStringLiteral(labeled: "category", from: node)
    let enablement = extractEnablement(from: node)

    let typeNameExpression = "String(describing: self)"
    let categoryBody = customCategory ?? typeNameExpression
    let subsystemBody = customSubsystem ?? typeNameExpression

    var members: [DeclSyntax] = [
        "\(raw: accessPrefix)nonisolated static var category: String { \(raw: categoryBody) }",
        "\(raw: accessPrefix)nonisolated static var subsystem: String { \(raw: subsystemBody) }",
    ]
    members.append(contentsOf: buildHandleMembers(
        accessPrefix: accessPrefix,
        enablement: enablement,
        usesRuntimeCache: true
    ))
    members.append("""
    \(raw: LoggableMacro.loggerAvailability)
    \(raw: accessPrefix)nonisolated var logger: os.Logger { Self.logger }
    """)
    members.append(contentsOf: buildCategoryAccessorMembers(
        accessPrefix: accessPrefix,
        enablement: enablement
    ))
    return members
}
