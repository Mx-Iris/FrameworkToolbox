import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import MacroToolbox

public enum KeychainMacro {}

extension KeychainMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let info = try LockPropertyParser.parse(declaration, macroName: "Keychain")
        if info.isWeak {
            throw LockPropertyError.weakNotSupported("Keychain")
        }
        return [
            """
            get {
                \(raw: info.storageName).get()
            }
            """,
            """
            set {
                \(raw: info.storageName).set(newValue)
            }
            """,
        ]
    }
}

extension KeychainMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let info = try LockPropertyParser.parse(declaration, macroName: "Keychain")
        if info.isWeak {
            throw LockPropertyError.weakNotSupported("Keychain")
        }

        guard let argumentList = node.arguments?.as(LabeledExprListSyntax.self),
              !argumentList.isEmpty
        else {
            throw KeychainMacroError.missingArguments
        }

        let staticKeyword = info.isStatic ? "static " : ""

        // Splice the user-supplied arguments verbatim; the macro's parameter
        // labels match `KeychainStorage`'s initializer one-to-one, so this
        // preserves any defaults the user omitted. Each element already carries
        // its own trailing comma in `description`, so we use the list's
        // description directly rather than rejoining.
        let argumentsText = argumentList.description.trimmingCharacters(in: .whitespacesAndNewlines)

        // Trim trivia so the generated text doesn't carry trailing whitespace
        // between the type and the closing `>`.
        let typeText = info.type.trimmedDescription

        // Reference types via their owning modules so user code that already
        // declares a same-named type doesn't accidentally shadow the macro's
        // expansion. `FoundationToolbox` re-exports Combine via @_exported
        // import, so `Combine.Publisher` is resolvable wherever the macro is
        // usable.
        let storageDecl: DeclSyntax = """
            private \(raw: staticKeyword)let \(raw: info.storageName) = FoundationToolbox.KeychainStorage<\(raw: typeText)>(
                \(raw: argumentsText),
                defaultValue: \(info.initialValue)
            )
            """

        // Match the access level of the original property so the publisher
        // is reachable from anywhere the property itself is reachable.
        let accessModifiers = Self.accessLevelModifiers(of: declaration)

        let publisherDecl: DeclSyntax = """
            \(raw: accessModifiers)\(raw: staticKeyword)var $\(raw: info.propertyName): some Combine.Publisher<\(raw: typeText), Never> {
                \(raw: info.storageName).publisher
            }
            """

        return [storageDecl, publisherDecl]
    }

    private static func accessLevelModifiers(of declaration: some DeclSyntaxProtocol) -> String {
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else { return "" }
        let accessKeywords: Set<TokenKind> = [
            .keyword(.public),
            .keyword(.internal),
            .keyword(.fileprivate),
            .keyword(.private),
            .keyword(.open),
            .keyword(.package),
        ]
        // Drop modifiers that carry a `(set)` detail (e.g. `private(set)`);
        // the projection is read-only so only the read access level matters,
        // and projecting `private(set)` would emit two access modifiers on a
        // single declaration which Swift rejects.
        let modifiers = varDecl.modifiers
            .filter { $0.detail == nil && accessKeywords.contains($0.name.tokenKind) }
            .map { "\($0.name.text) " }
            .joined()
        return modifiers
    }
}

public enum KeychainMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case missingArguments

    public var description: String {
        switch self {
        case .missingArguments:
            return "@Keychain requires `key:` and `service:` arguments."
        }
    }

    public var message: String { description }

    public var diagnosticID: MessageID {
        MessageID(domain: "KeychainMacro", id: "missingArguments")
    }

    public var severity: DiagnosticSeverity { .error }
}
