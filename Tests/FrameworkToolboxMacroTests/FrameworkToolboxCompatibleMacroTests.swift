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
}
