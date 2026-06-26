import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@DynamicSubclassHook(of: BaseClass.self, suffix: "...", adopts: [Protocol.self, ...])`
///
/// MemberMacro. Generates:
/// * `base` storage + memberwise `init(base:)`
/// * `install(on:)` / `uninstall(from:)` static entry points
/// * `dynamicSubclass(for:)` lifecycle helper
/// * `installOverridesIfNeeded(on:)` registry with one IMP-bridge block per
///   `@DynamicSubclassOverride`-tagged instance method, plus
///   `class_addProtocol` calls for every type listed in `adopts:`.
public enum DynamicSubclassHookMacro {}

extension DynamicSubclassHookMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // 1. Container shape — must be struct or class.
        guard let hookTypeName = validateHookContainer(declaration, attribute: node, in: context) else {
            return []
        }

        // 2. Attribute arguments.
        guard let arguments = parseAttributeArguments(node, in: context) else {
            return []
        }

        // 3. Walk members: diagnose non-func members (warning), collect
        //    @DynamicSubclassOverride-tagged methods (with their explicit
        //    selectors), reject baseline-selector collisions and intra-hook
        //    selector / block-name duplication.
        let methods = collectAndDiagnoseMembers(
            in: declaration,
            attribute: node,
            in: context
        )

        // 4. Emit generated members.
        var generated: [DeclSyntax] = []

        generated.append("""
        let base: \(raw: arguments.baseTypeText)
        """)
        generated.append("""
        init(base: \(raw: arguments.baseTypeText)) { self.base = base }
        """)

        generated.append("""
        public static func install(on instance: \(raw: arguments.baseTypeText)) {
            guard let dynamicSubclassValue = dynamicSubclass(for: instance) else { return }
            ObjCRuntimeToolbox.DynamicSubclass.retain(instance, dynamicSubclass: dynamicSubclassValue)
        }
        """)

        generated.append("""
        public static func uninstall(from instance: \(raw: arguments.baseTypeText)) {
            ObjCRuntimeToolbox.DynamicSubclass.release(instance)
        }
        """)

        generated.append("""
        public static func dynamicSubclass(for instance: \(raw: arguments.baseTypeText)) -> AnyClass? {
            let baseClass: AnyClass = ObjCRuntimeToolbox.DynamicSubclass.originalClass(of: instance)
            let dynamicSubclassValue: AnyClass
            do {
                dynamicSubclassValue = try ObjCRuntimeToolbox.DynamicSubclass.getOrCreate(of: baseClass, suffix: \(literal: arguments.suffix))
            } catch {
                ObjCRuntimeToolbox.DynamicSubclass.logAllocationFailure(error, baseClass: baseClass)
                return nil
            }
            installOverridesIfNeeded(on: dynamicSubclassValue)
            return dynamicSubclassValue
        }
        """)

        let installOverridesBody = buildInstallOverridesBody(
            methods: methods,
            arguments: arguments,
            hookTypeName: hookTypeName
        )
        generated.append("""
        private static func installOverridesIfNeeded(on dynamicSubclass: AnyClass) {
            guard ObjCRuntimeToolbox.DynamicSubclass.claimOverrideInstallation(on: dynamicSubclass, hookIdentifier: \(literal: hookTypeName)) else { return }
            \(raw: installOverridesBody)
        }
        """)

        return generated
    }
}

// MARK: - Container Validation

private func validateHookContainer(
    _ declaration: some DeclGroupSyntax,
    attribute: AttributeSyntax,
    in context: some MacroExpansionContext
) -> String? {
    if let structDeclaration = declaration.as(StructDeclSyntax.self) {
        return structDeclaration.name.text
    }
    if let classDeclaration = declaration.as(ClassDeclSyntax.self) {
        return classDeclaration.name.text
    }
    let kind: String
    if declaration.is(EnumDeclSyntax.self) { kind = "enum" }
    else if declaration.is(ActorDeclSyntax.self) { kind = "actor" }
    else if declaration.is(ExtensionDeclSyntax.self) { kind = "extension" }
    else if declaration.is(ProtocolDeclSyntax.self) { kind = "protocol" }
    else { kind = "declaration" }
    context.emit(
        .error(
            "invalidHookContainer",
            "@DynamicSubclassHook can only be applied to a struct or class, not a \(kind)."
        ),
        at: attribute
    )
    return nil
}

// MARK: - Member Walking

private struct CollectedMethod {
    let declaration: FunctionDeclSyntax
    let shape: FunctionShape
    let explicitSelector: String?
    let blockName: String
}

private func collectAndDiagnoseMembers(
    in declaration: some DeclGroupSyntax,
    attribute: AttributeSyntax,
    in context: some MacroExpansionContext
) -> [CollectedMethod] {
    var collected: [CollectedMethod] = []
    var seenSelectors: [String: FunctionDeclSyntax] = [:]
    var index = 0

    for member in declaration.memberBlock.members {
        if let functionDeclaration = member.decl.as(FunctionDeclSyntax.self) {
            if isStaticOrClassMethod(functionDeclaration) { continue }
            guard let marker = extractOverrideMarker(from: functionDeclaration) else {
                // Plain Swift helper — keep the source untouched.
                continue
            }
            let shape = FunctionShape(from: functionDeclaration)
            let selectorString = shape.selectorString(explicitSelector: marker.explicitSelector)

            if BASELINE_SELECTORS.contains(selectorString) {
                context.emit(
                    .error(
                        "baselineSelectorReserved",
                        """
                        @DynamicSubclassOverride: '\(selectorString)' is reserved for the dynamic subclass's baseline overrides (-class / -respondsToSelector: / -conformsToProtocol:). \
                        Choose a different selector or omit this method.
                        """
                    ),
                    at: functionDeclaration.name
                )
                index += 1
                continue
            }

            if let previous = seenSelectors[selectorString] {
                context.emit(
                    .error(
                        "duplicateSelector",
                        """
                        @DynamicSubclassOverride: selector '\(selectorString)' already declared by '\(previous.name.text)'. \
                        ObjC selectors must be unique within a single hook.
                        """
                    ),
                    at: functionDeclaration.name
                )
                index += 1
                continue
            }
            seenSelectors[selectorString] = functionDeclaration

            // Index makes block names unique even when Swift baseName collides
            // (e.g. overloads on parameter labels).
            let blockName = "block_\(shape.baseName)_\(index)"
            collected.append(CollectedMethod(
                declaration: functionDeclaration,
                shape: shape,
                explicitSelector: marker.explicitSelector,
                blockName: blockName
            ))
            index += 1
            continue
        }

        // Non-func members: init / deinit / subscript / var / typealias / ...
        // Static / class methods are also surfaced here when filtered above —
        // we don't warn on them as they're a legit hook-side organisational
        // tool.
        if member.decl.is(InitializerDeclSyntax.self)
            || member.decl.is(DeinitializerDeclSyntax.self)
            || member.decl.is(SubscriptDeclSyntax.self)
            || member.decl.is(VariableDeclSyntax.self)
        {
            context.emit(
                .warning(
                    "nonFuncMemberIgnored",
                    "@DynamicSubclassHook: only func declarations can be hooked. This member will not be installed as an ObjC override."
                ),
                at: member.decl
            )
        }
    }

    if collected.isEmpty {
        context.emit(
            .warning(
                "noOverrideMethodsTagged",
                """
                @DynamicSubclassHook: no methods are tagged with @DynamicSubclassOverride. \
                The hook will install the dynamic subclass but register no IMP overrides. \
                Did you forget to tag your override methods?
                """
            ),
            at: attribute
        )
    }

    return collected
}

private let BASELINE_SELECTORS: Set<String> = [
    "class",
    "respondsToSelector:",
    "conformsToProtocol:",
]

private func isStaticOrClassMethod(_ functionDeclaration: FunctionDeclSyntax) -> Bool {
    functionDeclaration.modifiers.contains { modifier in
        modifier.name.tokenKind == .keyword(.static) ||
        modifier.name.tokenKind == .keyword(.class)
    }
}

// MARK: - Code Emission

private func buildInstallOverridesBody(
    methods: [CollectedMethod],
    arguments: ParsedHookArguments,
    hookTypeName: String
) -> String {
    let adoptedProtocolEntries = arguments.adoptedProtocolTypeTexts.map { "\($0).self" }.joined(separator: ", ")
    let addProtocolsCall: String
    if arguments.adoptedProtocolTypeTexts.isEmpty {
        addProtocolsCall = ""
    } else {
        addProtocolsCall = """
        ObjCRuntimeToolbox.DynamicSubclass.addProtocols(on: dynamicSubclass, [\(adoptedProtocolEntries)])
        """
    }

    if methods.isEmpty {
        if addProtocolsCall.isEmpty {
            return "// no overrides or protocols declared"
        }
        return addProtocolsCall
    }

    let blockDeclarations = methods.map { method -> String in
        let signatureText = method.shape.blockSignatureText(baseTypeText: arguments.baseTypeText)
        let bodyText = method.shape.blockBodyText(hookTypeName: hookTypeName)
        return "let \(method.blockName): @convention(block) \(signatureText) = \(bodyText)"
    }.joined(separator: "\n            ")

    let descriptorEntries = methods.map { method -> String in
        let selectorString = method.shape.selectorString(explicitSelector: method.explicitSelector)
        return """
            ObjCRuntimeToolbox.DynamicSubclass.Override(selector: NSSelectorFromString("\(selectorString)"), block: \(method.blockName) as AnyObject)
            """
    }.joined(separator: ",\n                ")

    let referenceProtocolEntries = adoptedProtocolEntries
    let protocolsPrefix = addProtocolsCall.isEmpty ? "" : "\(addProtocolsCall)\n            "

    return """
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

// MARK: - Argument Parsing

private struct ParsedHookArguments {
    let baseTypeText: String
    let suffix: String
    let adoptedProtocolTypeTexts: [String]
}

private func parseAttributeArguments(
    _ node: AttributeSyntax,
    in context: some MacroExpansionContext
) -> ParsedHookArguments? {
    guard let argumentList = node.arguments?.as(LabeledExprListSyntax.self), !argumentList.isEmpty else {
        context.emit(
            .error(
                "missingArguments",
                "@DynamicSubclassHook requires 'of:' and 'suffix:' arguments."
            ),
            at: node
        )
        return nil
    }

    var baseTypeText: String?
    var ofArgumentNode: LabeledExprSyntax?
    var suffix: String?
    var suffixArgumentNode: LabeledExprSyntax?
    var adoptedProtocolTypeTexts: [String] = []
    var adoptsArgumentNode: LabeledExprSyntax?

    for argument in argumentList {
        let label = argument.label?.text
        switch label {
        case "of":
            baseTypeText = extractTypeName(from: argument.expression)
            ofArgumentNode = argument
        case "suffix":
            suffix = extractStringLiteral(from: argument.expression)
            suffixArgumentNode = argument
        case "adopts":
            adoptedProtocolTypeTexts = extractTypeNameArray(from: argument.expression)
            adoptsArgumentNode = argument
        case .some(let actualLabel):
            context.emit(
                .error(
                    "unknownAttributeLabel",
                    "@DynamicSubclassHook: unknown argument label '\(actualLabel)'. Expected 'of:', 'suffix:', or 'adopts:'."
                ),
                at: argument
            )
            continue
        case .none:
            continue
        }
    }

    guard let baseTypeText, !baseTypeText.isEmpty else {
        context.emit(
            .error(
                "missingBaseType",
                "@DynamicSubclassHook requires an 'of:' argument naming the base class as '<ClassName>.self'."
            ),
            at: (ofArgumentNode.map { Syntax($0) }) ?? Syntax(node)
        )
        return nil
    }

    guard let suffix else {
        context.emit(
            .error(
                "missingSuffix",
                "@DynamicSubclassHook requires a 'suffix:' string literal."
            ),
            at: (suffixArgumentNode.map { Syntax($0) }) ?? Syntax(node)
        )
        return nil
    }

    // Validate adopts: shape — each element must be `Type.self`.
    if let adoptsArgumentNode {
        if let arrayExpression = adoptsArgumentNode.expression.as(ArrayExprSyntax.self) {
            for element in arrayExpression.elements {
                if !isSelfExpression(element.expression) {
                    context.emit(
                        .error(
                            "adoptsEntryMustBeSelfExpression",
                            "@DynamicSubclassHook: every 'adopts:' entry must be written as '<@objc Protocol>.self'."
                        ),
                        at: element.expression
                    )
                }
            }
        } else if !adoptsArgumentNode.expression.trimmedDescription.isEmpty
            && adoptsArgumentNode.expression.trimmedDescription != "[]"
        {
            context.emit(
                .error(
                    "adoptsMustBeArrayLiteral",
                    "@DynamicSubclassHook: 'adopts:' must be an array literal of '<Protocol>.self' entries."
                ),
                at: adoptsArgumentNode.expression
            )
        }
    }

    return ParsedHookArguments(
        baseTypeText: baseTypeText,
        suffix: suffix,
        adoptedProtocolTypeTexts: adoptedProtocolTypeTexts
    )
}

private func isSelfExpression(_ expression: ExprSyntax) -> Bool {
    guard let memberAccess = expression.as(MemberAccessExprSyntax.self) else { return false }
    return memberAccess.declName.baseName.text == "self"
}

/// Pulls `Foo` out of `Foo.self`. Returns `nil` when the user wrote something
/// that isn't a plain type-of-self access — the caller emits a diagnostic so
/// the user can fix the form.
private func extractTypeName(from expression: ExprSyntax) -> String? {
    if let memberAccess = expression.as(MemberAccessExprSyntax.self),
       memberAccess.declName.baseName.text == "self",
       let baseExpression = memberAccess.base
    {
        return baseExpression.trimmedDescription
    }
    return nil
}

/// Parses `[Foo.self, Bar.self]` into `["Foo", "Bar"]`. Entries that aren't a
/// type-of-self expression are dropped (a diagnostic is emitted separately by
/// the validation pass).
private func extractTypeNameArray(from expression: ExprSyntax) -> [String] {
    guard let arrayExpression = expression.as(ArrayExprSyntax.self) else {
        return []
    }
    return arrayExpression.elements.compactMap { element in
        extractTypeName(from: element.expression)
    }
}
