import SwiftDiagnostics
import SwiftSyntax

// MARK: - Type Inspection

extension TypeSyntax {
    /// The type with any leading attributes stripped, so that
    /// `@escaping (Int) -> Void` is seen as the function type `(Int) -> Void`.
    var withoutAttributes: TypeSyntax {
        self.as(AttributedTypeSyntax.self)?.baseType ?? self
    }

    /// The type as a function type, looking through attributes such as `@escaping`.
    var asFunctionType: FunctionTypeSyntax? {
        withoutAttributes.as(FunctionTypeSyntax.self)
    }

    /// A textual description of the type in which the interchangeable spellings
    /// of void (`Void`, `()`, `(Void)`) all collapse to `Void`.
    var normalizedDescription: String {
        guard let tupleType = self.as(TupleTypeSyntax.self) else {
            return trimmedDescription
        }
        if tupleType.elements.isEmpty {
            return "Void"
        }
        // A single-element tuple is just a parenthesised type, not a real tuple.
        if tupleType.elements.count == 1, let onlyElement = tupleType.elements.first {
            return onlyElement.type.trimmedDescription
        }
        return trimmedDescription
    }

    /// Whether the type is one of the spellings of void.
    var isVoid: Bool {
        normalizedDescription == "Void"
    }

    /// The `Success` and `Failure` generic arguments when the type is spelled
    /// `Result<Success, Failure>`, otherwise `nil`.
    var asResultTypeArguments: (success: TypeSyntax, failure: TypeSyntax)? {
        guard
            let identifierType = withoutAttributes.as(IdentifierTypeSyntax.self),
            identifierType.name.text == "Result",
            let genericArguments = identifierType.genericArgumentClause?.arguments
        else {
            return nil
        }
        let argumentTypes = genericArguments.compactMap { $0.argument.as(TypeSyntax.self) }
        guard argumentTypes.count == 2 else {
            return nil
        }
        return (argumentTypes[0], argumentTypes[1])
    }
}

// MARK: - Parameter Inspection

extension FunctionParameterSyntax {
    /// The label callers write at the call site, or `nil` when the parameter is
    /// declared unlabelled (`_`).
    var callSiteLabel: String? {
        // Without a second name the single name serves as both label and binding.
        guard secondName != nil else {
            return firstName.text
        }
        let declaredLabel = firstName.text
        return declaredLabel == "_" ? nil : declaredLabel
    }

    /// The name the parameter is bound to inside the function body.
    var internalName: String {
        (secondName ?? firstName).text
    }
}

extension Sequence<FunctionParameterSyntax> {
    /// The parameters as a comma-separated parameter list, with each element's
    /// trailing comma fixed up so the last parameter has none.
    var asParameterList: FunctionParameterListSyntax {
        let parameters = Array(self)
        return FunctionParameterListSyntax(
            parameters.enumerated().map { index, parameter in
                let isLast = index == parameters.count - 1
                return parameter.with(\.trailingComma, isLast ? nil : .commaToken())
            }
        )
    }

    /// The parameters rendered as the arguments that forward them to a function
    /// declaring the same parameters (common when wrapping a function).
    var asPassthroughArguments: [String] {
        map { parameter in
            guard let callSiteLabel = parameter.callSiteLabel else {
                return parameter.internalName
            }
            return "\(callSiteLabel): \(parameter.internalName)"
        }
    }
}

// MARK: - Attribute Editing

extension AttributeListSyntax {
    /// The attribute list with every attribute whose name matches `attribute`
    /// removed. Used to keep a macro's own attribute off the declaration it
    /// generates, which would otherwise expand forever.
    func removing(_ attribute: AttributeSyntax) -> AttributeListSyntax {
        let removedName = attribute.attributeName.trimmedDescription
        return AttributeListSyntax(
            compactMap { element in
                if case .attribute(let attributeSyntax) = element,
                   attributeSyntax.attributeName.trimmedDescription == removedName {
                    return nil
                }
                return element.with(\.trailingTrivia, .space)
            }
        )
    }
}

// MARK: - Function Declaration Editing

extension FunctionDeclSyntax {
    /// The signature's effect specifiers, or an empty set of specifiers to build on.
    var effectSpecifiersOrDefault: FunctionEffectSpecifiersSyntax {
        signature.effectSpecifiers
            ?? FunctionEffectSpecifiersSyntax(
                leadingTrivia: .space,
                asyncSpecifier: nil,
                throwsClause: nil
            )
    }

    /// The function with the `async` specifier added or removed.
    func withAsyncModifier(_ isPresent: Bool = true) -> FunctionDeclSyntax {
        with(
            \.signature,
            signature.with(
                \.effectSpecifiers,
                effectSpecifiersOrDefault.with(
                    \.asyncSpecifier,
                    isPresent ? .keyword(.async) : nil
                )
            )
        )
    }

    /// The function with the `throws` specifier added or removed.
    func withThrowsModifier(_ isPresent: Bool = true) -> FunctionDeclSyntax {
        with(
            \.signature,
            signature.with(
                \.effectSpecifiers,
                effectSpecifiersOrDefault.with(
                    \.throwsClause,
                    isPresent ? ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws)) : nil
                )
            )
        )
    }

    /// The function with its parameter list replaced.
    func withParameters(_ parameters: some Sequence<FunctionParameterSyntax>) -> FunctionDeclSyntax {
        with(
            \.signature,
            signature.with(
                \.parameterClause,
                FunctionParameterClauseSyntax(parameters: parameters.asParameterList)
            )
        )
    }

    /// The function with its return clause replaced, or removed when `type` is `nil`.
    func withReturnType(_ type: TypeSyntax?) -> FunctionDeclSyntax {
        guard let type else {
            return with(\.signature, signature.with(\.returnClause, nil))
        }
        return with(
            \.signature,
            signature.with(
                \.returnClause,
                ReturnClauseSyntax(leadingTrivia: .space, type: type.trimmed)
            )
        )
    }

    /// The function with its body replaced.
    func withBody(_ codeBlock: CodeBlockSyntax) -> FunctionDeclSyntax {
        with(\.body, codeBlock)
    }

    /// The function with its body replaced by the given expressions.
    func withBody(_ expressions: [ExprSyntax]) -> FunctionDeclSyntax {
        with(\.body, CodeBlockSyntax(expressions))
    }

    /// The function with its attribute list replaced.
    func withAttributes(_ attributes: AttributeListSyntax) -> FunctionDeclSyntax {
        with(\.attributes, attributes)
    }

    /// The function preceded by a blank line, so peers read as separate declarations.
    func withLeadingBlankLine() -> FunctionDeclSyntax {
        with(\.leadingTrivia, .newlines(2))
    }
}

extension CodeBlockSyntax {
    /// Builds a code block whose statements are the given expressions.
    init(_ expressions: [ExprSyntax]) {
        self.init(
            leftBrace: .leftBraceToken(leadingTrivia: .space),
            statements: CodeBlockItemListSyntax(
                expressions.map { CodeBlockItemSyntax(item: .expr($0)) }
            ),
            rightBrace: .rightBraceToken(leadingTrivia: .newline)
        )
    }
}
