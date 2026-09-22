import MacroTesting
import Testing

@testable import FrameworkToolboxMacros

@Suite(.macros(["FrameworkToolboxCompatible": FrameworkToolboxCompatibleMacro.self]))
struct FrameworkToolboxCompatibleMacroTests {

    @Test func defaultAccessLevel() {
        assertMacro {
            """
            @FrameworkToolboxCompatible
            struct MyType { }
            """
        } expansion: {
            """
            struct MyType { 

                public static var box: FrameworkToolbox<Self>.Type {
                    set {
                    }
                    get {
                        FrameworkToolbox<Self>.self
                    }
                }

                public var box: FrameworkToolbox<Self> {
                    set {
                        self = newValue.base
                    }
                    get {
                        FrameworkToolbox(self)
                    }
                }

                public subscript <Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public subscript <Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public subscript <Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    box[keyPath: keyPath]
                }

                public static subscript <Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public static subscript <Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public static subscript <Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    box[keyPath: keyPath]
                }
            }
            """
        }
    }

    @Test func publicAccessLevel() {
        assertMacro {
            """
            @FrameworkToolboxCompatible(.public)
            struct MyType { }
            """
        } expansion: {
            """
            struct MyType { 

                public static var box: FrameworkToolbox<Self>.Type {
                    set {
                    }
                    get {
                        FrameworkToolbox<Self>.self
                    }
                }

                public var box: FrameworkToolbox<Self> {
                    set {
                        self = newValue.base
                    }
                    get {
                        FrameworkToolbox(self)
                    }
                }

                public subscript <Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public subscript <Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public subscript <Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    box[keyPath: keyPath]
                }

                public static subscript <Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public static subscript <Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public static subscript <Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    box[keyPath: keyPath]
                }
            }
            """
        }
    }

    @Test func internalAccessLevel() {
        assertMacro {
            """
            @FrameworkToolboxCompatible(.internal)
            struct MyType { }
            """
        } expansion: {
            """
            struct MyType { 

                internal static var box: FrameworkToolbox<Self>.Type {
                    set {
                    }
                    get {
                        FrameworkToolbox<Self>.self
                    }
                }

                internal var box: FrameworkToolbox<Self> {
                    set {
                        self = newValue.base
                    }
                    get {
                        FrameworkToolbox(self)
                    }
                }

                internal subscript <Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                internal subscript <Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                internal subscript <Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    box[keyPath: keyPath]
                }

                internal static subscript <Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                internal static subscript <Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                internal static subscript <Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    box[keyPath: keyPath]
                }
            }
            """
        }
    }

    /// The instance `box` setter writes back, or every `mutating` method reached
    /// through `.box` is silently a no-op.
    @Test func valueSemanticsWritesBackThroughTheSetter() {
        assertMacro {
            """
            @FrameworkToolboxCompatible
            struct MyValueType { }
            """
        } expansion: {
            """
            struct MyValueType { 

                public static var box: FrameworkToolbox<Self>.Type {
                    set {
                    }
                    get {
                        FrameworkToolbox<Self>.self
                    }
                }

                public var box: FrameworkToolbox<Self> {
                    set {
                        self = newValue.base
                    }
                    get {
                        FrameworkToolbox(self)
                    }
                }

                public subscript <Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public subscript <Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public subscript <Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    box[keyPath: keyPath]
                }

                public static subscript <Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public static subscript <Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public static subscript <Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    box[keyPath: keyPath]
                }
            }
            """
        }
    }

    /// A setter in a class-bound protocol's extension is not `mutating`, so it
    /// cannot assign `self` — and the compiler crashes in SILGen instead of
    /// diagnosing it. Under reference semantics the write-back is not needed
    /// anyway: the box wraps the same object.
    @Test func referenceSemanticsEmitsAnEmptySetter() {
        assertMacro {
            """
            @FrameworkToolboxCompatible(referenceSemantics: true)
            class MyReferenceType { }
            """
        } expansion: {
            """
            class MyReferenceType { 

                public static var box: FrameworkToolbox<Self>.Type {
                    set {
                    }
                    get {
                        FrameworkToolbox<Self>.self
                    }
                }

                public var box: FrameworkToolbox<Self> {
                    set {
                    }
                    get {
                        FrameworkToolbox(self)
                    }
                }

                public subscript <Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public subscript <Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public subscript <Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>, Member>) -> Member {
                    box[keyPath: keyPath]
                }

                public static subscript <Member>(dynamicMember keyPath: ReferenceWritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public static subscript <Member>(dynamicMember keyPath: WritableKeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    set {
                        box[keyPath: keyPath] = newValue
                    }
                    get {
                        box[keyPath: keyPath]
                    }
                }

                public static subscript <Member>(dynamicMember keyPath: KeyPath<FrameworkToolbox<Self>.Type, Member>) -> Member {
                    box[keyPath: keyPath]
                }
            }
            """
        }
    }
}
