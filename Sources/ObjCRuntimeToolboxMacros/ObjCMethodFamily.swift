import SwiftSyntax

/// The Objective-C method families that move a reference across a call.
///
/// A method in one of these families that returns an object hands its caller a reference to it, and
/// an `init` method also takes over the reference to its receiver. Membership follows ARC's naming
/// rule: leading underscores aside, the selector's first component must be the family's name or
/// begin with it followed by something other than a lowercase letter — `copyItem` and `_newItem` are
/// in, `copyright` and `newsItem` are not.
///
/// The runtime keeps the same rule for `DynamicObject` in
/// `ObjCRuntimeToolbox/DynamicInvocation/ObjCMethodFamily.swift`. A macro plugin cannot link the
/// runtime target, so the two are separate copies; the tests of each pin the same edges.
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

/// How a macro's generated code stands in for, or calls, a method — which decides the method
/// families whose ownership it can honour.
enum OwnershipConvention {
    /// A block installed with `imp_implementationWithBlock`, as `@RuntimeMethodReplacement` and
    /// `@DynamicSubclassOverride` generate. A Swift block returns its object autoreleased and takes
    /// over nothing from its receiver, so it cannot stand in for a method in any of the families.
    case blockImplementation

    /// A direct call through the method's implementation, as `@RuntimeClassProxy` generates. The
    /// call takes over the reference a method in the alloc, copy, mutableCopy or new family hands
    /// back, but it calls into an object it does not own, so it cannot give an initialiser its
    /// receiver.
    case directCall

    func honours(_ methodFamily: ObjCMethodFamily) -> Bool {
        switch self {
        case .blockImplementation:
            return false
        case .directCall:
            return methodFamily != .`init`
        }
    }
}

/// The family of a method whose ownership matters: one that returns an object. `nil` for a method
/// returning nothing or a value the encoding table knows is not an object, and for a method in no
/// family.
///
/// A type the table does not know counts as an object — classes are by far the common case among
/// the types it leaves out — so a method returning such a scalar under a family name is rejected
/// too, which only ever costs a rename.
func ownershipTransferringFamily(
    of functionDeclaration: FunctionDeclSyntax,
    explicitSelector: String?
) -> ObjCMethodFamily? {
    let shape = FunctionShape(from: functionDeclaration)
    guard let returnTypeText = shape.returnTypeText else { return nil }
    let returnsObject = !ObjCTypeEncoding.isKnownType(returnTypeText)
        || ObjCTypeEncoding.encoding(forTypeText: returnTypeText) == "@"
    guard returnsObject else { return nil }
    return ObjCMethodFamily(selectorName: shape.selectorString(explicitSelector: explicitSelector))
}

/// The diagnostic for a method in a family `convention` cannot honour.
func ownershipTransferringFamilyDiagnostic(
    selector: String,
    methodFamily: ObjCMethodFamily,
    convention: OwnershipConvention,
    macroName: String
) -> DynamicSubclassMacroDiagnostic {
    switch convention {
    case .blockImplementation:
        let unsupportedSentence = "A method in the alloc, copy, mutableCopy, new or init family that returns an object is not supported."
        if methodFamily == .`init` {
            return .error(
                "ownershipTransferringFamilyNotSupported",
                """
                \(macroName): '\(selector)' is in the init family, which takes over the reference to its receiver and hands its caller a reference to the object it returns. \
                The block this macro installs does neither, so the receiver would leak and the result would be released once too often. \
                \(unsupportedSentence)
                """
            )
        }
        return .error(
            "ownershipTransferringFamilyNotSupported",
            """
            \(macroName): '\(selector)' is in the \(methodFamily.rawValue) family, which hands its caller a reference to the object it returns. \
            The block this macro installs returns the object without that reference, so the caller would release it once too often. \
            \(unsupportedSentence)
            """
        )
    case .directCall:
        return .error(
            "initializerCannotBeProxied",
            """
            \(macroName): '\(selector)' is in the init family, which takes over the reference to its receiver, and a proxy calls into an object it does not own. \
            Create the object with DynamicObject instead: ObjC.ClassName(...) sends alloc and the initialiser together.
            """
        )
    }
}
