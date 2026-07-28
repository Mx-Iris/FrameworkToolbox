import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// Modified from: https://github.com/DougGregor/swift-macro-examples/blob/f61ac7cdca8dc3557e53f86e7e03df1353908d3e/MacroExamplesPlugin/AddAsyncMacro.swift

enum AddAsyncMacroCore {
    static func expansion(of node: AttributeSyntax?, providingFunctionOf declaration: some DeclSyntaxProtocol) throws -> DeclSyntax {
        // Only on functions at the moment.
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            throw AddAsyncMacroError.notAFunction
        }

        // This only makes sense for non async functions.
        guard function.signature.effectSpecifiers?.asyncSpecifier == nil else {
            throw AddAsyncMacroError.alreadyAsync
        }

        // This only makes sense void functions
        guard function.signature.returnClause?.type.isVoid ?? true else {
            throw AddAsyncMacroError.nonVoidReturnType
        }

        // Requires a completion handler block as last parameter
        guard
            let completionHandlerType = function.signature.parameterClause.parameters.last?.type.asFunctionType
        else {
            throw AddAsyncMacroError.missingCompletionHandler
        }

        // Completion handler needs to return Void
        guard completionHandlerType.returnClause.type.isVoid else {
            throw AddAsyncMacroError.completionHandlerReturnsNonVoid
        }

        guard let returnType = completionHandlerType.parameters.first.map(\.type) else {
            throw AddAsyncMacroError.completionHandlerWithoutParameter
        }

        // Destructure return type
        let successReturnType: TypeSyntax
        let isResultReturn: Bool
        if let resultTypeArguments = returnType.asResultTypeArguments {
            isResultReturn = true
            successReturnType = resultTypeArguments.success
        } else {
            isResultReturn = false
            successReturnType = returnType
        }

        // Remove completionHandler and comma from the previous parameter
        let newParameters = function.signature.parameterClause.parameters.dropLast()

        // Drop the @AddAsync attribute from the new declaration.
        var filteredAttributes = function.attributes
        if let node {
            filteredAttributes = filteredAttributes.removing(node)
        }

        let callArguments = newParameters.asPassthroughArguments

        let newBody = function.body.map { _ in
            let switchBody: ExprSyntax =
            """
            switch returnValue {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
            }
            """

            let continuationExpr =
            isResultReturn
            ? "try await withCheckedThrowingContinuation { continuation in"
            : "await withCheckedContinuation { continuation in"

            let newBody: ExprSyntax =
            """
            \(raw: continuationExpr)
                \(raw: function.name.text)(\(raw: callArguments.joined(separator: ", "))) { returnValue in
                    \(isResultReturn ? switchBody : "continuation.resume(returning: returnValue)")
                }
            }
            """
            return CodeBlockSyntax([newBody])
        }

        var newFunc =
            function
            .withParameters(newParameters)
            .withReturnType(successReturnType)
            .withAsyncModifier()
            .withThrowsModifier(isResultReturn)
            .withAttributes(filteredAttributes)
            .withLeadingBlankLine()

        if let newBody {
            newFunc = newFunc.withBody(newBody)
        }

        return DeclSyntax(newFunc)
    }
}

/// Diagnostics emitted by `@AddAsync`. `@AddAsyncAllMembers` swallows these so
/// that ineligible members are simply skipped rather than failing the build.
enum AddAsyncMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case notAFunction
    case alreadyAsync
    case nonVoidReturnType
    case missingCompletionHandler
    case completionHandlerReturnsNonVoid
    case completionHandlerWithoutParameter

    var description: String {
        switch self {
        case .notAFunction:
            return "@AddAsync only works on functions"
        case .alreadyAsync:
            return "@AddAsync requires a non async function"
        case .nonVoidReturnType:
            return "@AddAsync requires a function that returns void"
        case .missingCompletionHandler:
            return "@AddAsync requires a function that has a completion handler as last parameter"
        case .completionHandlerReturnsNonVoid:
            return "@AddAsync requires a function that has a completion handler that returns Void"
        case .completionHandlerWithoutParameter:
            return "@AddAsync requires a function that has a completion handler that has one parameter"
        }
    }

    var message: String { description }

    var diagnosticID: MessageID {
        MessageID(domain: "\(AddAsyncMacro.self)", id: "\(Self.self)")
    }

    var severity: DiagnosticSeverity { .error }
}
