import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@DynamicSubclassHook(of: BaseClass.self, suffix: "...", adopts: [Protocol.self, ...])`
///
/// Multi-role attached macro. Combines:
/// * `MemberMacro` — generates `base`, `init(base:)`, `install/uninstall`,
///   `dynamicSubclass(for:)`, and `installOverridesIfNeeded(on:)` with one
///   IMP-bridge block per declared instance method, plus `class_addProtocol`
///   calls for every type listed in `adopts:`.
/// * `MemberAttributeMacro` — tags every instance method on the struct with
///   `@_DynamicSubclassMethodBody` so the body macro can inject typed local
///   `callSuper(...)` / `callSuperIfImplemented(...)` helpers.
public enum DynamicSubclassHookMacro {}

extension DynamicSubclassHookMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let arguments = try parseAttributeArguments(node, in: context)
        let methods = collectInstanceMethods(in: declaration)
        let hookTypeName = resolveHookTypeName(in: declaration)

        var generated: [DeclSyntax] = []

        // 1. base + init
        generated.append("""
        let base: \(raw: arguments.baseTypeText)
        """)
        generated.append("""
        init(base: \(raw: arguments.baseTypeText)) { self.base = base }
        """)

        // 2. install / uninstall / dynamicSubclass(for:)
        generated.append("""
        public static func install(on instance: \(raw: arguments.baseTypeText)) {
            let dynamicSubclassValue = dynamicSubclass(for: instance)
            ObjCRuntimeToolbox.DynamicSubclass.retain(instance, dynamicSubclass: dynamicSubclassValue)
        }
        """)

        generated.append("""
        public static func uninstall(from instance: \(raw: arguments.baseTypeText)) {
            ObjCRuntimeToolbox.DynamicSubclass.release(instance)
        }
        """)

        generated.append("""
        public static func dynamicSubclass(for instance: \(raw: arguments.baseTypeText)) -> AnyClass {
            let baseClass = ObjCRuntimeToolbox.DynamicSubclass.originalClass(of: instance)
            let dynamicSubclassValue = ObjCRuntimeToolbox.DynamicSubclass.getOrCreate(of: baseClass, suffix: \(literal: arguments.suffix))
            installOverridesIfNeeded(on: dynamicSubclassValue)
            return dynamicSubclassValue
        }
        """)

        // 3. installOverridesIfNeeded(on:)
        let blockDeclarations = methods.map { method -> String in
            let shape = FunctionShape(from: method)
            let blockName = "block_\(shape.baseName)"
            let signatureText = shape.blockSignatureText(baseTypeText: arguments.baseTypeText)
            let bodyText = shape.blockBodyText(hookTypeName: hookTypeName)
            return "let \(blockName): @convention(block) \(signatureText) = \(bodyText)"
        }.joined(separator: "\n            ")

        let descriptorEntries = methods.map { method -> String in
            let shape = FunctionShape(from: method)
            let blockName = "block_\(shape.baseName)"
            let selectorString = shape.selectorString
            return """
                ObjCRuntimeToolbox.DynamicSubclass.Override(selector: Selector(("\(selectorString)")), block: \(blockName) as AnyObject)
                """
        }.joined(separator: ",\n                ")

        let adoptedProtocolEntries = arguments.adoptedProtocolTypeTexts.map { "\($0).self" }.joined(separator: ", ")
        let referenceProtocolEntries = adoptedProtocolEntries  // same set used for type-encoding lookup

        let addProtocolsCall: String
        if arguments.adoptedProtocolTypeTexts.isEmpty {
            addProtocolsCall = ""
        } else {
            addProtocolsCall = """
            ObjCRuntimeToolbox.DynamicSubclass.addProtocols(on: dynamicSubclass, [\(adoptedProtocolEntries)])
            """
        }

        let installOverridesBody: String
        if methods.isEmpty && arguments.adoptedProtocolTypeTexts.isEmpty {
            installOverridesBody = "// no overrides or protocols declared"
        } else if methods.isEmpty {
            installOverridesBody = "        \(addProtocolsCall)"
        } else {
            let protocolsPrefix = addProtocolsCall.isEmpty ? "" : "\(addProtocolsCall)\n            "
            installOverridesBody = """
            \(protocolsPrefix)\(blockDeclarations)
                        ObjCRuntimeToolbox.DynamicSubclass.addOverrides(
                            on: dynamicSubclass,
                            referenceClass: \(arguments.baseTypeText).self,
                            referenceProtocols: [\(referenceProtocolEntries)],
                            [
                                \(descriptorEntries)
                            ]
                        )
            """
        }

        generated.append("""
        private static func installOverridesIfNeeded(on dynamicSubclass: AnyClass) {
            \(raw: installOverridesBody)
        }
        """)

        return generated
    }
}

extension DynamicSubclassHookMacro: MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let functionDeclaration = member.as(FunctionDeclSyntax.self),
              !isStaticOrClassMethod(functionDeclaration)
        else {
            return []
        }
        return [
            AttributeSyntax("@ObjCRuntimeToolbox._DynamicSubclassMethodBody")
        ]
    }
}

// MARK: - Argument Parsing

private struct ParsedHookArguments {
    let baseTypeText: String
    let suffix: String
    let adoptedProtocolTypeTexts: [String]
}

private func parseAttributeArguments(
    _ node: AttributeSyntax,
    in context: some MacroExpansionContext
) throws -> ParsedHookArguments {
    guard let argumentList = node.arguments?.as(LabeledExprListSyntax.self),
          argumentList.count >= 2
    else {
        throw DynamicSubclassHookMacroError.missingArguments
    }

    var baseTypeText: String?
    var suffix: String?
    var adoptedProtocolTypeTexts: [String] = []

    for argument in argumentList {
        let label = argument.label?.text
        switch label {
        case "of":
            baseTypeText = extractTypeName(from: argument.expression)
        case "suffix":
            suffix = extractStringLiteral(from: argument.expression)
        case "adopts":
            adoptedProtocolTypeTexts = extractTypeNameArray(from: argument.expression)
        default:
            continue
        }
    }

    guard let baseTypeText else {
        throw DynamicSubclassHookMacroError.missingBaseType
    }
    guard let suffix else {
        throw DynamicSubclassHookMacroError.missingSuffix
    }

    return ParsedHookArguments(
        baseTypeText: baseTypeText,
        suffix: suffix,
        adoptedProtocolTypeTexts: adoptedProtocolTypeTexts
    )
}

/// Pulls `Foo` out of `Foo.self`. Falls back to the trimmed text of the
/// expression when the user wrote something other than a plain type-of-self
/// access — the macro substitutes the text verbatim, no evaluation needed.
private func extractTypeName(from expression: ExprSyntax) -> String? {
    if let memberAccess = expression.as(MemberAccessExprSyntax.self),
       memberAccess.declName.baseName.text == "self",
       let baseExpression = memberAccess.base
    {
        return baseExpression.trimmedDescription
    }
    return expression.trimmedDescription
}

/// Parses `[Foo.self, Bar.self]` into `["Foo", "Bar"]`. Entries that aren't a
/// type-of-self expression are passed through using their trimmed text.
private func extractTypeNameArray(from expression: ExprSyntax) -> [String] {
    guard let arrayExpression = expression.as(ArrayExprSyntax.self) else {
        return []
    }
    return arrayExpression.elements.compactMap { element in
        extractTypeName(from: element.expression)
    }
}

private func extractStringLiteral(from expression: ExprSyntax) -> String? {
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

// MARK: - Declaration Walking

private func collectInstanceMethods(in declaration: some DeclGroupSyntax) -> [FunctionDeclSyntax] {
    declaration.memberBlock.members.compactMap { member -> FunctionDeclSyntax? in
        guard let functionDeclaration = member.decl.as(FunctionDeclSyntax.self) else { return nil }
        if isStaticOrClassMethod(functionDeclaration) { return nil }
        return functionDeclaration
    }
}

private func isStaticOrClassMethod(_ functionDeclaration: FunctionDeclSyntax) -> Bool {
    functionDeclaration.modifiers.contains { modifier in
        modifier.name.tokenKind == .keyword(.static) ||
        modifier.name.tokenKind == .keyword(.class)
    }
}

private func resolveHookTypeName(in declaration: some DeclGroupSyntax) -> String {
    if let structDeclaration = declaration.as(StructDeclSyntax.self) {
        return structDeclaration.name.text
    }
    if let classDeclaration = declaration.as(ClassDeclSyntax.self) {
        return classDeclaration.name.text
    }
    if let enumDeclaration = declaration.as(EnumDeclSyntax.self) {
        return enumDeclaration.name.text
    }
    return "Self"
}

// MARK: - Errors

enum DynamicSubclassHookMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case missingArguments
    case missingBaseType
    case missingSuffix

    var description: String {
        switch self {
        case .missingArguments:
            return "@DynamicSubclassHook requires `of:` and `suffix:` arguments."
        case .missingBaseType:
            return "@DynamicSubclassHook requires an `of:` argument naming the base class."
        case .missingSuffix:
            return "@DynamicSubclassHook requires a `suffix:` string literal."
        }
    }

    var message: String { description }
    var severity: DiagnosticSeverity { .error }
    var diagnosticID: MessageID { MessageID(domain: "ObjCRuntimeToolbox", id: "\(self)") }
}
