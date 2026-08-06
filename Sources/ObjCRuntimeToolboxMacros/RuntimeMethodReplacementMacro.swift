import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@RuntimeMethodReplacement([selector], typeEncoding:, isClassMethod:)` —
/// body macro.
///
/// Prepends one typed local helper to the method body:
///
/// * `callOriginal(args...)` — dispatches through the implementation this
///   replacement displaced, cast to a `@convention(c)` function type over the
///   method's own parameter and return types.
///
/// `callOriginal` goes straight to the saved implementation rather than through
/// the class's method table, so a replacement forwarding to the host cannot
/// re-enter itself.
///
/// The user's statements follow unchanged. All shape validation is shared with
/// `@DynamicSubclassOverride` via `diagnoseUnsupportedFunctionShape`.
public enum RuntimeMethodReplacementMacro {}

extension RuntimeMethodReplacementMacro: BodyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        guard let functionDeclaration = declaration.as(FunctionDeclSyntax.self) else {
            context.emit(
                .error(
                    "notAFunctionDeclaration",
                    "\(runtimeReplacementMacroName) can only be attached to a function declaration."
                ),
                at: node
            )
            return []
        }

        let marker = parseReplacementMarker(from: node)

        let canProceed = diagnoseUnsupportedFunctionShape(
            functionDeclaration,
            in: context,
            overrideMarker: OverrideMarker(attribute: node, explicitSelector: marker.explicitSelector),
            macroName: runtimeReplacementMacroName
        )
        guard canProceed, let originalBody = functionDeclaration.body else {
            return functionDeclaration.body?.statements.map { $0 } ?? []
        }

        // A static or class method has no `self.host` to dispatch against — the
        // container is constructed per invocation around the receiver, so the
        // replacement has to be an instance method of the container even when
        // it replaces an Objective-C class method (`isClassMethod:` controls
        // that separately, and makes `host` the class object).
        if let staticModifier = functionDeclaration.modifiers.first(where: {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }) {
            context.emit(
                .error(
                    "staticReplacementNotSupported",
                    """
                    \(runtimeReplacementMacroName) cannot be applied to a 'static' or 'class' method. \
                    Declare it as an instance method — the container is rebuilt around the receiver on every invocation, and 'host' is how the replacement reaches it. \
                    To replace an Objective-C *class* method, keep the Swift method non-static and pass isClassMethod: true.
                    """
                ),
                at: staticModifier
            )
            return originalBody.statements.map { $0 }
        }

        let shape = FunctionShape(from: functionDeclaration)

        let callOriginalItem = CodeBlockItemSyntax(
            stringLiteral: buildCallOriginalDeclaration(
                shape: shape,
                explicitSelector: marker.explicitSelector
            )
        )

        var statements: [CodeBlockItemSyntax] = [callOriginalItem]
        statements.append(contentsOf: liftImplicitReturn(in: originalBody.statements, when: shape))
        return statements
    }
}

// MARK: - callOriginal

private func buildCallOriginalDeclaration(
    shape: FunctionShape,
    explicitSelector: String?
) -> String {
    let selectorString = shape.selectorString(explicitSelector: explicitSelector)
    let selectorExpression = "NSSelectorFromString(\(stringLiteral(selectorString)))"
    let returnTypeText = shape.returnTypeText ?? "Void"

    var conventionParameterTypes = ["AnyObject", "Selector"]
    conventionParameterTypes.append(contentsOf: shape.parameters.map { $0.typeText })
    let conventionSignatureText = "@convention(c) (\(conventionParameterTypes.joined(separator: ", "))) -> \(returnTypeText)"

    var callArguments = ["self.host", selectorExpression]
    callArguments.append(contentsOf: shape.parameters.enumerated().map { index, _ in "argument\(index)" })
    let callArgumentList = callArguments.joined(separator: ", ")

    let parameterListText = shape.callSuperParameterListText
    let returnClauseText = shape.returnTypeText.map { " -> \($0)" } ?? ""
    let returnKeyword = shape.isVoid ? "" : "return "

    // @discardableResult so a replacement can forward to the host purely for
    // its side effects without the compiler objecting to the ignored value.
    return """
    @discardableResult
    func callOriginal(\(parameterListText))\(returnClauseText) {
        let dispatchFunction = unsafeBitCast(self.originalImplementation, to: (\(conventionSignatureText)).self)
        \(returnKeyword)dispatchFunction(\(callArgumentList))
    }
    """
}
