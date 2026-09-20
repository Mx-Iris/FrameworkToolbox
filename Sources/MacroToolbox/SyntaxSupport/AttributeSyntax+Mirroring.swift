//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

extension AttributeSyntax {
    /// The attribute's name without its arguments — the `available` of
    /// `@available(macOS 13, *)` — or `nil` when it is not a plain name.
    public var baseName: String? {
        attributeName.as(IdentifierTypeSyntax.self)?.name.text
    }
}

extension AttributeListSyntax {
    public func first(named baseName: String) -> AttributeSyntax? {
        for case .attribute(let attribute) in self where attribute.baseName == baseName {
            return attribute
        }
        return nil
    }

    public func contains<Failure>(
        where predicate: (_ baseName: String) throws(Failure) -> Bool
    ) throws(Failure) -> Bool {
        for case .attribute(let attribute) in self {
            if let baseName = attribute.baseName, try predicate(baseName) {
                return true
            }
        }
        return false
    }
}

// MARK: - Mirroring a declaration's attributes onto what a macro generates
//
// A generated declaration has to carry forward the attributes that still apply
// to it, and only those. Which ones those are depends on what is being
// generated from what, hence three separate filters rather than one.

extension AttributeListSyntax {
    /// Attributes to copy from a type onto a *peer type* generated beside it.
    public var mirroredAsTypeForType: AttributeListSyntax {
        filter {
            guard case .attribute(let attribute) = $0 else { return false }
            switch attribute.baseName {
            case "available", "frozen", "usableFromInline": return true
            default: return false
            }
        }
    }

    /// Attributes to copy from a type onto a *member* generated inside it.
    ///
    /// Only availability survives: `@frozen` describes the type's layout and
    /// `@usableFromInline` is decided separately for the member itself.
    public var mirroredAsTypeForMember: AttributeListSyntax {
        filter {
            guard case .attribute(let attribute) = $0 else { return false }
            return attribute.baseName == "available"
        }
    }

    /// Attributes to copy from a member onto another member generated from it,
    /// such as the initializer `@Bijection` derives from a property.
    public var mirroredAsMemberForMember: AttributeListSyntax {
        filter {
            guard case .attribute(let attribute) = $0 else { return false }
            switch attribute.baseName {
            case "available", "backDeployed", "inlinable", "inline", "usableFromInline":
                return true
            default:
                return false
            }
        }
    }
}
