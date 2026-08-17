import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct LoggableMacro: MemberMacro, ExtensionMacro {

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
        return buildConcreteMembers(node: node, declaration: declaration)
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
    declaration: some DeclGroupSyntax
) -> [DeclSyntax] {
    let accessLevel = extractAccessLevel(from: node)
    let accessPrefix = accessLevel == "internal" ? "" : "\(accessLevel) "
    let customSubsystem = extractStringLiteral(labeled: "subsystem", from: node)
    let customCategory = extractStringLiteral(labeled: "category", from: node)

    let typeNameLiteral = quoteString(staticTypeName(from: declaration))
    let categoryBody = customCategory ?? typeNameLiteral
    // No bundle-identifier fallback: an unspecified subsystem is the type name,
    // the same string the category defaults to. Deriving it from `Bundle` would
    // put Foundation in the expansion, which lands in the caller's file.
    let subsystemBody = customSubsystem ?? typeNameLiteral

    var members: [DeclSyntax] = [
        "\(raw: accessPrefix)nonisolated static var category: String { \(raw: categoryBody) }",
        "\(raw: accessPrefix)nonisolated static var subsystem: String { \(raw: subsystemBody) }",
        "\(raw: accessPrefix)nonisolated static let _osLog = os.OSLog(subsystem: subsystem, category: category)",
        """
        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        \(raw: accessPrefix)nonisolated static let logger = os.Logger(subsystem: subsystem, category: category)
        """,
        """
        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        \(raw: accessPrefix)nonisolated var logger: os.Logger { Self.logger }
        """,
    ]
    members.append(contentsOf: buildCategoryAccessorMembers(accessPrefix: accessPrefix))
    return members
}

/// Builds the per-category accessors backing the `#log(category: .name, ...)`
/// overload. Categories are values of the library's `LogCategory` struct, so
/// the accessors take any category and route through the shared
/// per-subsystem/category cache; the subsystem stays the annotated type's own.
private func buildCategoryAccessorMembers(accessPrefix: String) -> [DeclSyntax] {
    return [
        """
        \(raw: accessPrefix)nonisolated static func _osLog(for category: OSToolbox.LogCategory) -> os.OSLog {
            LoggableMacro._sharedOSLog(subsystem: subsystem, category: category.name)
        }
        """,
        """
        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        \(raw: accessPrefix)nonisolated static func logger(for category: OSToolbox.LogCategory) -> os.Logger {
            LoggableMacro._sharedLogger(subsystem: subsystem, category: category.name)
        }
        """,
    ]
}

// MARK: - Protocol requirements

/// Protocol-internal declarations carry no access modifier, no `nonisolated`,
/// and no body — they're plain protocol requirements that conforming types may
/// satisfy with their own storage / computed properties.
private func buildProtocolRequirements() -> [DeclSyntax] {
    return [
        "static var category: String { get }",
        "static var subsystem: String { get }",
        "static var _osLog: os.OSLog { get }",
        """
        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        static var logger: os.Logger { get }
        """,
        """
        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        var logger: os.Logger { get }
        """,
    ]
}

// MARK: - Protocol default implementations

/// The default-implementation extension. Its access modifier is derived from the
/// protocol's own access level so that conforming public/internal/etc. types can
/// actually pick up the default witness without re-implementing every property.
private func buildProtocolDefaultImplementations(
    node: AttributeSyntax,
    declaration: some DeclGroupSyntax
) -> [DeclSyntax] {
    let accessLevel = protocolAccessLevel(from: declaration)
    let accessPrefix = accessLevel == "internal" ? "" : "\(accessLevel) "
    let customSubsystem = extractStringLiteral(labeled: "subsystem", from: node)
    let customCategory = extractStringLiteral(labeled: "category", from: node)

    let typeNameExpression = "String(describing: self)"
    let categoryBody = customCategory ?? typeNameExpression
    let subsystemBody = customSubsystem ?? typeNameExpression

    var members: [DeclSyntax] = [
        "\(raw: accessPrefix)nonisolated static var category: String { \(raw: categoryBody) }",
        "\(raw: accessPrefix)nonisolated static var subsystem: String { \(raw: subsystemBody) }",
        """
        \(raw: accessPrefix)nonisolated static var _osLog: os.OSLog {
            LoggableMacro._sharedOSLog(for: self, subsystem: subsystem, category: category)
        }
        """,
        """
        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        \(raw: accessPrefix)nonisolated static var logger: os.Logger {
            LoggableMacro._sharedLogger(for: self, subsystem: subsystem, category: category)
        }
        """,
        """
        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        \(raw: accessPrefix)nonisolated var logger: os.Logger { Self.logger }
        """,
    ]
    members.append(contentsOf: buildCategoryAccessorMembers(accessPrefix: accessPrefix))
    return members
}
