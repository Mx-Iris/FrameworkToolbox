import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Lock Macro Protocol

public protocol LockMacroProtocol: PeerMacro, AccessorMacro {
    static var macroName: String { get }
    static func makeStorageDecl(for info: LockPropertyInfo) -> DeclSyntax
    static func makeGetter(for info: LockPropertyInfo) -> AccessorDeclSyntax
    static func makeSetter(for info: LockPropertyInfo) -> AccessorDeclSyntax
    static func makeModify(for info: LockPropertyInfo) -> AccessorDeclSyntax?
}

// MARK: - Default Implementations

extension LockMacroProtocol {
    public static func makeModify(for info: LockPropertyInfo) -> AccessorDeclSyntax? {
        nil
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let info = try LockPropertyParser.parse(declaration, macroName: macroName)
        return [makeStorageDecl(for: info)]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let info = try LockPropertyParser.parse(declaration, macroName: macroName)
        var accessors: [AccessorDeclSyntax] = [makeGetter(for: info), makeSetter(for: info)]
        if let modify = makeModify(for: info) {
            accessors.append(modify)
        }
        return accessors
    }
}
