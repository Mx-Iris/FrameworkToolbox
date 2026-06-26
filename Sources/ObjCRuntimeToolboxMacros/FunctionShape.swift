import SwiftSyntax

/// Parsed shape of a `func` declaration used by both the member macro
/// (to build IMP-bridge blocks) and the body macro (to build local
/// `callSuper(...)` helpers). Centralised so the two roles can't disagree
/// on selector derivation or parameter forwarding.
struct FunctionShape {

    /// One positional parameter — i.e. everything after the implicit `self`.
    struct Parameter {
        /// External argument label (`_` if the call site is positional).
        let externalLabel: String
        /// Internal parameter name as seen inside the body.
        let internalName: String
        /// Type as written in the source (trimmed of trivia).
        let typeText: String
    }

    let baseName: String
    let parameters: [Parameter]
    /// Trimmed return-type text, or `nil` for `Void`-returning functions.
    let returnTypeText: String?

    init(from declaration: FunctionDeclSyntax) {
        baseName = declaration.name.text
        parameters = declaration.signature.parameterClause.parameters.map { parameter in
            let externalLabel = parameter.firstName.text
            let internalName = parameter.secondName?.text ?? externalLabel
            return Parameter(
                externalLabel: externalLabel,
                internalName: internalName,
                typeText: parameter.type.trimmedDescription
            )
        }
        if let returnClause = declaration.signature.returnClause {
            let text = returnClause.type.trimmedDescription
            if text == "Void" || text == "()" {
                returnTypeText = nil
            } else {
                returnTypeText = text
            }
        } else {
            returnTypeText = nil
        }
    }

    var isVoid: Bool { returnTypeText == nil }

    /// Objective-C selector string derived from the Swift name and parameter
    /// labels: `<baseName>[<param1Label>:<param2Label>:…]`. A `_` external
    /// label contributes only `:`. With zero parameters there are no colons.
    var selectorString: String {
        if parameters.isEmpty { return baseName }
        var result = baseName
        for (index, parameter) in parameters.enumerated() {
            if index == 0 {
                if parameter.externalLabel != "_" {
                    result += parameter.externalLabel
                }
            } else {
                result += parameter.externalLabel == "_" ? "" : parameter.externalLabel
            }
            result += ":"
        }
        return result
    }

    /// Parameter list as it should appear on the generated local `callSuper`
    /// helper: every parameter is `_`-labeled so the user can invoke
    /// positionally — `callSuper(arg)`. Indexed names avoid collisions with
    /// the outer function's own parameters.
    var callSuperParameterListText: String {
        parameters.enumerated().map { index, parameter in
            "_ argument\(index): \(parameter.typeText)"
        }.joined(separator: ", ")
    }

    /// Positional argument list for the inner runtime dispatch call.
    var dispatchArgumentList: String {
        parameters.enumerated().map { index, _ in "argument\(index)" }.joined(separator: ", ")
    }

    /// Block IMP signature: `(BaseType, ...paramTypes) -> ReturnType`.
    func blockSignatureText(baseTypeText: String) -> String {
        var parameterTypes = [baseTypeText]
        parameterTypes.append(contentsOf: parameters.map { $0.typeText })
        let parameterListText = parameterTypes.joined(separator: ", ")
        let returnText = returnTypeText ?? "Void"
        return "(\(parameterListText)) -> \(returnText)"
    }

    /// Closure body that constructs the hook struct around the incoming
    /// instance and invokes the user-declared method with the labelled args.
    func blockBodyText(hookTypeName: String) -> String {
        let instanceParameter = "instance"
        let argumentParameterNames = parameters.enumerated().map { index, _ in "argument\(index)" }
        let parameterNames = [instanceParameter] + argumentParameterNames

        let callArguments = parameters.enumerated().map { index, parameter in
            let argumentName = "argument\(index)"
            if parameter.externalLabel == "_" {
                return argumentName
            } else {
                return "\(parameter.externalLabel): \(argumentName)"
            }
        }.joined(separator: ", ")

        return "{ \(parameterNames.joined(separator: ", ")) in \(hookTypeName)(base: \(instanceParameter)).\(baseName)(\(callArguments)) }"
    }
}
