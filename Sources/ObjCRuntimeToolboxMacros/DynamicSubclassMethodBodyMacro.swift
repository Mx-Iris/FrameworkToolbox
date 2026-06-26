import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@_DynamicSubclassMethodBody` — body macro applied automatically by
/// `@DynamicSubclassHook` to every instance method.
///
/// Rewrites the function body by prepending two typed local helpers that
/// capture `self.base`:
///
/// * `callSuper(args...)` — dispatches unconditionally to the original
///   class's IMP. Traps if the original class doesn't implement the selector.
/// * `callSuperIfImplemented(args...)` (void) / `callSuperIfImplemented(default:_:)`
///   (returning) — dispatches only when the original class actually implements
///   the selector. Lets hook methods that target informal-protocol selectors
///   chain super safely.
///
/// The user's original statements follow unchanged.
public enum DynamicSubclassMethodBodyMacro {}

extension DynamicSubclassMethodBodyMacro: BodyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        guard let functionDeclaration = declaration.as(FunctionDeclSyntax.self) else {
            return []
        }
        let shape = FunctionShape(from: functionDeclaration)
        guard let originalBody = functionDeclaration.body else {
            return []
        }

        let callSuperItem = CodeBlockItemSyntax(
            stringLiteral: buildLocalCallSuperDeclaration(shape: shape)
        )
        let callSuperIfImplementedItem = CodeBlockItemSyntax(
            stringLiteral: buildLocalCallSuperIfImplementedDeclaration(shape: shape)
        )

        var statements: [CodeBlockItemSyntax] = [callSuperItem, callSuperIfImplementedItem]
        statements.append(contentsOf: originalBody.statements)
        return statements
    }
}

// MARK: - callSuper

private func buildLocalCallSuperDeclaration(shape: FunctionShape) -> String {
    let parameterListText = shape.callSuperParameterListText
    let returnClauseText = shape.returnTypeText.map { " -> \($0)" } ?? ""
    let dispatchCallText = buildDispatchCall(shape: shape, trapWhenMissing: true)
    return """
    func callSuper(\(parameterListText))\(returnClauseText) {
        \(dispatchCallText)
    }
    """
}

// MARK: - callSuperIfImplemented

private func buildLocalCallSuperIfImplementedDeclaration(shape: FunctionShape) -> String {
    if shape.isVoid {
        return buildVoidCallSuperIfImplementedDeclaration(shape: shape)
    } else {
        return buildReturningCallSuperIfImplementedDeclaration(shape: shape)
    }
}

private func buildVoidCallSuperIfImplementedDeclaration(shape: FunctionShape) -> String {
    let parameterListText = shape.callSuperParameterListText
    let dispatchCallText = buildDispatchCall(shape: shape, trapWhenMissing: false)
    return """
    func callSuperIfImplemented(\(parameterListText)) {
        \(dispatchCallText)
    }
    """
}

private func buildReturningCallSuperIfImplementedDeclaration(shape: FunctionShape) -> String {
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
    trapWhenMissing: Bool,
    defaultValueExpression: String? = nil
) -> String {
    let selectorLiteral = "Selector((\"\(shape.selectorString)\"))"
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

    let defaultExpression = defaultValueExpression ?? "fatalError(\"PoC: missing default value\")"
    return """
    guard let originalImplementation = ObjCRuntimeToolbox.DynamicSubclass.resolveSuperImplementationIfAvailable(for: self.base, selector: \(selectorLiteral)) else {
            return \(defaultExpression)
        }
        let dispatchFunction = unsafeBitCast(originalImplementation, to: (\(conventionSignatureText)).self)
        return dispatchFunction(\(callArgumentList))
    """
}

enum DynamicSubclassMethodBodyMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case notAFunctionDeclaration

    var description: String {
        switch self {
        case .notAFunctionDeclaration:
            return "@_DynamicSubclassMethodBody can only be attached to a function declaration."
        }
    }

    var message: String { description }
    var severity: DiagnosticSeverity { .error }
    var diagnosticID: MessageID { MessageID(domain: "ObjCRuntimeToolbox", id: "\(self)") }
}
