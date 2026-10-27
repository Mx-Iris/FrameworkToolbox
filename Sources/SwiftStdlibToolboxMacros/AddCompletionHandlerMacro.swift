import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
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

        // `Task`, `Result` and `Error` are written with their modules: apps
        // routinely declare a `Task` or `Result` model of their own, and the
        // generated peer would pick that one up instead.
        //
        // The handler is `@Sendable` only when the caller passes
        // `sendable: true`. The `Task` below captures it and takes its closure
        // as `sending`, so on a `nonisolated` type in the Swift 6 language mode
        // the expansion does not compile without it. With it, every closure a
        // caller passes is checked as `@Sendable`, and one written on the main
        // actor can no longer touch main-actor state — an error even in Swift 5
        // — so it is opt-in and the signature stays what it always was.
        let returnTypeDescription = function.signature.returnClause?.type.trimmedDescription ?? "Void"
        let sendableAttribute = isSendableRequested(in: node, context: context) ? "@Sendable " : ""
        let completionHandlerParameter = FunctionParameterSyntax(
            firstName: .identifier("completion"),
            colon: .colonToken(trailingTrivia: .space),
            type: TypeSyntax("@escaping \(raw: sendableAttribute)(Swift.Result<\(raw: returnTypeDescription), any Swift.Error>) -> Void")
        )

        let callArguments = function.signature.parameterClause.parameters.asPassthroughArguments
        let returnsVoid = function.signature.returnClause?.type.isVoid ?? true
        let body: ExprSyntax = if returnsVoid {
            """
            _Concurrency.Task {
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
            _Concurrency.Task {
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

    /// Whether `sendable: true` was passed.
    ///
    /// Only a boolean literal is accepted: `@Sendable` is part of the generated
    /// signature, so the answer has to exist while the macro expands. Anything
    /// else is reported on the argument and read as `false`.
    private static func isSendableRequested(
        in node: AttributeSyntax,
        context: some MacroExpansionContext
    ) -> Bool {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let argument = arguments.first(where: { $0.label?.text == "sendable" })
        else { return false }

        guard let literal = argument.expression.as(BooleanLiteralExprSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: argument.expression,
                    message: AddCompletionHandlerMacroError.sendableIsNotALiteral
                )
            )
            return false
        }
        return literal.literal.text == "true"
    }
}

/// Diagnostics emitted by `@AddCompletionHandler`.
enum AddCompletionHandlerMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case notAFunction
    case missingAsync
    case sendableIsNotALiteral

    var description: String {
        switch self {
        case .notAFunction:
            return "@AddCompletionHandler only works on functions"
        case .missingAsync:
            return "can only add a completion-handler variant to an 'async' function"
        case .sendableIsNotALiteral:
            return """
                `sendable:` must be a boolean literal. Whether the completion handler is \
                `@Sendable` is part of the generated signature, so it is decided while the \
                macro expands — there is no runtime for a computed value to be evaluated in.
                """
        }
    }

    var message: String { description }

    var diagnosticID: MessageID {
        MessageID(domain: "AddCompletionHandlerMacro", id: "\(self)")
    }

    var severity: DiagnosticSeverity { .error }
}
