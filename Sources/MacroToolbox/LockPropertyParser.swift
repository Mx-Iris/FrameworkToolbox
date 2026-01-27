import Foundation
import SwiftSyntax
import SwiftDiagnostics

// MARK: - Parsed Property Info

public struct LockPropertyInfo {
    public let propertyName: String
    public let storageName: String
    public let type: TypeSyntax
    public let baseType: String
    public let initialValue: ExprSyntax
    public let isWeak: Bool
    public let isOptional: Bool
    public let isImplicitlyUnwrappedOptional: Bool
}

// MARK: - Parser

public enum LockPropertyParser {
    public static func parse(
        _ declaration: some DeclSyntaxProtocol,
        macroName: String
    ) throws -> LockPropertyInfo {
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            throw LockPropertyError.requiresVariable(macroName)
        }

        guard let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            throw LockPropertyError.invalidPropertyBinding(macroName)
        }

        if binding.accessorBlock != nil {
            throw LockPropertyError.cannotHaveExistingAccessors(macroName)
        }

        guard let type = binding.typeAnnotation?.type else {
            throw LockPropertyError.requiresExplicitType(macroName)
        }

        let isWeak = varDecl.modifiers.contains { $0.name.tokenKind == .keyword(.weak) }
        let isOptional = Self.isOptionalType(type)
        let isIUO = type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)

        if isWeak && !isOptional {
            throw LockPropertyError.weakRequiresOptional(macroName)
        }

        let initialValue: ExprSyntax
        if let initializer = binding.initializer {
            initialValue = initializer.value
        } else if isWeak || isOptional {
            initialValue = ExprSyntax("nil")
        } else {
            throw LockPropertyError.requiresInitialValue(macroName)
        }

        let baseType = Self.extractBaseType(from: type)

        return LockPropertyInfo(
            propertyName: pattern.identifier.text,
            storageName: "_\(pattern.identifier.text)",
            type: type,
            baseType: baseType,
            initialValue: initialValue,
            isWeak: isWeak,
            isOptional: isOptional,
            isImplicitlyUnwrappedOptional: isIUO
        )
    }

    // MARK: - Private Helpers

    private static func isOptionalType(_ type: TypeSyntax) -> Bool {
        if type.is(OptionalTypeSyntax.self) {
            return true
        }
        if type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return true
        }
        if let genericType = type.as(IdentifierTypeSyntax.self),
           genericType.name.text == "Optional" {
            return true
        }
        return false
    }

    private static func extractBaseType(from type: TypeSyntax) -> String {
        if let optionalType = type.as(OptionalTypeSyntax.self) {
            return optionalType.wrappedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let iuo = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return iuo.wrappedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let genericType = type.as(IdentifierTypeSyntax.self),
           genericType.name.text == "Optional",
           let genericArgs = genericType.genericArgumentClause?.arguments.first {
            return genericArgs.argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return type.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Error Type

public enum LockPropertyError: Error, CustomStringConvertible, DiagnosticMessage {
    case requiresVariable(String)
    case requiresInitialValue(String)
    case requiresExplicitType(String)
    case invalidPropertyBinding(String)
    case cannotHaveExistingAccessors(String)
    case weakRequiresOptional(String)

    public var description: String {
        switch self {
        case .requiresVariable(let name):
            return "@\(name) can only be applied to a variable declaration."
        case .requiresInitialValue(let name):
            return "@\(name) requires the property to have an initial value."
        case .requiresExplicitType(let name):
            return "@\(name) requires an explicit type annotation."
        case .invalidPropertyBinding(let name):
            return "@\(name) requires a valid property binding."
        case .cannotHaveExistingAccessors(let name):
            return "@\(name) cannot be applied to computed properties or properties with existing accessors."
        case .weakRequiresOptional(let name):
            return "@\(name) on weak properties requires the type to be optional."
        }
    }

    public var message: String { description }

    public var diagnosticID: MessageID {
        let id: String
        switch self {
        case .requiresVariable: id = "requiresVariable"
        case .requiresInitialValue: id = "requiresInitialValue"
        case .requiresExplicitType: id = "requiresExplicitType"
        case .invalidPropertyBinding: id = "invalidPropertyBinding"
        case .cannotHaveExistingAccessors: id = "cannotHaveExistingAccessors"
        case .weakRequiresOptional: id = "weakRequiresOptional"
        }
        return MessageID(domain: "LockPropertyError", id: id)
    }

    public var severity: DiagnosticSeverity { .error }
}
