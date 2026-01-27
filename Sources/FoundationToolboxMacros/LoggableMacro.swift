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

        let subsystemBody: String = isClass
            ? "Bundle(for: self).bundleIdentifier ?? \(quoteString(typeName))"
            : "Bundle.main.bundleIdentifier ?? \(quoteString(typeName))"

        return [
            "static let _loggableSwiftLogger = Logging.Logger(label: \(literal: typeName))",
            "static var category: String { \(literal: typeName) }",
            "static var subsystem: String { \(raw: subsystemBody) }",
            """
            @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
            static let logger = os.Logger(subsystem: subsystem, category: category)
            """,
            """
            @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
            var logger: os.Logger { Self.logger }
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
