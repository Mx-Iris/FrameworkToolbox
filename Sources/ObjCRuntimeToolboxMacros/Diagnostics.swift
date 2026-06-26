import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Message

/// All compile-time diagnostics emitted by the `@DynamicSubclassHook` /
/// `@DynamicSubclassOverride` macros. Errors anchor to the offending syntax
/// node so the IDE can underline the actual source rather than the macro
/// expansion buffer.
struct DynamicSubclassMacroDiagnostic: DiagnosticMessage {
    let message: String
    let identifier: String
    let severity: DiagnosticSeverity

    var diagnosticID: MessageID {
        MessageID(domain: "ObjCRuntimeToolbox", id: identifier)
    }

    static func error(_ identifier: String, _ message: String) -> Self {
        Self(message: message, identifier: identifier, severity: .error)
    }

    static func warning(_ identifier: String, _ message: String) -> Self {
        Self(message: message, identifier: identifier, severity: .warning)
    }
}

// MARK: - Reusable Emit Helpers

extension MacroExpansionContext {
    func emit(
        _ diagnostic: DynamicSubclassMacroDiagnostic,
        at node: some SyntaxProtocol
    ) {
        diagnose(Diagnostic(node: Syntax(node), message: diagnostic))
    }
}

// MARK: - Override Attribute Lookup

/// Extracts the `@DynamicSubclassOverride(...)` attribute (and any explicit
/// selector string it carries) from a function declaration. Returns `nil` when
/// the attribute is absent — that's the signal to treat the function as a
/// plain Swift helper, NOT a hook override.
struct OverrideMarker {
    let attribute: AttributeSyntax
    let explicitSelector: String?
}

func extractOverrideMarker(from functionDeclaration: FunctionDeclSyntax) -> OverrideMarker? {
    for attributeListEntry in functionDeclaration.attributes {
        guard let attribute = attributeListEntry.as(AttributeSyntax.self) else { continue }
        let attributeName = attribute.attributeName.trimmedDescription
        // Match both bare `DynamicSubclassOverride` and the fully-qualified
        // `ObjCRuntimeToolbox.DynamicSubclassOverride` form.
        let lastComponent = attributeName.split(separator: ".").last.map(String.init) ?? attributeName
        if lastComponent != "DynamicSubclassOverride" { continue }
        let explicitSelector = extractExplicitSelectorArgument(from: attribute)
        return OverrideMarker(attribute: attribute, explicitSelector: explicitSelector)
    }
    return nil
}

private func extractExplicitSelectorArgument(from attribute: AttributeSyntax) -> String? {
    guard let argumentList = attribute.arguments?.as(LabeledExprListSyntax.self),
          let firstArgument = argumentList.first
    else {
        return nil
    }
    return extractStringLiteral(from: firstArgument.expression)
}

func extractStringLiteral(from expression: ExprSyntax) -> String? {
    guard let stringLiteral = expression.as(StringLiteralExprSyntax.self) else {
        return nil
    }
    var result = ""
    for segment in stringLiteral.segments {
        guard let stringSegment = segment.as(StringSegmentSyntax.self) else {
            return nil
        }
        result += stringSegment.content.text
    }
    return result
}

// MARK: - Function Validation

