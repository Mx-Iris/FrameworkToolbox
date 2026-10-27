import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Distinguishes the two dyld interposing macros. Both emit the very same
/// `(replacement, replacee)` tuple of `@convention(c)` function pointers —
/// the layout `dyld_interpose_tuple` has always had — and differ only in the
/// Mach-O section the tuple lands in and in how the generated constant is
/// named.
///
/// `@DyldInterpose` targets `__DATA,__interpose`, which dyld itself consumes
/// at load time. `@DyldDynamicInterpose` targets a private section that dyld
/// ignores, leaving it to `DyldDynamicInterpose` in `SwiftStdlibToolbox` to
/// read back and apply at a moment of the program's choosing.
struct DyldInterposeExpansionConfiguration {
    /// Spelling used in diagnostics, e.g. `@DyldInterpose`.
    let attributeName: String

    /// Mach-O `segment,section` pair the tuple is placed in.
    let sectionName: String

    /// Prefix of the generated constant, e.g. `_dyldInterpose_`.
    let constantNamePrefix: String
}

enum DyldInterposeSupport {
    /// Builds the section-placed tuple both interposing macros expand to.
    static func makeInterposeTupleDeclarations(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        configuration: DyldInterposeExpansionConfiguration,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let functionDeclaration = declaration.as(FunctionDeclSyntax.self) else {
            throw DyldInterposeMacroError.requiresFunction(attributeName: configuration.attributeName)
        }

        guard let targetFunctionExpression = parseTargetArgument(from: node) else {
            throw DyldInterposeMacroError.missingTargetArgument(attributeName: configuration.attributeName)
        }

        try validateFunctionDeclaration(functionDeclaration, attributeName: configuration.attributeName)

        let replacementName = functionDeclaration.name.text
        let cFunctionType = buildCFunctionType(from: functionDeclaration.signature)
        let constantName = configuration.constantNamePrefix + replacementName
        let targetExpressionDescription = targetFunctionExpression.trimmedDescription
        let tuple = "private let \(constantName): (\(cFunctionType), \(cFunctionType)) = (\(replacementName), \(targetExpressionDescription))"

        // When the replacement's signature does not match the replacee's, the
        // type error is raised on the tuple — code the caller never wrote. A
        // `#sourceLocation` pointing at the attribute puts it on the line that
        // names the replacee instead. The directive sets the line of the line
        // that follows it, so each branch carries the declaration on a single
        // line right after it, attributes included.
        let lineDirectives = sourceLocationDirectives(for: node, in: context)
        let generatedDeclaration: DeclSyntax = """
        #if canImport(Darwin)
        #if compiler(>=6.3)
        \(raw: lineDirectives.opening)@section("\(raw: configuration.sectionName)") @used \(raw: tuple)\(raw: lineDirectives.closing)
        #else
        \(raw: lineDirectives.opening)@_section("\(raw: configuration.sectionName)") @_used \(raw: tuple)\(raw: lineDirectives.closing)
        #endif
        #endif
        """

        return [generatedDeclaration]
    }

    /// The `#sourceLocation` lines to wrap the tuple in, or empty strings when
    /// the expansion context cannot say where the attribute is.
    private static func sourceLocationDirectives(
        for node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> (opening: String, closing: String) {
        guard let location = context.location(of: node, at: .afterLeadingTrivia, filePathMode: .filePath) else {
            return ("", "")
        }
        return (
            "#sourceLocation(file: \(location.file), line: \(location.line))\n",
            "\n#sourceLocation()"
        )
    }

    static func parseTargetArgument(from attribute: AttributeSyntax) -> ExprSyntax? {
        guard let argumentList = attribute.arguments?.as(LabeledExprListSyntax.self),
              let firstArgument = argumentList.first
        else {
            return nil
        }
        return firstArgument.expression
    }

    static func validateFunctionDeclaration(
        _ functionDeclaration: FunctionDeclSyntax,
        attributeName: String
    ) throws {
        if functionDeclaration.genericParameterClause != nil {
            throw DyldInterposeMacroError.genericFunctionUnsupported(attributeName: attributeName)
        }
        if functionDeclaration.genericWhereClause != nil {
            throw DyldInterposeMacroError.genericFunctionUnsupported(attributeName: attributeName)
        }

        let effectSpecifiers = functionDeclaration.signature.effectSpecifiers
        if effectSpecifiers?.throwsClause != nil {
            throw DyldInterposeMacroError.effectfulFunctionUnsupported(attributeName: attributeName, effect: "throws")
        }
        if effectSpecifiers?.asyncSpecifier != nil {
            throw DyldInterposeMacroError.effectfulFunctionUnsupported(attributeName: attributeName, effect: "async")
        }

        for parameter in functionDeclaration.signature.parameterClause.parameters {
            if let attributedType = parameter.type.as(AttributedTypeSyntax.self) {
                for specifier in attributedType.specifiers {
                    if let simpleSpecifier = specifier.as(SimpleTypeSpecifierSyntax.self),
                       simpleSpecifier.specifier.tokenKind == .keyword(.inout) {
                        throw DyldInterposeMacroError.inoutParameterUnsupported(attributeName: attributeName)
                    }
                }
            }
        }
    }

    static func buildCFunctionType(from signature: FunctionSignatureSyntax) -> String {
        let parameterTypeDescriptions = signature.parameterClause.parameters.map { parameter in
            parameter.type.trimmedDescription
        }
        let parameterList = parameterTypeDescriptions.joined(separator: ", ")
        let returnTypeDescription = signature.returnClause?.type.trimmedDescription ?? "Void"
        return "@convention(c) (\(parameterList)) -> \(returnTypeDescription)"
    }
}

enum DyldInterposeMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case requiresFunction(attributeName: String)
    case missingTargetArgument(attributeName: String)
    case genericFunctionUnsupported(attributeName: String)
    case effectfulFunctionUnsupported(attributeName: String, effect: String)
    case inoutParameterUnsupported(attributeName: String)

    var description: String {
        switch self {
        case .requiresFunction(let attributeName):
            return "\(attributeName) can only be applied to a function declaration."
        case .missingTargetArgument(let attributeName):
            return "\(attributeName) requires the function being replaced as its first argument, e.g. \(attributeName)(malloc)."
        case .genericFunctionUnsupported(let attributeName):
            return "\(attributeName) cannot be applied to a generic function because @convention(c) function types do not support generics."
        case .effectfulFunctionUnsupported(let attributeName, let effect):
            return "\(attributeName) cannot be applied to a function marked `\(effect)` because @convention(c) function types do not support effects."
        case .inoutParameterUnsupported(let attributeName):
            return "\(attributeName) cannot be applied to a function with `inout` parameters because @convention(c) function types do not support `inout`."
        }
    }

    var message: String { description }

    var diagnosticID: MessageID {
        let diagnosticName: String
        switch self {
        case .requiresFunction:
            diagnosticName = "requiresFunction"
        case .missingTargetArgument:
            diagnosticName = "missingTargetArgument"
        case .genericFunctionUnsupported:
            diagnosticName = "genericFunctionUnsupported"
        case .effectfulFunctionUnsupported:
            diagnosticName = "effectfulFunctionUnsupported"
        case .inoutParameterUnsupported:
            diagnosticName = "inoutParameterUnsupported"
        }
        return MessageID(domain: "DyldInterposeMacroError", id: diagnosticName)
    }

    var severity: DiagnosticSeverity { .error }
}
