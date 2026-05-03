import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct AvailableNonMutatingMacro: AvailableStorageMacroProtocol {
    public static let macroName = "AvailableNonMutating"
    public static let emitsSetter = false
}

public struct AvailableMutatingMacro: AvailableStorageMacroProtocol {
    public static let macroName = "AvailableMutating"
    public static let emitsSetter = true
}

public protocol AvailableStorageMacroProtocol: PeerMacro, AccessorMacro {
    static var macroName: String { get }
    static var emitsSetter: Bool { get }
}

extension AvailableStorageMacroProtocol {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let propertyInfo = try AvailableStoragePropertyParser.parse(
            declaration,
            attribute: node,
            macroName: macroName
        )
        let staticKeyword = propertyInfo.isStatic ? "static " : ""
        return [
            """
            private \(raw: staticKeyword)var \(raw: propertyInfo.storageName): Any?
            """
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let propertyInfo = try? AvailableStoragePropertyParser.parse(
            declaration,
            attribute: node,
            macroName: macroName
        ) else {
            return []
        }

        let typeDescription = propertyInfo.type.trimmedDescription
        let defaultValueDescription = propertyInfo.defaultValue.trimmedDescription

        var accessors: [AccessorDeclSyntax] = [
            """
            get {
                if let existingValue = \(raw: propertyInfo.storageName) as? \(raw: typeDescription) {
                    return existingValue
                }
                let defaultValue: \(raw: typeDescription) = \(raw: defaultValueDescription)
                \(raw: propertyInfo.storageName) = defaultValue
                return defaultValue
            }
            """
        ]

        if emitsSetter {
            accessors.append(
                """
                set {
                    \(raw: propertyInfo.storageName) = newValue
                }
                """
            )
        }

        return accessors
    }
}

struct AvailableStoragePropertyInfo {
    let propertyName: String
    let storageName: String
    let type: TypeSyntax
    let defaultValue: ExprSyntax
    let isStatic: Bool
}

enum AvailableStoragePropertyParser {
    static func parse(
        _ declaration: some DeclSyntaxProtocol,
        attribute: AttributeSyntax,
        macroName: String
    ) throws -> AvailableStoragePropertyInfo {
        guard let variableDeclaration = declaration.as(VariableDeclSyntax.self),
              variableDeclaration.bindingSpecifier.tokenKind == .keyword(.var) else {
            throw AvailableStorageMacroError.requiresVariable(macroName)
        }

        guard variableDeclaration.bindings.count == 1,
              let propertyBinding = variableDeclaration.bindings.first,
              let identifierPattern = propertyBinding.pattern.as(IdentifierPatternSyntax.self) else {
            throw AvailableStorageMacroError.invalidPropertyBinding(macroName)
        }

        if propertyBinding.accessorBlock != nil {
            throw AvailableStorageMacroError.cannotHaveExistingAccessors(macroName)
        }

        guard let type = propertyBinding.typeAnnotation?.type else {
            throw AvailableStorageMacroError.requiresExplicitType(macroName)
        }

        let argumentDefaultValue = (attribute.arguments?.as(LabeledExprListSyntax.self))
            .flatMap { $0.first?.expression }
            .flatMap { $0.is(NilLiteralExprSyntax.self) ? nil : $0 }

        let initializerDefaultValue = propertyBinding.initializer?.value

        let defaultValue: ExprSyntax
        switch (argumentDefaultValue, initializerDefaultValue) {
        case (let argument?, nil):
            defaultValue = argument
        case (nil, let initializer?):
            defaultValue = initializer
        case (_?, _?):
            throw AvailableStorageMacroError.conflictingDefaultValue(macroName)
        case (nil, nil):
            throw AvailableStorageMacroError.requiresDefaultValue(macroName)
        }

        let isStatic = variableDeclaration.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.static) || modifier.name.tokenKind == .keyword(.class)
        }
        let propertyName = identifierPattern.identifier.text

        return AvailableStoragePropertyInfo(
            propertyName: propertyName,
            storageName: "\(propertyName)Storage",
            type: type,
            defaultValue: defaultValue,
            isStatic: isStatic
        )
    }
}

enum AvailableStorageMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case requiresVariable(String)
    case invalidPropertyBinding(String)
    case cannotHaveExistingAccessors(String)
    case requiresExplicitType(String)
    case requiresDefaultValue(String)
    case conflictingDefaultValue(String)

    var description: String {
        switch self {
        case .requiresVariable(let macroName):
            return "@\(macroName) can only be applied to a variable declaration."
        case .invalidPropertyBinding(let macroName):
            return "@\(macroName) requires a single named property binding."
        case .cannotHaveExistingAccessors(let macroName):
            return "@\(macroName) cannot be applied to computed properties or properties with existing accessors."
        case .requiresExplicitType(let macroName):
            return "@\(macroName) requires an explicit type annotation."
        case .requiresDefaultValue(let macroName):
            return "@\(macroName) requires a default value, either as a macro argument or as a property initializer."
        case .conflictingDefaultValue(let macroName):
            return "@\(macroName) cannot specify both a macro argument and a property initializer."
        }
    }

    var message: String { description }

    var diagnosticID: MessageID {
        let diagnosticName: String
        switch self {
        case .requiresVariable:
            diagnosticName = "requiresVariable"
        case .invalidPropertyBinding:
            diagnosticName = "invalidPropertyBinding"
        case .cannotHaveExistingAccessors:
            diagnosticName = "cannotHaveExistingAccessors"
        case .requiresExplicitType:
            diagnosticName = "requiresExplicitType"
        case .requiresDefaultValue:
            diagnosticName = "requiresDefaultValue"
        case .conflictingDefaultValue:
            diagnosticName = "conflictingDefaultValue"
        }
        return MessageID(domain: "AvailableStorageMacroError", id: diagnosticName)
    }

    var severity: DiagnosticSeverity { .error }
}