/// Walk the function signature looking for shapes the runtime cannot honour.
/// Diagnostics are emitted to `context` against the most-specific node so the
/// underline lands on the real source token. Returns `true` when every issue
/// found is non-fatal (warning); `false` when at least one fatal issue means
/// the macro should NOT proceed to generate code that would explode in the
/// expansion buffer.
@discardableResult
func diagnoseUnsupportedFunctionShape(
    _ functionDeclaration: FunctionDeclSyntax,
    in context: some MacroExpansionContext,
    overrideMarker: OverrideMarker?
) -> Bool {
    var canProceed = true

    // 1. Effect specifiers — throws / async cannot bridge through @convention(c).
    if let effects = functionDeclaration.signature.effectSpecifiers {
        if let asyncSpecifier = effects.asyncSpecifier {
            context.emit(
                .error(
                    "asyncNotSupported",
                    "@DynamicSubclassOverride does not support 'async' methods — Objective-C IMP blocks cannot bridge Swift continuations."
                ),
                at: asyncSpecifier
            )
            canProceed = false
        }
        if let throwsClause = effects.throwsClause {
            context.emit(
                .error(
                    "throwsNotSupported",
                    "@DynamicSubclassOverride does not support 'throws' methods. Catch the error inside the hook body instead."
                ),
                at: throwsClause
            )
            canProceed = false
        }
    }

    // 2. Modifiers — mutating / actor isolation cannot land on an IMP block.
    for modifier in functionDeclaration.modifiers {
        switch modifier.name.tokenKind {
        case .keyword(.mutating):
            context.emit(
                .error(
                    "mutatingNotSupported",
                    "@DynamicSubclassOverride does not support 'mutating' methods — the hook container is reconstructed per ObjC invocation."
                ),
                at: modifier
            )
            canProceed = false
        case .keyword(.nonisolated):
            // Allowed — `nonisolated` widens isolation, doesn't add it.
            continue
        case .keyword(.isolated):
            context.emit(
                .error(
                    "actorIsolationNotSupported",
                    "@DynamicSubclassOverride does not support actor-isolated methods."
                ),
                at: modifier
            )
            canProceed = false
        default:
            continue
        }
    }

    // 3. Attributes — @MainActor / other isolation attributes are unsupported.
    for attributeListEntry in functionDeclaration.attributes {
        guard let attribute = attributeListEntry.as(AttributeSyntax.self) else { continue }
        let attributeName = attribute.attributeName.trimmedDescription
        let lastComponent = attributeName.split(separator: ".").last.map(String.init) ?? attributeName
        if lastComponent == "MainActor" {
            context.emit(
                .error(
                    "mainActorNotSupported",
                    "@DynamicSubclassOverride does not support @MainActor methods — the ObjC IMP block does not carry actor isolation."
                ),
                at: attribute
            )
            canProceed = false
        }
    }

    // 4. Parameters — each type must be syntactically ObjC representable.
    for parameter in functionDeclaration.signature.parameterClause.parameters {
        if !diagnoseObjcRepresentable(parameter.type, role: "parameter", in: context) {
            canProceed = false
        }
    }

    // 5. Return type — same checks.
    if let returnClause = functionDeclaration.signature.returnClause {
        let returnTypeText = returnClause.type.trimmedDescription
        if returnTypeText != "Void" && returnTypeText != "()" {
            if !diagnoseObjcRepresentable(returnClause.type, role: "return type", in: context) {
                canProceed = false
            }
        }
    }

    // 6. First-parameter label rule (only when no explicit selector supplied).
    if overrideMarker?.explicitSelector == nil,
       let firstParameter = functionDeclaration.signature.parameterClause.parameters.first
    {
        if firstParameter.firstName.text != "_" {
            context.emit(
                .error(
                    "firstParameterLabelMustBeUnderscore",
                    """
                    @DynamicSubclassOverride: first parameter label must be '_'. \
                    Swift's @objc bridging produces a selector like '<baseName>With<CapitalizedLabel>:' for labelled first parameters, but this macro derives '<baseName><label>:' which won't match. \
                    Either drop the label (use '_'), or pass an explicit selector: @DynamicSubclassOverride("real:selector:").
                    """
                ),
                at: firstParameter.firstName
            )
            canProceed = false
        }
    }

    return canProceed
}

/// Conservative syntactic check for ObjC representability. We can't observe
/// concrete types at macro time, so this checks what we *can* observe from the
/// `TypeSyntax`: `inout`, tuple arity > 0, function-without-`@convention(block)`,
/// and identifier types that look like outer generic parameters.
@discardableResult
private func diagnoseObjcRepresentable(
    _ typeSyntax: TypeSyntax,
    role: String,
    in context: some MacroExpansionContext
) -> Bool {
    if let attributed = typeSyntax.as(AttributedTypeSyntax.self) {
        for specifier in attributed.specifiers {
            switch specifier {
            case .simpleTypeSpecifier(let simpleSpecifier):
                switch simpleSpecifier.specifier.tokenKind {
                case .keyword(.inout), .keyword(.borrowing), .keyword(.consuming):
                    context.emit(
                        .error(
                            "ownershipSpecifierNotSupported",
                            "@DynamicSubclassOverride \(role) cannot use 'inout' / 'borrowing' / 'consuming' — these specifiers don't bridge to @convention(c)."
                        ),
                        at: simpleSpecifier
                    )
                    return false
                default:
                    continue
                }
            default:
                continue
            }
        }
        // The wrapped type still needs checking.
        return diagnoseObjcRepresentable(attributed.baseType, role: role, in: context)
    }

    if let tuple = typeSyntax.as(TupleTypeSyntax.self) {
        if tuple.elements.count != 1 {
            // Non-Void tuple (arity != 1 because empty tuple == Void caught upstream).
            context.emit(
                .error(
                    "tupleNotRepresentable",
                    "@DynamicSubclassOverride \(role) cannot use Swift tuples — Objective-C has no tuple type."
                ),
                at: tuple
            )
            return false
        }
        // Single-element tuple is just a paren-wrapped type — recurse.
        return diagnoseObjcRepresentable(tuple.elements.first!.type, role: role, in: context)
    }

    if let function = typeSyntax.as(FunctionTypeSyntax.self) {
        // Bare Swift closure types are not representable.
        context.emit(
            .error(
                "swiftClosureNotRepresentable",
                "@DynamicSubclassOverride \(role) cannot use bare Swift closure types. If you need an ObjC block, declare it as @convention(block) ... and wrap it with @attribute syntax."
            ),
            at: function
        )
        return false
    }

    return true
}
