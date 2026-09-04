import SwiftSyntax

// Attribute- and declaration-reading helpers shared by `@Loggable` and
// `@Signpostable`. They started out `private` inside `LoggableMacro.swift`;
// since Swift's `private` is file-scoped, `@Signpostable` could not reach them
// from its own file, and copying them would have left two drifting parsers for
// the same attribute grammar (both macros take the same
// `(AccessLevel, asProtocolRequirement:, subsystem:, category:)` shape).

/// Indents every non-empty line of `source` by `spaces`.
func indent(_ source: String, by spaces: Int) -> String {
    let prefix = String(repeating: " ", count: spaces)
    return source
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in line.isEmpty ? String(line) : prefix + line }
        .joined(separator: "\n")
}

/// The declared name of a type declaration, used as the default subsystem and
/// category on concrete types.
func staticTypeName(from declaration: some DeclGroupSyntax) -> String {
    if let structDeclaration = declaration.as(StructDeclSyntax.self) {
        return structDeclaration.name.trimmedDescription
    } else if let classDeclaration = declaration.as(ClassDeclSyntax.self) {
        return classDeclaration.name.trimmedDescription
    } else if let enumDeclaration = declaration.as(EnumDeclSyntax.self) {
        return enumDeclaration.name.trimmedDescription
    } else if let actorDeclaration = declaration.as(ActorDeclSyntax.self) {
        return actorDeclaration.name.trimmedDescription
    } else if let protocolDeclaration = declaration.as(ProtocolDeclSyntax.self) {
        return protocolDeclaration.name.trimmedDescription
    }
    return "Unknown"
}

func quoteString(_ value: String) -> String {
    "\"\(value)\""
}

/// Extracts the access level from the macro attribute, defaulting to `"private"`.
/// Only considers the first positional (unlabeled) argument.
func extractAccessLevel(from node: AttributeSyntax) -> String {
    guard let arguments = node.arguments,
          case let .argumentList(argumentList) = arguments,
          let firstArgument = argumentList.first,
          firstArgument.label == nil,
          let memberAccess = firstArgument.expression.as(MemberAccessExprSyntax.self) else {
        return "private"
    }
    return memberAccess.declName.baseName.text
}

/// Reads the access modifier off the declaration itself (e.g. `public protocol P`).
/// Falls back to `"internal"` when none is present.
func protocolAccessLevel(from declaration: some DeclGroupSyntax) -> String {
    for modifier in declaration.modifiers {
        let text = modifier.name.text
        switch text {
        case "open", "public", "package", "internal", "fileprivate", "private":
            return text
        default:
            continue
        }
    }
    return "internal"
}

/// Extracts a string literal argument by its label, returning the raw source form
/// (including quotes). Returns `nil` when the label is missing or the argument is
/// not a string literal.
func extractStringLiteral(labeled label: String, from node: AttributeSyntax) -> String? {
    guard let arguments = node.arguments,
          case let .argumentList(argumentList) = arguments else {
        return nil
    }
    for argument in argumentList {
        if argument.label?.text == label,
           let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
            return stringLiteral.trimmedDescription
        }
    }
    return nil
}

/// Extracts a boolean literal argument by its label.
/// Returns `nil` when the label is missing or the value is not a boolean literal.
func extractBoolLiteral(labeled label: String, from node: AttributeSyntax) -> Bool? {
    guard let arguments = node.arguments,
          case let .argumentList(argumentList) = arguments else {
        return nil
    }
    for argument in argumentList {
        guard argument.label?.text == label,
              let booleanLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) else {
            continue
        }
        return booleanLiteral.literal.text == "true"
    }
    return nil
}

/// Extracts an argument by its label as raw source text, whatever expression it
/// is. Unlike ``extractStringLiteral(labeled:from:)`` and
/// ``extractBoolLiteral(labeled:from:)`` this does not require a literal — the
/// text is transplanted into the expansion and re-type-checked there.
func extractExpression(labeled label: String, from node: AttributeSyntax) -> ExprSyntax? {
    guard let arguments = node.arguments,
          case let .argumentList(argumentList) = arguments else {
        return nil
    }
    for argument in argumentList where argument.label?.text == label {
        return argument.expression
    }
    return nil
}

// MARK: - The `isEnabled:` switch

