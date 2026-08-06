import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@RuntimeClassHook("ClassName")`
///
/// MemberMacro. Generates:
/// * `runtimeClassName` — the target class name, for diagnostics and lookups.
/// * `host` / `originalImplementation` storage plus the matching initialiser.
/// * `descriptors()` — one `RuntimeMethodHook.Descriptor` per method tagged
///   with `@RuntimeMethodReplacement`, each carrying a selector derived from
///   the Swift signature, a type encoding derived from the Swift types, and a
///   `@convention(block)` trampoline built over the same signature.
/// * `install()` — hands the batch to `RuntimeMethodHook.installAtomically`.
public enum RuntimeClassHookMacro {}

/// The name reported in this macro family's diagnostics.
let runtimeReplacementMacroName = "@RuntimeMethodReplacement"
let runtimeClassHookMacroName = "@RuntimeClassHook"

extension RuntimeClassHookMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let hookTypeName = validateRuntimeHookContainer(declaration, attribute: node, in: context) else {
            return []
        }
        guard let className = parseClassNameArgument(node, in: context) else {
            return []
        }

        let methods = collectReplacementMethods(in: declaration, attribute: node, in: context)

        var generated: [DeclSyntax] = []

        generated.append("""
        static let runtimeClassName: String = \(literal: className)
        """)

        generated.append("""
        let host: AnyObject
        """)

        generated.append("""
        let originalImplementation: IMP
        """)

        generated.append("""
        init(host: AnyObject, originalImplementation: IMP) {
            self.host = host
            self.originalImplementation = originalImplementation
        }
        """)

        let descriptorEntries = buildDescriptorEntries(
            methods: methods,
            className: className,
            hookTypeName: hookTypeName
        )
        generated.append("""
        static func descriptors() -> [ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor] {
            \(raw: descriptorEntries)
        }
        """)

        generated.append("""
        static func install() throws {
            try ObjCRuntimeToolbox.RuntimeMethodHook.installAtomically(descriptors())
        }
        """)

        return generated
    }
}

// MARK: - Container Validation

private func validateRuntimeHookContainer(
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
            "invalidRuntimeHookContainer",
            """
            \(runtimeClassHookMacroName) can only be applied to a struct or class, not a \(kind). \
            The container is constructed around the receiver on every invocation, so it needs stored properties.
            """
        ),
        at: attribute
    )
    return nil
}

// MARK: - Argument Parsing

private func parseClassNameArgument(
    _ node: AttributeSyntax,
    in context: some MacroExpansionContext
) -> String? {
    guard let argumentList = node.arguments?.as(LabeledExprListSyntax.self),
          let firstArgument = argumentList.first
    else {
        context.emit(
            .error(
                "missingRuntimeClassName",
                "\(runtimeClassHookMacroName) requires the target class name, e.g. \(runtimeClassHookMacroName)(\"NSStatusBarWindow\")."
            ),
            at: node
        )
        return nil
    }

    guard let className = extractStringLiteral(from: firstArgument.expression) else {
        context.emit(
            .error(
                "runtimeClassNameMustBeStringLiteral",
                "\(runtimeClassHookMacroName): the class name must be a string literal — it is resolved with objc_getClass at install time."
            ),
            at: firstArgument.expression
        )
        return nil
    }

    guard !className.isEmpty else {
        context.emit(
            .error(
                "runtimeClassNameEmpty",
                "\(runtimeClassHookMacroName): the class name must not be empty."
            ),
            at: firstArgument.expression
        )
        return nil
    }

    return className
}

/// Everything `@RuntimeMethodReplacement(...)` can carry.
struct ReplacementMarker {
    let attribute: AttributeSyntax
    let explicitSelector: String?
    let explicitTypeEncoding: String?
    let isClassMethod: Bool
}

func parseReplacementMarker(from attribute: AttributeSyntax) -> ReplacementMarker {
    var explicitSelector: String?
    var explicitTypeEncoding: String?
    var isClassMethod = false

    if let argumentList = attribute.arguments?.as(LabeledExprListSyntax.self) {
        for argument in argumentList {
            switch argument.label?.text {
            case nil:
                explicitSelector = extractStringLiteral(from: argument.expression)
            case "typeEncoding":
                explicitTypeEncoding = extractStringLiteral(from: argument.expression)
            case "isClassMethod":
                isClassMethod = argument.expression.trimmedDescription == "true"
            default:
                continue
            }
        }
    }

    return ReplacementMarker(
        attribute: attribute,
        explicitSelector: explicitSelector,
        explicitTypeEncoding: explicitTypeEncoding,
        isClassMethod: isClassMethod
    )
}

// MARK: - Member Walking

private struct CollectedReplacement {
    let shape: FunctionShape
    let marker: ReplacementMarker
    let blockName: String
}

private func collectReplacementMethods(
    in declaration: some DeclGroupSyntax,
    attribute: AttributeSyntax,
    in context: some MacroExpansionContext
) -> [CollectedReplacement] {
    var collected: [CollectedReplacement] = []
    var seenSelectors: [String: FunctionDeclSyntax] = [:]
    var index = 0

    for member in declaration.memberBlock.members {
        guard let functionDeclaration = member.decl.as(FunctionDeclSyntax.self) else { continue }
        guard let markerAttribute = findAttribute(named: "RuntimeMethodReplacement", on: functionDeclaration) else {
            // Untagged — an ordinary Swift helper. Leave it alone.
            continue
        }

        let marker = parseReplacementMarker(from: markerAttribute)
        let shape = FunctionShape(from: functionDeclaration)
        let selectorString = shape.selectorString(explicitSelector: marker.explicitSelector)

        if let previous = seenSelectors[selectorString] {
            context.emit(
                .error(
                    "duplicateRuntimeSelector",
                    """
                    \(runtimeReplacementMacroName): selector '\(selectorString)' is already declared by '\(previous.name.text)'. \
                    Installing the same method twice would chain the replacements, so each one's original would be the other's replacement.
                    """
                ),
                at: functionDeclaration.name
            )
            index += 1
            continue
        }
        seenSelectors[selectorString] = functionDeclaration

        // The index keeps block names unique even when the Swift base name
        // collides across overloads differing only in parameter labels.
        collected.append(CollectedReplacement(
            shape: shape,
            marker: marker,
            blockName: "replacementBlock_\(shape.baseName)_\(index)"
        ))
        index += 1
    }

    if collected.isEmpty {
        context.emit(
            .warning(
                "noReplacementMethodsTagged",
                """
                \(runtimeClassHookMacroName): no methods are tagged with \(runtimeReplacementMacroName). \
                descriptors() will be empty and install() will replace nothing. \
                Did you forget to tag your replacement methods?
                """
            ),
            at: attribute
        )
    }

    return collected
}

// MARK: - Code Emission

private func buildDescriptorEntries(
    methods: [CollectedReplacement],
    className: String,
    hookTypeName: String
) -> String {
    if methods.isEmpty {
        return "[]"
    }

    // The array literal is interpolated into a `descriptors()` body that is
    // itself indented one level, so every line after the first carries its
    // indentation explicitly.
    let entryIndentation = String(repeating: " ", count: 8)
    let fieldIndentation = String(repeating: " ", count: 12)
    let blockIndentation = String(repeating: " ", count: 16)

    let entries = methods.map { method -> String in
        let selectorString = method.shape.selectorString(explicitSelector: method.marker.explicitSelector)
        let typeEncoding = method.marker.explicitTypeEncoding ?? ObjCTypeEncoding.methodEncoding(
            returnTypeText: method.shape.returnTypeText,
            parameterTypeTexts: method.shape.parameters.map { $0.typeText }
        )
        let blockSignature = method.shape.blockSignatureText(baseTypeText: "AnyObject")
        let blockBody = buildReplacementBlockBody(shape: method.shape, hookTypeName: hookTypeName)

        let lines = [
            "\(entryIndentation)ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor(",
            "\(fieldIndentation)className: \(stringLiteral(className)),",
            "\(fieldIndentation)selector: NSSelectorFromString(\(stringLiteral(selectorString))),",
            "\(fieldIndentation)isInstanceMethod: \(method.marker.isClassMethod ? "false" : "true"),",
            "\(fieldIndentation)expectedTypeEncoding: \(stringLiteral(typeEncoding)),",
            "\(fieldIndentation)makeReplacement: { originalImplementation in",
            "\(blockIndentation)let \(method.blockName): @convention(block) \(blockSignature) = \(blockBody)",
            "\(blockIndentation)return imp_implementationWithBlock(\(method.blockName) as AnyObject)",
            "\(fieldIndentation)}",
            "\(entryIndentation)),",
        ]
        return lines.joined(separator: "\n")
    }.joined(separator: "\n")

    return "[\n\(entries)\n    ]"
}

/// The trampoline body: rebuild the container around this invocation's receiver
/// and the implementation being displaced, then call the user's method.
private func buildReplacementBlockBody(
    shape: FunctionShape,
    hookTypeName: String
) -> String {
    let receiverParameterName = "hostObject"
    let argumentParameterNames = shape.parameters.enumerated().map { index, _ in "argument\(index)" }
    let closureParameterNames = ([receiverParameterName] + argumentParameterNames).joined(separator: ", ")

    let callArguments = shape.parameters.enumerated().map { index, parameter in
        let argumentName = "argument\(index)"
        return parameter.externalLabel == "_" ? argumentName : "\(parameter.externalLabel): \(argumentName)"
    }.joined(separator: ", ")

    return "{ \(closureParameterNames) in \(hookTypeName)(host: \(receiverParameterName), originalImplementation: originalImplementation).\(shape.baseName)(\(callArguments)) }"
}

/// Emits a Swift string literal, escaping what a selector or encoding can
/// legitimately contain.
func stringLiteral(_ value: String) -> String {
    let escaped = value
        .replacingEvery("\\", with: "\\\\")
        .replacingEvery("\"", with: "\\\"")
    return "\"\(escaped)\""
}
