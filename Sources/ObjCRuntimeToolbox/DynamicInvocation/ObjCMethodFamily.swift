#if canImport(ObjectiveC)

/// The Objective-C method families that move a reference across a call.
///
/// A method in one of these families that returns an object hands its caller a reference to it —
/// the caller owns the result and must release it. An `init` method also takes over the reference
/// to its receiver: it hands that reference back as its result, or releases it when it returns
/// `nil` or another object.
///
/// Membership follows ARC's naming rule rather than a bare prefix test: leading underscores aside,
/// the selector's first component must be the family's name or begin with it followed by something
/// other than a lowercase letter. `copyItem`, `_newItem` and `initWithFrame:` are in a family;
/// `copyright`, `newsItem` and `initials` are not, and treating them as if they were releases their
/// result once too often.
enum ObjCMethodFamily: String, CaseIterable {
    case alloc
    case copy
    case mutableCopy
    case new
    case `init`

    /// The family `selectorName` belongs to, or `nil` for a method that returns its result without
    /// handing over a reference.
    init?(selectorName: String) {
        let firstComponent = selectorName.drop { $0 == "_" }.prefix { $0 != ":" }
        for family in Self.allCases {
            guard firstComponent.hasPrefix(family.rawValue) else { continue }
            let characterAfterName = firstComponent.dropFirst(family.rawValue.count).first
            if let characterAfterName, characterAfterName.isLowercase { continue }
            self = family
            return
        }
        return nil
    }
}

#endif
