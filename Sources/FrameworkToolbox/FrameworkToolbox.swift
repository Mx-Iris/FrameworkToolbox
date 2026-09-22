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
/// - Parameters:
///   - accessLevel: The access level to emit the generated members at. Defaults
///     to `public`.
///   - referenceSemantics: Pass `true` when extending a class-bound protocol.
///     The generated `box` setter then stays empty — a setter in a class-bound
///     protocol's extension is not `mutating` and cannot assign `self`, and the
///     compiler crashes in SILGen rather than diagnosing it. Under reference
///     semantics nothing is lost: the box wraps the same object. Has to be a
///     boolean literal, since it is read at expansion time.
@attached(member, names: arbitrary)
public macro FrameworkToolboxExtension(
    _ accessLevel: AccessLevel? = nil,
    referenceSemantics: Bool = false
) =
    #externalMacro(module: "FrameworkToolboxMacros", type: "FrameworkToolboxCompatibleMacro")
