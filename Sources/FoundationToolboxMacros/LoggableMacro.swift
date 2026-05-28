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
        let style = resolveConcreteStyle(for: declaration)
        return buildConcreteMembers(node: node, declaration: declaration, style: style)
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

private enum ConcreteStyle {
    /// `static let` stored properties, `Bundle.main` for subsystem.
    case structValue
    /// `static let` stored properties, `Bundle(for: self)` for subsystem.
    case classValue
    /// `static let` stored properties, `Bundle.main` for subsystem.
    case enumOrActor
}

private func resolveConcreteStyle(for declaration: some DeclGroupSyntax) -> ConcreteStyle {
    if declaration.is(ClassDeclSyntax.self) {
        return .classValue
    } else if declaration.is(StructDeclSyntax.self) {
        return .structValue
    }
    return .enumOrActor
}

private func buildConcreteMembers(
    node: AttributeSyntax,
    declaration: some DeclGroupSyntax,
    style: ConcreteStyle
) -> [DeclSyntax] {
    let accessLevel = extractAccessLevel(from: node)
    let accessPrefix = accessLevel == "internal" ? "" : "\(accessLevel) "
    let customSubsystem = extractStringLiteral(labeled: "subsystem", from: node)
    let customCategory = extractStringLiteral(labeled: "category", from: node)

    let typeNameLiteral = quoteString(staticTypeName(from: declaration))
    let categoryBody = customCategory ?? typeNameLiteral
    let subsystemBody = concreteSubsystemBody(
        style: style,
        typeNameLiteral: typeNameLiteral,
        customSubsystem: customSubsystem
    )

    return [
        "\(raw: accessPrefix)nonisolated static var category: String { \(raw: categoryBody) }",
        "\(raw: accessPrefix)nonisolated static var subsystem: String { \(raw: subsystemBody) }",
        "\(raw: accessPrefix)nonisolated static let _osLog = OSLog(subsystem: subsystem, category: category)",
        """
        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        \(raw: accessPrefix)nonisolated static let logger = os.Logger(subsystem: subsystem, category: category)
        """,
        """
        @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
        \(raw: accessPrefix)nonisolated var logger: os.Logger { Self.logger }
        """,
    ]
}

private func concreteSubsystemBody(
    style: ConcreteStyle,
    typeNameLiteral: String,
    customSubsystem: String?
) -> String {
    if let customSubsystem {
        return customSubsystem
    }
    switch style {
    case .classValue:
        return "Bundle(for: self).bundleIdentifier ?? \(typeNameLiteral)"
    case .structValue, .enumOrActor:
        return "Bundle.main.bundleIdentifier ?? \(typeNameLiteral)"
    }
}

// MARK: - Protocol requirements

/// Protocol-internal declarations carry no access modifier, no `nonisolated`,
/// and no body — they're plain protocol requirements that conforming types may
/// satisfy with their own storage / computed properties.
private func buildProtocolRequirements() -> [DeclSyntax] {
    return [
        "static var category: String { get }",
        "static var subsystem: String { get }",
        "static var _osLog: OSLog { get }",
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
    let subsystemBody = customSubsystem ?? "Bundle.main.bundleIdentifier ?? \(typeNameExpression)"

    return [
        "\(raw: accessPrefix)nonisolated static var category: String { \(raw: categoryBody) }",
        "\(raw: accessPrefix)nonisolated static var subsystem: String { \(raw: subsystemBody) }",
        """
        \(raw: accessPrefix)nonisolated static var _osLog: OSLog {
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
}

// MARK: - Helpers

private func indent(_ source: String, by spaces: Int) -> String {
    let prefix = String(repeating: " ", count: spaces)
    return source
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in line.isEmpty ? String(line) : prefix + line }
        .joined(separator: "\n")
}

private func staticTypeName(from declaration: some DeclGroupSyntax) -> String {
    if let structDecl = declaration.as(StructDeclSyntax.self) {
        return structDecl.name.trimmedDescription
    } else if let classDecl = declaration.as(ClassDeclSyntax.self) {
        return classDecl.name.trimmedDescription
    } else if let enumDecl = declaration.as(EnumDeclSyntax.self) {
        return enumDecl.name.trimmedDescription
    } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
        return actorDecl.name.trimmedDescription
    } else if let protocolDecl = declaration.as(ProtocolDeclSyntax.self) {
        return protocolDecl.name.trimmedDescription
    }
    return "Unknown"
}

private func quoteString(_ value: String) -> String {
    "\"\(value)\""
}

/// Extracts access level from the macro attribute, defaulting to "private".
/// Only considers the first positional (unlabeled) argument.
private func extractAccessLevel(from node: AttributeSyntax) -> String {
    guard let arguments = node.arguments,
          case let .argumentList(argList) = arguments,
          let firstArg = argList.first,
          firstArg.label == nil,
          let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self) else {
        return "private"
    }
    return memberAccess.declName.baseName.text
}

/// Reads the access modifier off the declaration itself (e.g. `public protocol P`).
/// Falls back to `"internal"` when none is present.
private func protocolAccessLevel(from declaration: some DeclGroupSyntax) -> String {
    for modifier in declaration.modifiers {
        let text = modifier.name.text
        switch text {
        case "open", "public", "package", "internal", "fileprivate", "private":
            return text
        default:
            continue
        }
    }
    return "internal"
}

/// Extracts a string literal argument by its label, returning the raw source form (including quotes).
/// Returns `nil` when the label is missing or the argument is not a string literal.
private func extractStringLiteral(labeled label: String, from node: AttributeSyntax) -> String? {
    guard let arguments = node.arguments,
          case let .argumentList(argList) = arguments else {
        return nil
    }
    for argument in argList {
        if argument.label?.text == label,
           let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
            return stringLiteral.trimmedDescription
        }
    }
    return nil
}

/// Extracts a boolean literal argument by its label.
/// Returns `nil` when the label is missing or the value is not a boolean literal.
private func extractBoolLiteral(labeled label: String, from node: AttributeSyntax) -> Bool? {
    guard let arguments = node.arguments,
          case let .argumentList(argList) = arguments else {
        return nil
    }
    for argument in argList {
        guard argument.label?.text == label,
              let booleanLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) else {
            continue
        }
        return booleanLiteral.literal.text == "true"
    }
    return nil
}
