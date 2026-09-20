//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import MacroToolbox
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Generates the payload-free counterpart of an enumeration — its tag — plus
/// the `tag` property that maps a value to it.
public struct CaseTagMacro {}

// MARK: - The tag enumeration, generated beside the host

extension CaseTagMacro: PeerMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard let enumeration = declaration.as(EnumDeclSyntax.self) else {
            context[.error, declaration] = "'@CaseTag' must be applied to an enum"
            return []
        }

        guard let configuration = Configuration(decoding: attribute, in: context) else {
            return []
        }

        // With `by:` the tag enumeration already exists — it is the one this
        // enumeration is nested inside — so there is nothing to generate here.
        guard configuration.tagType == nil else {
            return []
        }

        let cases = MemberBlockItemListSyntax {
            for element in enumeration.caseElements {
                EnumCaseDeclSyntax(caseNamed: element.name)
            }
        }

        let tagTypeName = "\(enumeration.name.text)Tag"
        let peer: DeclSyntax = """
        \(enumeration.attributes.mirroredAsTypeForType)\(enumeration.modifiersForMember)\
        enum \(raw: tagTypeName)\
        \(raw: configuration.rawValueType.map { ": \($0)" } ?? "") {
        \(cases)
        }
        """

        return [peer]
    }
}

// MARK: - The `tag` property, generated inside the host

extension CaseTagMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        // Both roles of this macro run on every attachment, so diagnosing a
        // non-enumeration here as well would report the same mistake twice.
        // The peer role above owns that message.
        guard let enumeration = declaration.as(EnumDeclSyntax.self) else {
            return []
        }

        guard let configuration = Configuration(decoding: attribute, in: context) else {
            return []
        }

        let tagTypeName: String = if let tagType = configuration.tagType {
            tagType.trimmedDescription
        } else {
            "\(enumeration.name.text)Tag"
        }

        let cases = enumeration.caseElements.map { element in
            "case .\(element.name): .\(element.name)"
        }

        let tagProperty: DeclSyntax = """
        \(enumeration.attributesForMember)\(enumeration.modifiersForMember)\
        var tag: \(raw: tagTypeName) {
            switch self {
            \(raw: cases.joined(separator: "\n    "))
            }
        }
        """

        return [tagProperty]
    }
}

extension CaseTagMacro {
    struct Configuration {
        /// An existing tag enumeration to point at, instead of generating one.
        let tagType: TypeSyntax?
        /// The raw-value type of the generated tag enumeration, if any.
        let rawValueType: TypeSyntax?
    }
}

extension CaseTagMacro.Configuration: ExpressionListDecodable {
    enum ArgumentKey: String, Sendable {
        case tagType = "by"
        case rawValueType = "backing"
    }

    init(from arguments: inout ExpressionListDecoder<ArgumentKey>) throws {
        self.init(
            tagType: try arguments[.tagType]?.decode(to: MetatypeExpression?.self)?.type,
            rawValueType: try arguments[.rawValueType]?
                .decode(to: MetatypeExpression?.self)?.type
        )
    }
}
