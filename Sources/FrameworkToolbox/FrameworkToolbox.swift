@dynamicMemberLookup
public struct FrameworkToolbox<Base> {
    public var base: Base

    public init(_ base: Base) {
        self.base = base
    }
    
    public subscript<Member>(dynamicMember keyPath: KeyPath<Self, Member>) -> Member {
        self[keyPath: keyPath]
    }
}

public protocol FrameworkToolboxCompatible {
    associatedtype Base = Self
    static var box: FrameworkToolbox<Base>.Type { set get }
    var box: FrameworkToolbox<Base> { set get }
}

extension FrameworkToolboxCompatible {
    @inlinable
    public static var box: FrameworkToolbox<Self>.Type {
        set {}
        get { FrameworkToolbox<Self>.self }
    }

    /// The setter has to write back, or every `mutating` method reached through
    /// `.box` is silently a no-op: the getter hands out a fresh
    /// `FrameworkToolbox` value, the method mutates that temporary, and an empty
    /// setter drops it on the floor. Nothing fails to compile and no warning is
    /// emitted — `value.box.clamp(max: 10)` simply leaves `value` untouched.
    @inlinable
    public var box: FrameworkToolbox<Self> {
        set { self = newValue.base }
        get { FrameworkToolbox(self) }
    }
}

@dynamicMemberLookup
public protocol FrameworkToolboxDynamicMemberLookup {
    associatedtype Base = Self
    subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Base>, Member>) -> Member { set get }
    subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Base>, Member>) -> Member { set get }
    subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Base>, Member>) -> Member { get }
    static subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Base>.Type, Member>) -> Member { set get }
    static subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Base>.Type, Member>) -> Member { set get }
    static subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Base>.Type, Member>) -> Member { get }
}

extension FrameworkToolboxDynamicMemberLookup where Self: FrameworkToolboxCompatible {
    public subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
        set { box[keyPath: keyPath] = newValue }
        get { box[keyPath: keyPath] }
    }

    public subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
        set { box[keyPath: keyPath] = newValue }
        get { box[keyPath: keyPath] }
    }

    public subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>, Member>) -> Member {
        box[keyPath: keyPath]
    }

    public static subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
        set { box[keyPath: keyPath] = newValue }
        get { box[keyPath: keyPath] }
    }

    public static subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
        set { box[keyPath: keyPath] = newValue }
        get { box[keyPath: keyPath] }
    }

    public static subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
        box[keyPath: keyPath]
    }
}

extension FrameworkToolboxCompatible where Self: AnyObject {
    @inlinable
    public static var box: FrameworkToolbox<Self>.Type {
        set {}
        get { FrameworkToolbox<Self>.self }
    }

    /// Unlike the value-type overload above, this setter stays empty on purpose:
    /// a protocol-extension setter is not `mutating`, so `self` cannot be
    /// assigned here. It is also not needed — under reference semantics the box
    /// wraps the same object, so mutating through it is already visible to every
    /// other reference.
    @inlinable
    public var box: FrameworkToolbox<Self> {
        set {}
        get { FrameworkToolbox(self) }
    }
}

extension FrameworkToolboxDynamicMemberLookup where Self: AnyObject, Self: FrameworkToolboxCompatible {
    public subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
        set { box[keyPath: keyPath] = newValue }
        get { box[keyPath: keyPath] }
    }

    public subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
        set { box[keyPath: keyPath] = newValue }
        get { box[keyPath: keyPath] }
    }

    public subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>, Member>) -> Member {
        box[keyPath: keyPath]
    }

    public static subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
        set { box[keyPath: keyPath] = newValue }
        get { box[keyPath: keyPath] }
    }

    public static subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
        set { box[keyPath: keyPath] = newValue }
        get { box[keyPath: keyPath] }
    }

    public static subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
        box[keyPath: keyPath]
    }
}

/// Copies `FrameworkToolboxCompatible`'s default implementations into a protocol
/// extension, so every type conforming to that protocol gains the `box` namespace.
///
/// The instance `box` setter writes back for a protocol value types can adopt,
/// so `mutating` methods reached through `.box` take effect, and stays empty for
/// a class-bound protocol (`AnyObject`, `@objc`), whose extension setters are not
/// `mutating` — assigning `self` there crashes the compiler instead of being
/// diagnosed. Nothing is lost under reference semantics: the box wraps the same
/// object. The macro cannot see the protocol's declaration, so the choice is the
/// compiler's: see `_FrameworkToolboxBoxAccessors`.
///
/// - Parameter accessLevel: The access level to emit the generated members at.
///   Defaults to `public`.
@attached(member, names: arbitrary)
public macro FrameworkToolboxExtension(
    _ accessLevel: AccessLevel? = nil
) =
    #externalMacro(module: "FrameworkToolboxMacros", type: "FrameworkToolboxCompatibleMacro")

/// The spelling from before the compiler made the choice; `referenceSemantics:`
/// is ignored.
@available(*, deprecated, message: "No longer needed: whether the protocol is class-bound is now worked out by the compiler. Remove the 'referenceSemantics:' argument.")
@attached(member, names: arbitrary)
public macro FrameworkToolboxExtension(
    _ accessLevel: AccessLevel? = nil,
    referenceSemantics: Bool
) =
    #externalMacro(module: "FrameworkToolboxMacros", type: "FrameworkToolboxCompatibleMacro")

/// Supplies the instance `box` accessors `@FrameworkToolboxExtension` generates,
/// with the setter its protocol needs.
///
/// A pair of overloads differing only in a constraint, attached as
/// `@_FrameworkToolboxBoxAccessors(Self.self)`. Inside a protocol extension
/// `Self` is the protocol's generic parameter, so when the protocol is
/// class-bound `Self: AnyObject` holds, both overloads match, and the
/// constrained one wins; for any other protocol only the unconstrained one
/// matches. The compiler answers the question the macro cannot, the same one
/// `FrameworkToolboxCompatible`'s own `where Self: AnyObject` extension answers.
///
/// The attribute is written without its module: the module and the box type are
/// both named `FrameworkToolbox`, so `@FrameworkToolbox._FrameworkToolboxBoxAccessors`
/// resolves `FrameworkToolbox` to the struct and fails.
@_documentation(visibility: private)
@attached(accessor, names: named(get), named(set))
public macro _FrameworkToolboxBoxAccessors<Subject>(_ subject: Subject.Type) =
    #externalMacro(module: "FrameworkToolboxMacros", type: "ValueSemanticsBoxAccessorsMacro")

@_documentation(visibility: private)
@attached(accessor, names: named(get), named(set))
public macro _FrameworkToolboxBoxAccessors<Subject: AnyObject>(_ subject: Subject.Type) =
    #externalMacro(module: "FrameworkToolboxMacros", type: "ReferenceSemanticsBoxAccessorsMacro")
