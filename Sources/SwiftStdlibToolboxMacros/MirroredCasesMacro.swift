//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import MacroToolbox
import SwiftSyntax
import SwiftSyntaxMacros

/// Copies the case names of a nested `@CaseTag(by:)` enumeration onto the
/// enumeration this is attached to, which is the tag those cases belong to.
public struct MirroredCasesMacro {}

extension MirroredCasesMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard let enumeration = declaration.as(EnumDeclSyntax.self) else {
            context[.error, declaration] = "'@MirroredCases' must be applied to an enum"
            return []
        }

        let candidates: [(enumeration: EnumDeclSyntax, attribute: AttributeSyntax)] =
            enumeration.memberBlock.members.reduce(into: []) { candidates, member in
                if let nested = member.decl.as(EnumDeclSyntax.self),
                   let nestedAttribute = nested.attributes.first(named: "CaseTag") {
                    candidates.append((nested, nestedAttribute))
                }
            }

        guard !candidates.isEmpty else {
            context[.error, declaration] = """
            '@MirroredCases' requires a nested enum annotated with '@CaseTag'
            """
            return []
        }
        guard candidates.count == 1, let candidate = candidates.first else {
            context[.error, declaration] = """
            '@MirroredCases' found multiple nested enums annotated with '@CaseTag'
            """
            return []
        }

        guard validate(candidate.attribute, pointsAt: enumeration, in: context) else {
            return []
        }

        return candidate.enumeration.caseElements.map { element in
            DeclSyntax(EnumCaseDeclSyntax(caseNamed: element.name))
        }
    }
}

extension MirroredCasesMacro {
    /// Checks that the nested enumeration's `@CaseTag(by:)` names *this*
    /// enumeration. Without it the two halves silently disagree about which
    /// type the tag is.
    private static func validate(
        _ nestedAttribute: AttributeSyntax,
        pointsAt enumeration: EnumDeclSyntax,
        in context: some MacroExpansionContext
    ) -> Bool {
        // A malformed `@CaseTag` has already been diagnosed where it is
        // written; leave this enumeration's cases alone rather than pile a
        // second error onto the same mistake.
        guard let configuration = CaseTagMacro.Configuration(
            decoding: nestedAttribute,
            in: context
        ) else {
            return true
        }

        guard let tagType = configuration.tagType else {
            context[.error, nestedAttribute] = """
            '@CaseTag' nested inside '@MirroredCases' must specify \
            'by: \(enumeration.name.text).self'
            """
            return false
        }

        let referencedName: Substring? = switch tagType.asProtocol((any TypeSyntaxProtocol).self) {
        case let identifier as IdentifierTypeSyntax: identifier.name.unescaped
        case let member as MemberTypeSyntax: member.name.unescaped
        default: nil
        }

        guard referencedName == enumeration.name.unescaped else {
            context[.error, nestedAttribute] = """
            '@CaseTag' must specify 'by: \(enumeration.name.text).self'
            """
            return false
        }

        return true
    }
}
