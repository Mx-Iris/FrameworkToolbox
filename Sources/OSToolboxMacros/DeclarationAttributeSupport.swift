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