/// How an `isEnabled:` argument resolves at expansion time.
///
/// The three cases are what let one spelling serve both a compile-time kill
/// switch and a runtime flag: a literal collapses to a constant the optimizer
/// can act on, anything else is left as an expression evaluated per call site.
enum EnablementConfiguration {
    /// No argument, or the literal `true`. The runtime switches decide alone.
    case runtimeControlled

    /// The literal `false`. The generated handles become `.disabled` constants
    /// and no runtime switch can turn them back on.
    case alwaysDisabled

    /// Any other expression, kept as source text and combined with the runtime
    /// switches by `&&`.
    case conditional(String)
}

func extractEnablement(from node: AttributeSyntax) -> EnablementConfiguration {
    guard let expression = extractExpression(labeled: "isEnabled", from: node) else {
        return .runtimeControlled
    }
    if let booleanLiteral = expression.as(BooleanLiteralExprSyntax.self) {
        return booleanLiteral.literal.text == "true" ? .runtimeControlled : .alwaysDisabled
    }
    return .conditional(expression.trimmedDescription)
}

extension EnablementConfiguration {
    /// The condition a generated accessor tests before handing back a live
    /// handle, or `nil` when the answer is statically "never".
    ///
    /// - Parameters:
    ///   - switchEntryPoint: the runtime helper to consult, e.g.
    ///     `"LoggableMacro._isEnabled"`.
    ///   - categoryExpression: what to pass it as the category.
    func condition(switchEntryPoint: String, categoryExpression: String) -> String? {
        let runtimeCheck = "\(switchEntryPoint)(category: \(categoryExpression))"
        switch self {
        case .runtimeControlled:
            return runtimeCheck
        case .alwaysDisabled:
            return nil
        case let .conditional(expression):
            return "(\(expression)) && \(runtimeCheck)"
        }
    }

    /// Whether a `static let` holding the live handle is worth emitting at all.
    var needsEnabledHandleStorage: Bool {
        switch self {
        case .runtimeControlled, .conditional:
            return true
        case .alwaysDisabled:
            return false
        }
    }
}

// MARK: - Generic context

/// Whether the declaration sits somewhere Swift forbids static stored
/// properties — inside a generic type, at any depth.
///
/// This is what decides between the two shapes of the concrete branch: caching
/// the live handle in a `static let` (cheapest, but illegal in a generic type)
/// or resolving it through the metatype-keyed runtime cache the protocol branch
/// already uses. Note that nesting a *non-generic* type inside a generic one is
/// enough to trigger the restriction:
///
///     struct Box<Element> {
///         struct Inner {
///             static let stored = 1  // error: static stored properties not
///                                    // supported in generic types
///         }
///     }
///
/// The declaration's own syntax tree cannot show that, which is why the
/// enclosing declarations have to come from `MacroExpansionContext`.
func isInGenericContext(
    declaration: some DeclGroupSyntax,
    lexicalContext: [Syntax]
) -> Bool {
    if genericParameterClause(of: declaration) != nil {
        return true
    }
    return lexicalContext.contains { enclosingSyntax in
        // An `extension` cannot be resolved from syntax alone: `extension Box`
        // says nothing about whether `Box` is generic. Assume the restricting
        // case — a needless runtime cache lookup costs a few nanoseconds, a
        // wrong `static let` costs a compile error in the caller's file.
        if enclosingSyntax.is(ExtensionDeclSyntax.self) {
            return true
        }
        if let enclosingDeclaration = enclosingSyntax.asProtocol(DeclGroupSyntax.self) {
            return genericParameterClause(of: enclosingDeclaration) != nil
        }
        if let enclosingFunction = enclosingSyntax.as(FunctionDeclSyntax.self) {
            return enclosingFunction.genericParameterClause != nil
        }
        return false
    }
}

/// The generic parameter list of a type declaration, if it has one.
/// Protocols are excluded on purpose — they carry `associatedtype`s rather than
/// generic parameters, and nothing can be nested inside them anyway.
private func genericParameterClause(of declaration: some DeclGroupSyntax) -> GenericParameterClauseSyntax? {
    if let structDeclaration = declaration.as(StructDeclSyntax.self) {
        return structDeclaration.genericParameterClause
    } else if let classDeclaration = declaration.as(ClassDeclSyntax.self) {
        return classDeclaration.genericParameterClause
    } else if let enumDeclaration = declaration.as(EnumDeclSyntax.self) {
        return enumDeclaration.genericParameterClause
    } else if let actorDeclaration = declaration.as(ActorDeclSyntax.self) {
        return actorDeclaration.genericParameterClause
    }
    return nil
}
