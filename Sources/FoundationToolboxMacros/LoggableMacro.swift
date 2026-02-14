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
        
        // Build access modifier prefix (empty for internal)
        let accessPrefix = accessLevel == "internal" ? "" : "\(accessLevel) "

        let subsystemBody: String = isClass
            ? "Bundle(for: self).bundleIdentifier ?? \(quoteString(typeName))"
            : "Bundle.main.bundleIdentifier ?? \(quoteString(typeName))"

        return [
            "\(raw: accessPrefix)static var category: String { \(literal: typeName) }",
            "\(raw: accessPrefix)static var subsystem: String { \(raw: subsystemBody) }",
            "\(raw: accessPrefix)static let _osLog = OSLog(subsystem: subsystem, category: category)",
            """
            @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
            \(raw: accessPrefix)static let logger = os.Logger(subsystem: subsystem, category: category)
            """,
            """
            @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
            \(raw: accessPrefix)var logger: os.Logger { Self.logger }
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

/// Extracts access level from the macro attribute, defaulting to "internal".
private func extractAccessLevel(from node: AttributeSyntax) -> String {
    // Check if there are arguments
    guard let arguments = node.arguments,
          case let .argumentList(argList) = arguments,
          let firstArg = argList.first else {
        return "internal"
    }

    // Parse the member access expression (e.g., `.private`, `.public`)
    if let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self) {
        return memberAccess.declName.baseName.text
    }

    return "internal"
}
