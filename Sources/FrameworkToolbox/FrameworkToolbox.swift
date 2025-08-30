public struct FrameworkToolbox<Base> {
    public var base: Base

    public init(_ base: Base) {
        self.base = base
    }
}

public protocol FrameworkToolboxCompatible {
    associatedtype Base
    static var box: FrameworkToolbox<Base>.Type { set get }
    var box: FrameworkToolbox<Base> { set get }
}

@dynamicMemberLookup
public protocol FrameworkToolboxDynamicMemberLookup {
    associatedtype Base
    subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Base>, Member>) -> Member { set get }
    subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Base>, Member>) -> Member { set get }
    subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Base>, Member>) -> Member { get }
    static subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Base>.Type, Member>) -> Member { set get }
    static subscript<Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Base>.Type, Member>) -> Member { set get }
    static subscript<Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Base>.Type, Member>) -> Member { get }
}

extension FrameworkToolboxCompatible {
    @inlinable
    public static var box: FrameworkToolbox<Self>.Type {
        set {}
        get { FrameworkToolbox<Self>.self }
    }

    @inlinable
    public var box: FrameworkToolbox<Self> {
        set {}
        get { FrameworkToolbox(self) }
    }
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

@attached(member, names: arbitrary)
public macro FrameworkToolboxExtension() =
    #externalMacro(module: "FrameworkToolboxMacros", type: "FrameworkToolboxCompatibleMacro")
