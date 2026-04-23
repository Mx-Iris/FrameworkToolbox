import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct LoggableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let typeName = extractTypeName(from: declaration)
        let isClass = declaration.is(ClassDeclSyntax.self)
        let accessLevel = extractAccessLevel(from: node)
        let customSubsystem = extractStringLiteral(labeled: "subsystem", from: node)
        let customCategory = extractStringLiteral(labeled: "category", from: node)

        // Build access modifier prefix (empty for internal)
        let accessPrefix = accessLevel == "internal" ? "" : "\(accessLevel) "

        let categoryBody: String = customCategory ?? quoteString(typeName)

        let subsystemBody: String
        if let customSubsystem {
            subsystemBody = customSubsystem
        } else if isClass {
            subsystemBody = "Bundle(for: self).bundleIdentifier ?? \(quoteString(typeName))"
        } else {
            subsystemBody = "Bundle.main.bundleIdentifier ?? \(quoteString(typeName))"
        }

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
}

private func extractTypeName(from declaration: some DeclGroupSyntax) -> String {
    if let structDecl = declaration.as(StructDeclSyntax.self) {
        return structDecl.name.trimmedDescription
    } else if let classDecl = declaration.as(ClassDeclSyntax.self) {
        return classDecl.name.trimmedDescription
    } else if let enumDecl = declaration.as(EnumDeclSyntax.self) {
        return enumDecl.name.trimmedDescription
    } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
        return actorDecl.name.trimmedDescription
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
