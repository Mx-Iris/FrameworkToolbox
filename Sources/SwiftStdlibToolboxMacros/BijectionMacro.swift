//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import MacroToolbox
import SwiftSyntax
import SwiftSyntaxMacros

/// Reads a property whose getter maps each case of an enumeration to a value,
/// and generates the inverse initializer.
public struct BijectionMacro: PeerMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard let propertyDeclaration = declaration.as(VariableDeclSyntax.self),
              let binding = propertyDeclaration.bindings.first,
              var valueType = binding.typeAnnotation?.type.trimmed,
              let accessors = binding.accessorBlock?.accessors else {
            context[.error, attribute] = "'@Bijection' must be applied to a computed property"
            return []
        }

        guard let getterStatements = getterStatements(of: accessors, in: context) else {
            return []
        }

        guard let mapping = mapping(in: getterStatements, at: binding, in: context) else {
            return []
        }

        let rows = rows(of: mapping, in: context)

        guard let configuration = Configuration(decoding: attribute, in: context) else {
            return []
        }

        if let genericConstraint = configuration.genericConstraint {
            valueType = "some \(raw: genericConstraint)"
        }

        // `borrowing` is not decoration: an initializer parameter defaults to
        // `__owned`, which costs a retain for a `String` or any other type with
        // storage behind it.
        //
        // The `copy` is emitted only when a generic constraint was given,
        // working around https://github.com/swiftlang/swift/issues/86208 —
        // emitting it unconditionally crashes the compiler when the value type
        // is a tuple, and omitting it in the generic case crashes it too.
        let initializer: DeclSyntax = """
        \(propertyDeclaration.attributes.mirroredAsMemberForMember)\
        \(propertyDeclaration.modifiers)\
        init?(\(raw: configuration.label) $value: borrowing \(valueType)) {
            switch\(raw: configuration.genericConstraint != nil ? " copy" : "") $value {
            \(raw: rows.map { row in "case \(row.value): self = \(row.pattern)" }
                .joined(separator: "\n    "))
            default: return nil
            }
        }
        """

        return [initializer]
    }
}

extension BijectionMacro {
    private static func getterStatements(
        of accessors: AccessorBlockSyntax.Accessors,
        in context: some MacroExpansionContext
    ) -> CodeBlockItemListSyntax? {
        switch accessors {
        case .getter(let statements):
            return statements

        case .accessors(let accessorDeclarations):
            for accessor in accessorDeclarations {
                if case .keyword(.get) = accessor.accessorSpecifier.tokenKind {
                    return accessor.body?.statements ?? []
                }
            }

            context[.error, accessorDeclarations] = "accessor list contains no getter"
            return nil

        @unknown default:
            return nil
        }
    }

    private static func mapping(
        in getterStatements: CodeBlockItemListSyntax,
        at binding: PatternBindingSyntax,
        in context: some MacroExpansionContext
    ) -> SwitchExprSyntax? {
        for statement in getterStatements {
            guard let expressionStatement = statement.item.as(ExpressionStmtSyntax.self),
                  let switchExpression = expressionStatement.expression.as(
                      SwitchExprSyntax.self
                  ) else {
                context[.warning, statement] = """
                body of '@Bijection' mapping should contain only a single switch-case block, \
                with the 'return' keyword elided
                """
                continue
            }

            return switchExpression
        }

        context[.error, binding] = """
        body of '@Bijection' mapping must contain a switch-case block
        """
        return nil
    }

    private static func rows(
        of mapping: SwitchExprSyntax,
        in context: some MacroExpansionContext
    ) -> [(pattern: PatternSyntax, value: ExprSyntax)] {
        mapping.cases.reduce(into: []) { rows, caseSyntax in
            // A `default` block has nothing to invert.
            guard case .switchCase(let switchCase) = caseSyntax,
                  let label = switchCase.label.as(SwitchCaseLabelSyntax.self),
                  let pattern = label.caseItems.first?.pattern,
                  label.caseItems.count == 1 else {
                context[.error, caseSyntax] = "only one pattern may appear per case"
                return
            }

            guard switchCase.statements.count == 1,
                  let onlyStatement = switchCase.statements.first,
                  let value = onlyStatement.item.as(ExprSyntax.self) else {
                context[.error, switchCase.statements] = """
                case body must be a single expression, with the 'return' keyword elided
                """
                return
            }

            rows.append((pattern.trimmed, value.trimmed))
        }
    }
}

extension BijectionMacro {
    struct Configuration {
        /// The name of a protocol to make the generated initializer generic
        /// over, instead of taking the property's own type.
        let genericConstraint: String?
        let label: String
    }
}

extension BijectionMacro.Configuration: ExpressionListDecodable {
    enum ArgumentKey: String, Sendable {
        case genericConstraint = "where"
        case label
    }

    init(from arguments: inout ExpressionListDecoder<ArgumentKey>) throws {
        self.init(
            genericConstraint: try arguments[.genericConstraint]?.decode(),
            label: try arguments[.label]?.decode() ?? "_"
        )
    }
}
