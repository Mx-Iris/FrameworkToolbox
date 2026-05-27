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
        // Protocol declarations only emit a sibling extension, not in-protocol members.
        if declaration.is(ProtocolDeclSyntax.self) {
            return []
        }

        let style = resolveGenerationStyle(for: declaration)
        return buildMembers(node: node, declaration: declaration, style: style)
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Only protocols receive a sibling extension; everything else uses MemberMacro alone.
        guard declaration.is(ProtocolDeclSyntax.self) else {
            return []
        }

        let members = buildMembers(node: node, declaration: declaration, style: .protocolDefault)
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

private func indent(_ source: String, by spaces: Int) -> String {
    let prefix = String(repeating: " ", count: spaces)
    return source
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in line.isEmpty ? String(line) : prefix + line }
        .joined(separator: "\n")
}

// MARK: - Generation style

private enum GenerationStyle {
    /// Concrete struct: `static let` stored properties, `Bundle.main` for subsystem.
    case structValue
    /// Concrete class: `static let` stored properties, `Bundle(for: self)` for subsystem.
    case classValue
    /// Concrete enum / actor: `static let` stored properties, `Bundle.main` for subsystem.
    case enumOrActor
    /// Protocol's sibling extension: computed properties backed by the shared per-type cache.
    case protocolDefault
}

private func resolveGenerationStyle(for declaration: some DeclGroupSyntax) -> GenerationStyle {
    if declaration.is(StructDeclSyntax.self) {
        return .structValue
    } else if declaration.is(ClassDeclSyntax.self) {
        return .classValue
    } else if declaration.is(EnumDeclSyntax.self) || declaration.is(ActorDeclSyntax.self) {
        return .enumOrActor
    }
    return .enumOrActor
}

// MARK: - Member generation

private func buildMembers(
    node: AttributeSyntax,
    declaration: some DeclGroupSyntax,
    style: GenerationStyle
) -> [DeclSyntax] {
    let accessLevel = extractAccessLevel(from: node)
    let accessPrefix = accessLevel == "internal" ? "" : "\(accessLevel) "
    let customSubsystem = extractStringLiteral(labeled: "subsystem", from: node)
    let customCategory = extractStringLiteral(labeled: "category", from: node)

    let typeNameExpression = typeNameExpression(for: declaration, style: style)
    let categoryBody: String = customCategory ?? typeNameExpression
    let subsystemBody = subsystemBody(
        style: style,
        typeNameExpression: typeNameExpression,
        customSubsystem: customSubsystem
    )

    switch style {
    case .structValue, .classValue, .enumOrActor:
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

    case .protocolDefault:
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
}

// MARK: - Helpers

private func typeNameExpression(for declaration: some DeclGroupSyntax, style: GenerationStyle) -> String {
    switch style {
    case .structValue, .classValue, .enumOrActor:
        return quoteString(staticTypeName(from: declaration))
    case .protocolDefault:
        // Self is determined at runtime — defer to String(describing: self).
        return "String(describing: self)"
    }
}

private func subsystemBody(
    style: GenerationStyle,
    typeNameExpression: String,
    customSubsystem: String?
) -> String {
    if let customSubsystem {
        return customSubsystem
    }
    switch style {
    case .classValue:
        return "Bundle(for: self).bundleIdentifier ?? \(typeNameExpression)"
    case .structValue, .enumOrActor, .protocolDefault:
        return "Bundle.main.bundleIdentifier ?? \(typeNameExpression)"
    }
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
