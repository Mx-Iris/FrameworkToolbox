import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DyldInterposeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let functionDeclaration = declaration.as(FunctionDeclSyntax.self) else {
            throw DyldInterposeMacroError.requiresFunction
        }

        guard let targetFunctionExpression = parseTargetArgument(from: node) else {
            throw DyldInterposeMacroError.missingTargetArgument
        }

        try validateFunctionDeclaration(functionDeclaration)

        let replacementName = functionDeclaration.name.text
        let cFunctionType = buildCFunctionType(from: functionDeclaration.signature)
        let interposeVariableName = makeInterposeVariableName(for: replacementName)
        let targetExpressionDescription = targetFunctionExpression.trimmedDescription

        let generatedDeclaration: DeclSyntax = """
        #if canImport(Darwin)
        #if compiler(>=6.3)
        @section("__DATA,__interpose")
        @used
        #else
        @_section("__DATA,__interpose")
        @_used
        #endif
        private let \(raw: interposeVariableName): (\(raw: cFunctionType), \(raw: cFunctionType)) = (\(raw: replacementName), \(raw: targetExpressionDescription))
        #endif
        """

        return [generatedDeclaration]
    }
}

private extension DyldInterposeMacro {
    static func parseTargetArgument(from attribute: AttributeSyntax) -> ExprSyntax? {
        guard let argumentList = attribute.arguments?.as(LabeledExprListSyntax.self),
              let firstArgument = argumentList.first
        else {
            return nil
        }
        return firstArgument.expression
    }

    static func validateFunctionDeclaration(_ functionDeclaration: FunctionDeclSyntax) throws {
        if functionDeclaration.genericParameterClause != nil {
            throw DyldInterposeMacroError.genericFunctionUnsupported
        }
        if functionDeclaration.genericWhereClause != nil {
            throw DyldInterposeMacroError.genericFunctionUnsupported
        }

        let effectSpecifiers = functionDeclaration.signature.effectSpecifiers
        if effectSpecifiers?.throwsClause != nil {
            throw DyldInterposeMacroError.effectfulFunctionUnsupported(effect: "throws")
        }
        if effectSpecifiers?.asyncSpecifier != nil {
            throw DyldInterposeMacroError.effectfulFunctionUnsupported(effect: "async")
        }

        for parameter in functionDeclaration.signature.parameterClause.parameters {
            if let attributedType = parameter.type.as(AttributedTypeSyntax.self) {
                for specifier in attributedType.specifiers {
                    if let simpleSpecifier = specifier.as(SimpleTypeSpecifierSyntax.self),
                       simpleSpecifier.specifier.tokenKind == .keyword(.inout) {
                        throw DyldInterposeMacroError.inoutParameterUnsupported
                    }
                }
            }
        }
    }

    static func buildCFunctionType(from signature: FunctionSignatureSyntax) -> String {
        let parameterTypeDescriptions = signature.parameterClause.parameters.map { parameter in
            parameter.type.trimmedDescription
        }
        let parameterList = parameterTypeDescriptions.joined(separator: ", ")
        let returnTypeDescription = signature.returnClause?.type.trimmedDescription ?? "Void"
        return "@convention(c) (\(parameterList)) -> \(returnTypeDescription)"
    }

    static func makeInterposeVariableName(for replacementFunctionName: String) -> String {
        return "_dyldInterpose_\(replacementFunctionName)"
    }
}

enum DyldInterposeMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case requiresFunction
    case missingTargetArgument
    case genericFunctionUnsupported
    case effectfulFunctionUnsupported(effect: String)
    case inoutParameterUnsupported

    var description: String {
        switch self {
        case .requiresFunction:
            return "@DyldInterpose can only be applied to a function declaration."
        case .missingTargetArgument:
            return "@DyldInterpose requires the function being replaced as its first argument, e.g. @DyldInterpose(malloc)."
        case .genericFunctionUnsupported:
            return "@DyldInterpose cannot be applied to a generic function because @convention(c) function types do not support generics."
        case .effectfulFunctionUnsupported(let effect):
            return "@DyldInterpose cannot be applied to a function marked `\(effect)` because @convention(c) function types do not support effects."
        case .inoutParameterUnsupported:
            return "@DyldInterpose cannot be applied to a function with `inout` parameters because @convention(c) function types do not support `inout`."
        }
    }

    var message: String { description }

    var diagnosticID: MessageID {
        let diagnosticName: String
        switch self {
        case .requiresFunction:
            diagnosticName = "requiresFunction"
        case .missingTargetArgument:
            diagnosticName = "missingTargetArgument"
        case .genericFunctionUnsupported:
            diagnosticName = "genericFunctionUnsupported"
        case .effectfulFunctionUnsupported:
            diagnosticName = "effectfulFunctionUnsupported"
        case .inoutParameterUnsupported:
            diagnosticName = "inoutParameterUnsupported"
        }
        return MessageID(domain: "DyldInterposeMacroError", id: diagnosticName)
    }

    var severity: DiagnosticSeverity { .error }
}
