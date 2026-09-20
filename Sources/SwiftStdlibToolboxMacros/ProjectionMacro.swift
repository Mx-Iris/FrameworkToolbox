//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import MacroToolbox
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Generates a property per `@ProjectionFunction` in the enumeration, each
/// pulling one shared value out of every case whatever that case carries.
public struct ProjectionMacro {}

extension ProjectionMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard let enumeration = declaration.as(EnumDeclSyntax.self) else {
            context[.error, declaration] = "'@Projection' must be applied to an enum"
            return []
        }

        // Anything marked but malformed has already been diagnosed by
        // `@ProjectionFunction` itself, so it is dropped here in silence.
        let projectionFunctions: [(function: FunctionDeclSyntax, marker: AttributeSyntax)] =
            enumeration.memberBlock.members.compactMap { member in
                guard let function = member.decl.as(FunctionDeclSyntax.self),
                      let marker = function.attributes.first(named: "ProjectionFunction"),
                      function.isStatic,
                      function.signature.returnClause != nil else {
                    return nil
                }
                return (function, marker)
            }

        guard !projectionFunctions.isEmpty else {
            context[.error, attribute] = """
            enum '\(enumeration.name.text)' must declare at least one static function \
            marked with '@ProjectionFunction' for '@Projection' to build a property from
            """
            return []
        }

        return projectionFunctions.map { projectionFunction, marker in
            property(
                for: projectionFunction,
                markedBy: marker,
                of: enumeration,
                in: context
            )
        }
    }
}

extension ProjectionMacro {
    private static func property(
        for projectionFunction: FunctionDeclSyntax,
        markedBy marker: AttributeSyntax,
        of enumeration: EnumDeclSyntax,
        in context: some MacroExpansionContext
    ) -> DeclSyntax {
        // The function names the projection: no string to keep in step with it.
        let name = projectionFunction.name.text
        let returnType = projectionFunction.signature.returnClause!.type.trimmed

        context[.warning, returnType] = returnType.unsugaredOptionalDiagnostic

        let flatten = ProjectionFunctionMacro.Configuration(
            decoding: marker,
            in: context
        )?.flatten ?? true

        let projectionParameters = projectionFunction.signature.parameterClause.parameters

        var projectedCases: [String] = []

        // Whether the generated `switch` already covers every case on its own.
        // Two things clear it: a case the projection function cannot be handed,
        // and an optional payload — `case .first(let payload?)` does not match
        // `.first(nil)`. Miss the second and the macro emits a `switch` that
        // does not compile, which is worse than the warning this flag exists to
        // remove.
        var isExhaustive = true

        for element in enumeration.caseElements {
            let payload =
                element.parameterClause?.parameters ?? EnumCaseParameterListSyntax([])

            // A case is projectable when it carries exactly as many values as
            // the projection function takes — zero included.
            guard payload.count == projectionParameters.count else {
                isExhaustive = false
                continue
            }

            var bindings: [String] = []
            var arguments: [String] = []

            for (offset, (payloadParameter, projectionParameter))
            in zip(payload, projectionParameters).enumerated() {
                context[.warning, payloadParameter.type] =
                    payloadParameter.type.unsugaredOptionalDiagnostic

                // A lone payload keeps the unnumbered name; several are
                // numbered rather than named after the projection function's
                // parameters, which are routinely `_`.
                let binding = payload.count == 1 ? "payload" : "payload\(offset + 1)"

                // An optional payload is unwrapped in the pattern, so the
                // projection function never has to be generic over optionality.
                if payloadParameter.type.isOptional {
                    bindings.append("let \(binding)?")
                    isExhaustive = false
                } else {
                    bindings.append("let \(binding)")
                }

                // The argument label comes from the projection function, not
                // from the case: the two name their values independently.
                let label = projectionParameter.firstName.text
                arguments.append(label == "_" ? binding : "\(label): \(binding)")
            }

            let pattern = bindings.isEmpty ? "" : "(\(bindings.joined(separator: ", ")))"

            projectedCases.append(
                """
                case .\(element.name)\(pattern): \
                Self.\(name)(\(arguments.joined(separator: ", ")))
                """
            )
        }

        // Flattening keeps the property from being a double optional when the
        // projection function itself returns one.
        let propertyType: TypeSyntax = if flatten, returnType.isOptional {
            returnType
        } else {
            "\(returnType)?"
        }

        // The `default` is emitted only when it can actually be reached.
        // Emitting it unconditionally makes the compiler warn `default will
        // never be executed` against generated code the caller never wrote.
        var branches = projectedCases
        if !isExhaustive {
            branches.append("default: nil")
        }

        return """
        \(enumeration.attributesForMember)\(enumeration.modifiersForMember)var \
        \(raw: name): \(propertyType) {
            switch self {
            \(raw: branches.joined(separator: "\n    "))
            }
        }
        """
    }
}
