import SwiftSyntax
import MacroToolkit
import SwiftDiagnostics
import SwiftSyntaxMacros

/// Modified from: https://github.com/DougGregor/swift-macro-examples/blob/f61ac7cdca8dc3557e53f86e7e03df1353908d3e/MacroExamplesPlugin/AddCompletionHandlerMacro.swift
public struct AddCompletionHandlerMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = Function(declaration) else {
            throw MacroError("@AddCompletionHandler only works on functions")
        }

        guard function.isAsync else {
            let newSignature = function._syntax.withAsyncModifier().signature
            let diagnostic = DiagnosticBuilder(for: function._syntax.funcKeyword)
                .message("can only add a completion-handler variant to an 'async' function")
                .messageID(domain: "AddCompletionHandlerMacro", id: "MissingAsync")
                .suggestReplacement(
                    "add 'async'",
                    old: function._syntax.signature,
                    new: newSignature
                )
                .build()

            context.diagnose(diagnostic)
            return []
        }

        let completionHandlerParameter =
            FunctionParameter(
                name: "completion",
                type: "@escaping (Result<\(raw: function.returnType?.description ?? "Void"), Error>) -> Void"
            )

        let callArguments = function.parameters.asPassthroughArguments
        let body: ExprSyntax = if function.returnsVoid {
            """
            Task {
                do {
                    try await \(raw: function.identifier)(\(raw: callArguments.joined(separator: ", ")))
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
                    let result = try await \(raw: function.identifier)(\(raw: callArguments.joined(separator: ", ")))
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
            """
        }
        let newFunc =
            function._syntax
                .withAsyncModifier(false)
                .withThrowsModifier(false)
                .withReturnType(nil)
                .withParameters(function.parameters + [completionHandlerParameter])
                .withBody([
                    body,
                ])
                .withAttributes(function.attributes.removing(node))
                .withLeadingBlankLine()

        return [DeclSyntax(newFunc)]
    }
}
