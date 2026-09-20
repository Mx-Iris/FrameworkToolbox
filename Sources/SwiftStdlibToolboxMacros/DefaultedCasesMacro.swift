//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import MacroToolbox
import SwiftSyntax
import SwiftSyntaxMacros

/// Generates a zero-argument static property for every case whose associated
/// values can all be filled in without the caller saying anything.
public struct DefaultedCasesMacro {}

extension DefaultedCasesMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard let enumeration = declaration.as(EnumDeclSyntax.self) else {
            context[.error, declaration] = "'@DefaultedCases' must be applied to an enum"
            return []
        }

        var members: [DeclSyntax] = []

        for element in enumeration.caseElements {
            // A case with no associated values can already be written as
            // `.quick`; there is nothing to restore.
            guard let parameters = element.parameterClause?.parameters,
                  !parameters.isEmpty else {
                continue
            }

            guard let arguments = arguments(filling: parameters, in: context) else {
                continue
            }

            let constructor: DeclSyntax = """
            \(enumeration.attributesForMember)\(enumeration.modifiersForMember)static var \
            \(raw: element.name): Self {
                .\(raw: element.name)(\(raw: arguments.joined(separator: ", ")))
            }
            """
            members.append(constructor)
        }

        return members
    }
}

extension DefaultedCasesMacro {
    /// The argument list that reconstructs this case with no input, or `nil`
    /// when some parameter has neither a default argument nor an optional type
    /// — in which case the case is skipped rather than diagnosed, since a
    /// single unfillable parameter is a perfectly ordinary thing for an
    /// enumeration to have.
    private static func arguments(
        filling parameters: EnumCaseParameterListSyntax,
        in context: some MacroExpansionContext
    ) -> [String]? {
        var arguments: [String] = []

        for parameter in parameters {
            // `Optional<Int>` is matched by spelling, not by resolution, so the
            // long form has to be pointed out rather than accepted.
            context[.warning, parameter.type] = parameter.type.unsugaredOptionalDiagnostic

            let value: String
            if let defaultValue = parameter.defaultValue {
                value = defaultValue.value.trimmedDescription
            } else if parameter.type.isOptional {
                value = "nil"
            } else {
                return nil
            }

            if let label = parameter.firstName, label.text != "_" {
                arguments.append("\(label.text): \(value)")
            } else {
                arguments.append(value)
            }
        }

        return arguments
    }
}
