import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@DynamicSubclassOverride([explicitSelector])` — body macro.
///
/// Rewrites the function body by prepending two typed local helpers that
/// capture `self.base`:
///
/// * `callSuper(args...)` — dispatches unconditionally to the original
///   class's IMP. Traps if the original class doesn't implement the selector.
/// * `callSuperIfImplemented(args...)` (void) /
///   `callSuperIfImplemented(default:_:)` (returning) — dispatches only when
///   the original class actually implements the selector. Lets hook methods
///   that target informal-protocol selectors chain super safely.
///
/// The user's original statements follow unchanged.
///
/// All compile-time validation lives in `diagnoseUnsupportedFunctionShape`:
/// throws / async / @MainActor / mutating / non-ObjC representable parameters /
/// non-`_` first parameter label (unless an explicit selector is provided).
public enum DynamicSubclassOverrideMacro {}

extension DynamicSubclassOverrideMacro: BodyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        guard let functionDeclaration = declaration.as(FunctionDeclSyntax.self) else {
            context.emit(
                .error(
                    "notAFunctionDeclaration",
                    "@DynamicSubclassOverride can only be attached to a function declaration."
                ),
                at: node
            )
            return []
        }

        // Recover the explicit selector argument from the attribute that
        // invoked us. The marker discovery helper exists for the MemberMacro
        // role; here we only have the single attribute node.
        let explicitSelector = extractExplicitSelector(from: node)
        let marker = OverrideMarker(attribute: node, explicitSelector: explicitSelector)

        let canProceed = diagnoseUnsupportedFunctionShape(
            functionDeclaration,
            in: context,
            overrideMarker: marker
        )
        guard canProceed, let originalBody = functionDeclaration.body else {
            return functionDeclaration.body?.statements.map { $0 } ?? []
        }

        let shape = FunctionShape(from: functionDeclaration)

        let callSuperItem = CodeBlockItemSyntax(
            stringLiteral: buildLocalCallSuperDeclaration(
                shape: shape,
                explicitSelector: explicitSelector
            )
        )
        let callSuperIfImplementedItem = CodeBlockItemSyntax(
            stringLiteral: buildLocalCallSuperIfImplementedDeclaration(
                shape: shape,
                explicitSelector: explicitSelector
            )
        )

        var statements: [CodeBlockItemSyntax] = [callSuperItem, callSuperIfImplementedItem]
        statements.append(contentsOf: liftImplicitReturn(in: originalBody.statements, when: shape))
        return statements
    }
}

/// Swift's implicit-return rule only fires for single-expression function
/// bodies. Once we prepend the two `func callSuper…` decls, the body has more
/// than one statement, so a single-expression user body (e.g.
/// `callSuper(name, age).uppercased()`) stops compiling. Detect that shape and
/// promote the lone expression to an explicit `return`.
private func liftImplicitReturn(
    in statements: CodeBlockItemListSyntax,
    when shape: FunctionShape
) -> [CodeBlockItemSyntax] {
    let originalStatements = Array(statements)
    guard !shape.isVoid,
          originalStatements.count == 1,
          let only = originalStatements.first
    else {
        return originalStatements
    }
    // Only rewrite plain expression items — preserve any existing `return`,
    // `throw`, `if let`, etc. that the user wrote explicitly.
    switch only.item {
    case .expr(let expression):
        return [CodeBlockItemSyntax(stringLiteral: "return \(expression.trimmedDescription)")]
    default:
        return originalStatements
    }
}

// MARK: - Explicit Selector

private func extractExplicitSelector(from attribute: AttributeSyntax) -> String? {
    guard let argumentList = attribute.arguments?.as(LabeledExprListSyntax.self),
          let firstArgument = argumentList.first
    else {
        return nil
    }
    return extractStringLiteral(from: firstArgument.expression)
}

// MARK: - callSuper

private func buildLocalCallSuperDeclaration(
    shape: FunctionShape,
    explicitSelector: String?
) -> String {
    let parameterListText = shape.callSuperParameterListText
    let returnClauseText = shape.returnTypeText.map { " -> \($0)" } ?? ""
    let dispatchCallText = buildDispatchCall(
        shape: shape,
        explicitSelector: explicitSelector,
        trapWhenMissing: true,
        defaultValueExpression: nil
    )
    return """
    func callSuper(\(parameterListText))\(returnClauseText) {
        \(dispatchCallText)
    }
    """
}

// MARK: - callSuperIfImplemented

private func buildLocalCallSuperIfImplementedDeclaration(
    shape: FunctionShape,
    explicitSelector: String?
) -> String {
    if shape.isVoid {
        return buildVoidCallSuperIfImplementedDeclaration(
            shape: shape,
            explicitSelector: explicitSelector
        )
    } else {
        return buildReturningCallSuperIfImplementedDeclaration(
            shape: shape,
            explicitSelector: explicitSelector
        )
    }
}

private func buildVoidCallSuperIfImplementedDeclaration(
    shape: FunctionShape,
    explicitSelector: String?
) -> String {
    let parameterListText = shape.callSuperParameterListText
    let dispatchCallText = buildDispatchCall(
        shape: shape,
        explicitSelector: explicitSelector,
        trapWhenMissing: false,
        defaultValueExpression: nil
    )
    return """
    func callSuperIfImplemented(\(parameterListText)) {
        \(dispatchCallText)
    }
    """
}

private func buildReturningCallSuperIfImplementedDeclaration(
    shape: FunctionShape,
    explicitSelector: String?
) -> String {
    guard let returnTypeText = shape.returnTypeText else {
        // Unreachable: caller checked isVoid first.
        return ""
    }
    var defaultedParameterList = ["default defaultValue: \(returnTypeText)"]
    defaultedParameterList.append(contentsOf: shape.parameters.enumerated().map { index, parameter in
        "_ argument\(index): \(parameter.typeText)"
    })
    let parameterListText = defaultedParameterList.joined(separator: ", ")
    let dispatchCallText = buildDispatchCall(
        shape: shape,
        explicitSelector: explicitSelector,
        trapWhenMissing: false,
        defaultValueExpression: "defaultValue"
    )
    return """
    func callSuperIfImplemented(\(parameterListText)) -> \(returnTypeText) {
        \(dispatchCallText)
    }
    """
}

// MARK: - Dispatch

/// Emit the IMP-dispatch sequence. `trapWhenMissing` chooses between
/// `resolveSuperImplementation` (traps) and `resolveSuperImplementationIfAvailable`
/// (returns `nil`). For the non-trapping variant on a returning function,
/// `defaultValueExpression` is required to express "no impl → return default".
private func buildDispatchCall(
    shape: FunctionShape,
    explicitSelector: String?,
    trapWhenMissing: Bool,
    defaultValueExpression: String?
) -> String {
    let selectorString = shape.selectorString(explicitSelector: explicitSelector)
    let selectorLiteral = "NSSelectorFromString(\"\(selectorString)\")"
    let returnTypeText = shape.returnTypeText ?? "Void"

    var conventionParameterTypes = ["AnyObject", "Selector"]
    conventionParameterTypes.append(contentsOf: shape.parameters.map { $0.typeText })
    let conventionSignatureText = "@convention(c) (\(conventionParameterTypes.joined(separator: ", "))) -> \(returnTypeText)"

    var callArguments = ["self.base", selectorLiteral]
    callArguments.append(contentsOf: shape.parameters.enumerated().map { index, _ in "argument\(index)" })
    let callArgumentList = callArguments.joined(separator: ", ")

    let returnKeyword = shape.isVoid ? "" : "return "

    if trapWhenMissing {
        return """
        let originalImplementation = ObjCRuntimeToolbox.DynamicSubclass.resolveSuperImplementation(for: self.base, selector: \(selectorLiteral))
            let dispatchFunction = unsafeBitCast(originalImplementation, to: (\(conventionSignatureText)).self)
            \(returnKeyword)dispatchFunction(\(callArgumentList))
        """
    }

    if shape.isVoid {
        return """
        guard let originalImplementation = ObjCRuntimeToolbox.DynamicSubclass.resolveSuperImplementationIfAvailable(for: self.base, selector: \(selectorLiteral)) else {
                return
            }
            let dispatchFunction = unsafeBitCast(originalImplementation, to: (\(conventionSignatureText)).self)
            dispatchFunction(\(callArgumentList))
        """
    }

    // Returning + non-trapping path requires a default expression. The
    // buildReturningCallSuperIfImplementedDeclaration always supplies one;
    // any other caller is a programmer error.
    guard let defaultValueExpression else {
        preconditionFailure("buildDispatchCall: returning + non-trapping variant requires defaultValueExpression")
    }
    return """
    guard let originalImplementation = ObjCRuntimeToolbox.DynamicSubclass.resolveSuperImplementationIfAvailable(for: self.base, selector: \(selectorLiteral)) else {
            return \(defaultValueExpression)
        }
        let dispatchFunction = unsafeBitCast(originalImplementation, to: (\(conventionSignatureText)).self)
        return dispatchFunction(\(callArgumentList))
    """
}
