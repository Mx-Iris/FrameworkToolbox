import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@_StoragePublisherProjection` — accessor macro used inside the expansions of
/// `@Keychain` and `@UserDefault`.
///
/// Turns `var $name = <prototype>.publisher.eraseToAnyPublisher()` into a
/// computed property returning `_name.publisher.eraseToAnyPublisher()`, whose
/// type the compiler infers from the initial value.
///
/// A computed property has to spell its type before any macro runs, and for a
/// storage property declared without a type annotation there is nothing to
/// spell. An initialized `var` needs no type, and once this macro adds a getter
/// the compiler keeps the initial value only to infer the property's type from:
/// it is type-checked but never runs. SwiftUI's `@Entry` generates its key's
/// default value the same way. Two rules shape what the initial value can be:
///
/// - It is checked as a property initializer, where `self` is not available
///   yet, so on an instance property it may not touch the storage. The
///   generating macro writes a prototype of the same type instead — a fresh
///   storage built from the same arguments, which costs nothing because it is
///   never evaluated — and the getter, which runs with `self`, reads the real
///   storage. Which storage that is follows from the projection's own name.
/// - A property may not take its inferred type from another declaration's
///   `some` result, and `publisher` is declared `some Publisher<Value, Never>`.
///   Erasing to `AnyPublisher` gives a type the property can have, and it keeps
///   the subject's `send` hidden just as the opaque type does.
public enum StoragePublisherProjectionMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self),
              variable.bindings.count == 1,
              let binding = variable.bindings.first,
              binding.initializer != nil,
              let projectionName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              projectionName.hasPrefix("$")
        else {
            context.diagnose(Diagnostic(node: node, message: StoragePublisherProjectionDiagnostic.requiresProjection))
            return []
        }
        let storageName = "_" + projectionName.dropFirst()
        return ["get { \(raw: storageName).publisher.eraseToAnyPublisher() }"]
    }
}

enum StoragePublisherProjectionDiagnostic: String, DiagnosticMessage {
    case requiresProjection

    var message: String {
        "'@_StoragePublisherProjection' must be applied to a single 'var $name' with an initial value"
    }

    var diagnosticID: MessageID {
        MessageID(domain: "StoragePublisherProjectionMacro", id: rawValue)
    }

    var severity: DiagnosticSeverity { .error }
}
