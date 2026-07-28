import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Modified from: https://github.com/DougGregor/swift-macro-examples/blob/f61ac7cdca8dc3557e53f86e7e03df1353908d3e/MacroExamplesPlugin/AddCompletionHandlerMacro.swift
public struct AddCompletionHandlerMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            throw AddCompletionHandlerMacroError.notAFunction
        }

        guard function.signature.effectSpecifiers?.asyncSpecifier != nil else {
            let newSignature = function.withAsyncModifier().signature
            let diagnostic = Diagnostic(
                node: Syntax(function.funcKeyword),
                message: AddCompletionHandlerMacroError.missingAsync,
                fixIt: .replace(
                    message: SimpleFixItMessage(
                        message: "add 'async'",
                        fixItID: AddCompletionHandlerMacroError.missingAsync.diagnosticID
                    ),
                    oldNode: function.signature,
                    newNode: newSignature
                )
            )

            context.diagnose(diagnostic)
            return []
        }

        let returnTypeDescription = function.signature.returnClause?.type.trimmedDescription ?? "Void"
        let completionHandlerParameter = FunctionParameterSyntax(
            firstName: .identifier("completion"),
            colon: .colonToken(trailingTrivia: .space),
            type: TypeSyntax("@escaping (Result<\(raw: returnTypeDescription), Error>) -> Void")
        )

        let callArguments = function.signature.parameterClause.parameters.asPassthroughArguments
        let returnsVoid = function.signature.returnClause?.type.isVoid ?? true
        let body: ExprSyntax = if returnsVoid {
            """
            Task {
                do {
                    try await \(raw: function.name.text)(\(raw: callArguments.joined(separator: ", ")))
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
            """
        } else {
            """
            Task {
                do {
                    let result = try await \(raw: function.name.text)(\(raw: callArguments.joined(separator: ", ")))
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
            """
        }
        let newFunc =
            function
                .withAsyncModifier(false)
                .withThrowsModifier(false)
                .withReturnType(nil)
                .withParameters(function.signature.parameterClause.parameters + [completionHandlerParameter])
                .withBody([
                    body,
                ])
                .withAttributes(function.attributes.removing(node))
                .withLeadingBlankLine()

        return [DeclSyntax(newFunc)]
    }
}

/// Diagnostics emitted by `@AddCompletionHandler`.
enum AddCompletionHandlerMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case notAFunction
    case missingAsync

    var description: String {
        switch self {
        case .notAFunction:
            return "@AddCompletionHandler only works on functions"
        case .missingAsync:
            return "can only add a completion-handler variant to an 'async' function"
        }
    }

    var message: String { description }

    var diagnosticID: MessageID {
        MessageID(domain: "AddCompletionHandlerMacro", id: "\(self)")
    }

    var severity: DiagnosticSeverity { .error }
}
