//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import MacroToolbox
import SwiftSyntax
import SwiftSyntaxBuilder

extension EnumDeclSyntax {
    /// Whether the enumeration is visible outside its own module, and so
    /// whether `@inlinable` means anything on a member generated inside it.
    var isPackageOrHigher: Bool {
        modifiers.contains { modifier in
            modifier.name.text == "public" || modifier.name.text == "package"
        }
    }

    /// The attributes to put on a member generated inside this enumeration.
    ///
    /// `@inlinable` is added only where it would be accepted: the enumeration
    /// has to be visible outside the module for a caller to inline anything
    /// from it.
    func attributesForMember(inlinable: Bool) -> AttributeListSyntax {
        var attributes = self.attributes.mirroredAsTypeForMember

        if inlinable {
            let qualifies = isPackageOrHigher || self.attributes.contains { baseName in
                baseName == "usableFromInline"
            }
            if qualifies {
                attributes.append(.attribute("@inlinable "))
            }
        }

        return attributes
    }

    var attributesForMember: AttributeListSyntax {
        attributesForMember(inlinable: true)
    }

    /// The enumeration's modifiers as they should appear on something
    /// generated from it. `indirect` describes this enumeration's own storage
    /// and means nothing on a generated member or peer.
    var modifiersForMember: DeclModifierListSyntax {
        modifiers.filter { modifier in modifier.name.text != "indirect" }
    }

    /// Every case element the enumeration declares, flattening the
    /// `case a, b, c` shorthand into one element per name.
    var caseElements: [EnumCaseElementSyntax] {
        memberBlock.members.flatMap { member in
            member.decl.as(EnumCaseDeclSyntax.self)?.elements ?? []
        }
    }
}

extension EnumCaseDeclSyntax {
    /// A bare `case name` declaration, with no associated values.
    init(caseNamed name: TokenSyntax) {
        self.init(caseKeyword: .keyword(.case, trailingTrivia: .spaces(1))) {
            EnumCaseElementSyntax(name: name, trailingTrivia: .newlines(1))
        }
    }
}
