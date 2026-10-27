import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftDiagnostics

// MARK: - Parsed Property Info

public struct LockPropertyInfo {
    public let propertyName: String
    public let storageName: String
    /// The property's type as written, or `nil` when the declaration leaves it
    /// to be inferred from ``initialValue``.
    ///
    /// The macros using this are accessor macros, so once they add a getter the
    /// compiler keeps the initial value only to infer the property's type from
    /// (it never runs it). Generated code then has to avoid naming the type: a
    /// stored property infers its own (`Mutex(initialValue)`), and anything
    /// computed goes through an accessor macro that takes its type from an
    /// initializer the same way.
    public let type: TypeSyntax?
    /// ``type`` with any optionality stripped, or `nil` along with it.
    public let baseType: String?
    public let initialValue: ExprSyntax
    public let isWeak: Bool
    public let isOptional: Bool
    public let isImplicitlyUnwrappedOptional: Bool
    public let isStatic: Bool
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

        // The macros all need a settable `var` — they generate get/set
        // accessors. A `let` declaration would silently get the accessors
        // attached and produce confusing downstream errors.
        if varDecl.bindingSpecifier.tokenKind == .keyword(.let) {
            throw LockPropertyError.requiresVar(macroName)
        }

        guard let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            throw LockPropertyError.invalidPropertyBinding(macroName)
        }

        if binding.accessorBlock != nil {
            throw LockPropertyError.cannotHaveExistingAccessors(macroName)
        }

        let isWeak = varDecl.modifiers.contains { $0.name.tokenKind == .keyword(.weak) }
        let isStatic = varDecl.modifiers.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }

        // An annotation is only needed where nothing else can stand in for it.
        // A weak property's storage spells `WeakBox<T>`, and `weak var owner =
        // object` infers `Object?`, which gives no spelling for `T`; a property
        // with no initial value has nothing to infer from at all.
        let type = binding.typeAnnotation?.type
        if type == nil, isWeak || binding.initializer == nil {
            throw LockPropertyError.requiresExplicitType(macroName)
        }

        let isOptional = type.map(Self.isOptionalType) ?? false
        let isIUO = type?.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) ?? false

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

        let baseType = type.map(Self.extractBaseType(from:))

        return LockPropertyInfo(
            propertyName: pattern.identifier.text,
            storageName: "_\(pattern.identifier.text)",
            type: type,
            baseType: baseType,
            initialValue: initialValue,
            isWeak: isWeak,
            isOptional: isOptional,
            isImplicitlyUnwrappedOptional: isIUO,
            isStatic: isStatic
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
    case requiresVar(String)
    case requiresInitialValue(String)
    case requiresExplicitType(String)
    case invalidPropertyBinding(String)
    case cannotHaveExistingAccessors(String)
    case weakRequiresOptional(String)
    case weakNotSupported(String)

    public var description: String {
        switch self {
        case .requiresVariable(let name):
            return "@\(name) can only be applied to a variable declaration."
        case .requiresVar(let name):
            return "@\(name) requires a `var` (settable) property; `let` is not supported."
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
        case .weakNotSupported(let name):
            return "@\(name) cannot be applied to a `weak` property; the backing storage holds the value strongly."
        }
    }

    public var message: String { description }

    public var diagnosticID: MessageID {
        let id: String
        switch self {
        case .requiresVariable: id = "requiresVariable"
        case .requiresVar: id = "requiresVar"
        case .requiresInitialValue: id = "requiresInitialValue"
        case .requiresExplicitType: id = "requiresExplicitType"
        case .invalidPropertyBinding: id = "invalidPropertyBinding"
        case .cannotHaveExistingAccessors: id = "cannotHaveExistingAccessors"
        case .weakRequiresOptional: id = "weakRequiresOptional"
        case .weakNotSupported: id = "weakNotSupported"
        }
        return MessageID(domain: "LockPropertyError", id: id)
    }

    public var severity: DiagnosticSeverity { .error }
}
