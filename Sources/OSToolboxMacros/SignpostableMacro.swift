import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Implementation of `@Signpostable`. Structurally the same as `LoggableMacro` —
/// same attribute grammar, same concrete/protocol split, same access-level
/// handling, same three shapes for the generated handles — differing only in
/// which members it emits.
public struct SignpostableMacro: MemberMacro, ExtensionMacro {

    /// The floor for `OSSignposter` and everything reachable through it.
    /// Three OS versions above this package's own floor, which is the whole
    /// reason the generated code carries a legacy path at all.
    static let signposterAvailability = "@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)"

    /// The static properties the `subsystem:` and `category:` arguments end up
    /// in. Inside their getters a bare name resolves to these first, so an
    /// argument naming one of them is rejected rather than transplanted.
    static let generatedNameProperties: Set<String> = ["signpostCategory", "signpostSubsystem"]

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
        return buildSignpostConcreteMembers(
            node: node,
            declaration: declaration,
            // A generic context forbids static stored properties, so the live
            // handles have to come from the runtime cache instead.
            usesRuntimeCache: isInGenericContext(
                declaration: declaration,
                lexicalContext: context.lexicalContext
            ),
            context: context
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

        let members = buildSignpostProtocolDefaultImplementations(node: node, declaration: declaration, context: context)
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

/// `@Signpostable`'s reading of a `subsystem:` or `category:` argument.
private func extractSignpostableNameExpression(
    labeled label: String,
    from node: AttributeSyntax,
    in context: some MacroExpansionContext
) -> String? {
    extractNameExpression(
        labeled: label,
        from: node,
        macroName: "Signpostable",
        generatedNames: SignpostableMacro.generatedNameProperties,
        in: context
    )
}

private func buildSignpostConcreteMembers(
    node: AttributeSyntax,
    declaration: some DeclGroupSyntax,
    usesRuntimeCache: Bool,
    context: some MacroExpansionContext
) -> [DeclSyntax] {
    let accessLevel = extractAccessLevel(from: node)
    let accessPrefix = accessLevel == "internal" ? "" : "\(accessLevel) "
    let customSubsystem = extractSignpostableNameExpression(labeled: "subsystem", from: node, in: context)
    let customCategory = extractSignpostableNameExpression(labeled: "category", from: node, in: context)
    let enablement = extractEnablement(from: node)

    let typeNameLiteral = quoteString(staticTypeName(from: declaration))
    let categoryBody = customCategory ?? typeNameLiteral
    // Same reasoning as `@Loggable`: no bundle-identifier fallback, because that
    // would name `Bundle` in an expansion that lands in the caller's file.
    let subsystemBody = customSubsystem ?? typeNameLiteral
    let availability = SignpostableMacro.signposterAvailability

    var members: [DeclSyntax] = [
        "\(raw: accessPrefix)nonisolated static var signpostCategory: String { \(raw: categoryBody) }",
        "\(raw: accessPrefix)nonisolated static var signpostSubsystem: String { \(raw: subsystemBody) }",
    ]
    members.append(contentsOf: buildSignpostHandleMembers(
        accessPrefix: accessPrefix,
        enablement: enablement,
        usesRuntimeCache: usesRuntimeCache
    ))
    members.append("""
    \(raw: availability)
    \(raw: accessPrefix)nonisolated var signposter: os.OSSignposter { Self.signposter }
    """)
    members.append(contentsOf: buildSignpostCategoryAccessorMembers(
        accessPrefix: accessPrefix,
        enablement: enablement
    ))
    members.append(contentsOf: buildSignpostIdentifierFactories(accessPrefix: accessPrefix))
    return members
}

/// The type-level `_signpostLog` / `signposter` pair, in whichever of three
/// shapes the attribute and the surrounding context call for — the same three
/// `@Loggable` uses, for the same reasons.
///
/// - `isEnabled: false` — `.disabled` constants, no storage emitted.
/// - `usesRuntimeCache` — a generic context or a protocol's default
///   implementations, where no static stored property is allowed.
/// - otherwise — the live handle cached in a `static let`.
private func buildSignpostHandleMembers(
    accessPrefix: String,
    enablement: EnablementConfiguration,
    usesRuntimeCache: Bool
) -> [DeclSyntax] {
    let availability = SignpostableMacro.signposterAvailability
    let condition = enablement.condition(
        switchEntryPoint: "SignpostableMacro._isEnabled",
        categoryExpression: "signpostCategory"
    )

    guard let condition else {
        return [
            "\(raw: accessPrefix)nonisolated static var _signpostLog: os.OSLog { .disabled }",
            """
            \(raw: availability)
            \(raw: accessPrefix)nonisolated static var signposter: os.OSSignposter { .disabled }
            """,
        ]
    }

    let liveSignpostLogExpression = usesRuntimeCache
        ? "SignpostableMacro._sharedSignpostLog(for: self, subsystem: signpostSubsystem, category: signpostCategory)"
        : "_enabledSignpostLog"
    let liveSignposterExpression = usesRuntimeCache
        ? "SignpostableMacro._sharedSignposter(for: self, subsystem: signpostSubsystem, category: signpostCategory)"
        : "_enabledSignposter"

    var members: [DeclSyntax] = []
    if enablement.needsEnabledHandleStorage, !usesRuntimeCache {
        members.append(
            "\(raw: accessPrefix)nonisolated static let _enabledSignpostLog = os.OSLog(subsystem: signpostSubsystem, category: signpostCategory)"
        )
    }
    members.append("""
    \(raw: accessPrefix)nonisolated static var _signpostLog: os.OSLog {
        guard \(raw: condition) else {
            return .disabled
        }
        return \(raw: liveSignpostLogExpression)
    }
    """)
    if enablement.needsEnabledHandleStorage, !usesRuntimeCache {
        members.append("""
        \(raw: availability)
        \(raw: accessPrefix)nonisolated static let _enabledSignposter = os.OSSignposter(logHandle: _enabledSignpostLog)
        """)
    }
    members.append("""
    \(raw: availability)
    \(raw: accessPrefix)nonisolated static var signposter: os.OSSignposter {
        guard \(raw: condition) else {
            return .disabled
        }
        return \(raw: liveSignposterExpression)
    }
    """)
    return members
}

/// The per-category accessors backing `#signpost(… category: .name …)`.
/// Categories are values of the library's `LogCategory` struct — the same ones
/// `@Loggable` uses, since the system models signposts as riding on logging's
/// subsystem/category pairs. The subsystem stays the annotated type's own.
///
/// The switches are consulted against the call site's category, which is what
/// makes `SignpostingControl.setEnabled(false, for:)` reach here.
private func buildSignpostCategoryAccessorMembers(
    accessPrefix: String,
    enablement: EnablementConfiguration
) -> [DeclSyntax] {
    let availability = SignpostableMacro.signposterAvailability
    let condition = enablement.condition(
        switchEntryPoint: "SignpostableMacro._isEnabled",
        categoryExpression: "category.name"
    )

    guard let condition else {
        return [
            """
            \(raw: accessPrefix)nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
                .disabled
            }
            """,
            """
            \(raw: availability)
            \(raw: accessPrefix)nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
                .disabled
            }
            """,
        ]
    }

    return [
        """
        \(raw: accessPrefix)nonisolated static func _signpostLog(for category: OSToolbox.LogCategory) -> os.OSLog {
            guard \(raw: condition) else {
                return .disabled
            }
            return SignpostableMacro._sharedSignpostLog(subsystem: signpostSubsystem, category: category.name)
        }
        """,
        """
        \(raw: availability)
        \(raw: accessPrefix)nonisolated static func signposter(for category: OSToolbox.LogCategory) -> os.OSSignposter {
            guard \(raw: condition) else {
                return .disabled
            }
            return SignpostableMacro._sharedSignposter(subsystem: signpostSubsystem, category: category.name)
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
///
/// They read `_signpostLog`, so while signposting is off they hand back the ID
/// a disabled handle generates. Harmless: nothing is emitted under it either.
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

/// Protocol-internal declarations carry no access modifier and no body — they're
/// plain requirements conforming types may satisfy with their own storage or
/// computed properties.
///
/// They are `nonisolated`, for the reason given on `@Loggable`'s requirements:
/// the default implementations read them from nonisolated code, and under a
/// `MainActor` default isolation an unmarked requirement is main-actor isolated.
///
/// As with `@Loggable`, the `isEnabled:` switch adds no requirement here — it is
/// resolved inside the default implementations, so existing conformers keep
/// compiling unchanged.
private func buildSignpostProtocolRequirements() -> [DeclSyntax] {
    let availability = SignpostableMacro.signposterAvailability
    return [
        "nonisolated static var signpostCategory: String { get }",
        "nonisolated static var signpostSubsystem: String { get }",
        "nonisolated static var _signpostLog: os.OSLog { get }",
        """
        \(raw: availability)
        nonisolated static var signposter: os.OSSignposter { get }
        """,
        """
        \(raw: availability)
        nonisolated var signposter: os.OSSignposter { get }
        """,
    ]
}

// MARK: - Protocol default implementations

/// The default-implementation extension. Its access modifier comes from the
/// protocol's own access level so conforming types can pick up the defaults
/// without re-implementing every member.
private func buildSignpostProtocolDefaultImplementations(
    node: AttributeSyntax,
    declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext
) -> [DeclSyntax] {
    let accessLevel = protocolAccessLevel(from: declaration)
    let accessPrefix = accessLevel == "internal" ? "" : "\(accessLevel) "
    let customSubsystem = extractSignpostableNameExpression(labeled: "subsystem", from: node, in: context)
    let customCategory = extractSignpostableNameExpression(labeled: "category", from: node, in: context)
    let enablement = extractEnablement(from: node)

    let typeNameExpression = "String(describing: self)"
    let categoryBody = customCategory ?? typeNameExpression
    let subsystemBody = customSubsystem ?? typeNameExpression
    let availability = SignpostableMacro.signposterAvailability

    var members: [DeclSyntax] = [
        "\(raw: accessPrefix)nonisolated static var signpostCategory: String { \(raw: categoryBody) }",
        "\(raw: accessPrefix)nonisolated static var signpostSubsystem: String { \(raw: subsystemBody) }",
    ]
    members.append(contentsOf: buildSignpostHandleMembers(
        accessPrefix: accessPrefix,
        enablement: enablement,
        usesRuntimeCache: true
    ))
    members.append("""
    \(raw: availability)
    \(raw: accessPrefix)nonisolated var signposter: os.OSSignposter { Self.signposter }
    """)
    members.append(contentsOf: buildSignpostCategoryAccessorMembers(
        accessPrefix: accessPrefix,
        enablement: enablement
    ))
    members.append(contentsOf: buildSignpostIdentifierFactories(accessPrefix: accessPrefix))
    return members
}
