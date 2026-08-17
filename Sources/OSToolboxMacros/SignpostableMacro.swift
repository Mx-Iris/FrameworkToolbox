import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Implementation of `@Signpostable`. Structurally the same as `LoggableMacro` —
/// same attribute grammar, same concrete/protocol split, same access-level
/// handling — differing only in which members it emits.
public struct SignpostableMacro: MemberMacro, ExtensionMacro {

    /// The floor for `OSSignposter` and everything reachable through it.
    /// Three OS versions above this package's own floor, which is the whole
    /// reason the generated code carries a legacy path at all.
    static let signposterAvailability = "@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)"

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
            return buildSignpostProtocolRequirements()
        }
        return buildSignpostConcreteMembers(node: node, declaration: declaration)
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

        let members = buildSignpostProtocolDefaultImplementations(node: node, declaration: declaration)
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

private func buildSignpostConcreteMembers(
    node: AttributeSyntax,
    declaration: some DeclGroupSyntax
) -> [DeclSyntax] {
    let accessLevel = extractAccessLevel(from: node)
    let accessPrefix = accessLevel == "internal" ? "" : "\(accessLevel) "
    let customSubsystem = extractStringLiteral(labeled: "subsystem", from: node)
    let customCategory = extractStringLiteral(labeled: "category", from: node)

    let typeNameLiteral = quoteString(staticTypeName(from: declaration))
    let categoryBody = customCategory ?? typeNameLiteral
    // Same reasoning as `@Loggable`: no bundle-identifier fallback, because that
    // would name `Bundle` in an expansion that lands in the caller's file.
    let subsystemBody = customSubsystem ?? typeNameLiteral
    let availability = SignpostableMacro.signposterAvailability

    var members: [DeclSyntax] = [
        "\(raw: accessPrefix)nonisolated static var signpostCategory: String { \(raw: categoryBody) }",
        "\(raw: accessPrefix)nonisolated static var signpostSubsystem: String { \(raw: subsystemBody) }",
        "\(raw: accessPrefix)nonisolated static let _signpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)",
        """
        \(raw: availability)
        \(raw: accessPrefix)nonisolated static let signposter = os.OSSignposter(logHandle: _signpostLog)
        """,
        """
        \(raw: availability)
        \(raw: accessPrefix)nonisolated var signposter: os.OSSignposter { Self.signposter }
        """,
    ]
    members.append(contentsOf: buildSignpostCategoryAccessorMembers(accessPrefix: accessPrefix))
    members.append(contentsOf: buildSignpostIdentifierFactories(accessPrefix: accessPrefix))
    return members
}

/// The per-category accessors backing `#signpost(… category: .name …)`.
/// Categories are values of the library's `LogCategory` struct — the same ones
/// `@Loggable` uses, since the system models signposts as riding on logging's
/// subsystem/category pairs. The subsystem stays the annotated type's own.
private func buildSignpostCategoryAccessorMembers(accessPrefix: String) -> [DeclSyntax] {
    let availability = SignpostableMacro.signposterAvailability
    return [
        """
        \(raw: accessPrefix)nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
            SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
        }
        """,
        """
        \(raw: availability)
        \(raw: accessPrefix)nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
            SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
        }
        """,
    ]
}

/// Signpost ID factories.
///
/// These go through `OSSignpostID(log:)` rather than
/// `OSSignposter.makeSignpostID()` so they need no `@available` gate — the
/// initializer has been there since macOS 10.14, and both routes produce an
/// identifier unique within the process.
private func buildSignpostIdentifierFactories(accessPrefix: String) -> [DeclSyntax] {
    return [
        """
        \(raw: accessPrefix)nonisolated static func makeSignpostID() -> os.OSSignpostID {
            os.OSSignpostID(log: _signpostLog)
        }
        """,
        """
        \(raw: accessPrefix)nonisolated static func makeSignpostID(from object: AnyObject) -> os.OSSignpostID {
            os.OSSignpostID(log: _signpostLog, object: object)
        }
        """,
    ]
}

// MARK: - Protocol requirements

/// Protocol-internal declarations carry no access modifier, no `nonisolated`,
/// and no body — they're plain requirements conforming types may satisfy with
/// their own storage or computed properties.
private func buildSignpostProtocolRequirements() -> [DeclSyntax] {
    let availability = SignpostableMacro.signposterAvailability
    return [
        "static var signpostCategory: String { get }",
        "static var signpostSubsystem: String { get }",
        "static var _signpostLog: os.OSLog { get }",
        """
        \(raw: availability)
        static var signposter: os.OSSignposter { get }
        """,
        """
        \(raw: availability)
        var signposter: os.OSSignposter { get }
        """,
    ]
}

// MARK: - Protocol default implementations

/// The default-implementation extension. Its access modifier comes from the
/// protocol's own access level so conforming types can pick up the defaults
/// without re-implementing every member.
private func buildSignpostProtocolDefaultImplementations(
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
    let availability = SignpostableMacro.signposterAvailability

    var members: [DeclSyntax] = [
        "\(raw: accessPrefix)nonisolated static var signpostCategory: String { \(raw: categoryBody) }",
        "\(raw: accessPrefix)nonisolated static var signpostSubsystem: String { \(raw: subsystemBody) }",
        """
        \(raw: accessPrefix)nonisolated static var _signpostLog: os.OSLog {
            SignpostableMacro._sharedSignpostLog(for: self, subsystem: signpostSubsystem, category: signpostCategory)
        }
        """,
        """
        \(raw: availability)
        \(raw: accessPrefix)nonisolated static var signposter: os.OSSignposter {
            SignpostableMacro._sharedSignposter(for: self, subsystem: signpostSubsystem, category: signpostCategory)
        }
        """,
        """
        \(raw: availability)
        \(raw: accessPrefix)nonisolated var signposter: os.OSSignposter { Self.signposter }
        """,
    ]
    members.append(contentsOf: buildSignpostCategoryAccessorMembers(accessPrefix: accessPrefix))
    members.append(contentsOf: buildSignpostIdentifierFactories(accessPrefix: accessPrefix))
    return members
}
