import MacroTesting
import Testing

@testable import ObjCRuntimeToolboxMacros

// A method in the alloc, copy, mutableCopy, new or init family that returns an object hands its
// caller a reference to that object, and an initialiser also takes over the reference to its
// receiver. A block installed with imp_implementationWithBlock does neither — it returns its object
// autoreleased — so a replacement or override of such a method has its result released once too
// often. Measured before these diagnostics existed: a @RuntimeClassHook replacement of a copy-family
// method returning an existing object left that object one reference short. A proxy dispatches
// directly and takes over a returned reference, but it calls into an object it does not own, so
// only an initialiser is beyond it.

// MARK: - @RuntimeMethodReplacement

@Suite(.macros([
    "RuntimeClassHook": RuntimeClassHookMacro.self,
    "RuntimeMethodReplacement": RuntimeMethodReplacementMacro.self,
]))
struct RuntimeMethodReplacementMethodFamilyTests {

    @Test func copyFamilyReplacementReturningAnObjectIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func copyItem() -> NSObject? {
                    nil
                }
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func copyItem() -> NSObject? {
                     ┬───────
                     ╰─ 🛑 @RuntimeMethodReplacement: 'copyItem' is in the copy family, which hands its caller a reference to the object it returns. The block this macro installs returns the object without that reference, so the caller would release it once too often. A method in the alloc, copy, mutableCopy, new or init family that returns an object is not supported.
                    nil
                }
            }
            """
        }
    }

    @Test func initFamilyReplacementIsRejectedThroughAnExplicitSelector() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement("initWithFrame:")
                func initialise(_ frame: CGRect) -> AnyObject? {
                    nil
                }
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement("initWithFrame:")
                func initialise(_ frame: CGRect) -> AnyObject? {
                     ┬─────────
                     ╰─ 🛑 @RuntimeMethodReplacement: 'initWithFrame:' is in the init family, which takes over the reference to its receiver and hands its caller a reference to the object it returns. The block this macro installs does neither, so the receiver would leak and the result would be released once too often. A method in the alloc, copy, mutableCopy, new or init family that returns an object is not supported.
                    nil
                }
            }
            """
        }
    }

    @Test func leadingUnderscoresDoNotTakeAMethodOutOfItsFamily() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func _newItem() -> NSObject? {
                    nil
                }
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func _newItem() -> NSObject? {
                     ┬───────
                     ╰─ 🛑 @RuntimeMethodReplacement: '_newItem' is in the new family, which hands its caller a reference to the object it returns. The block this macro installs returns the object without that reference, so the caller would release it once too often. A method in the alloc, copy, mutableCopy, new or init family that returns an object is not supported.
                    nil
                }
            }
            """
        }
    }
}

// MARK: - @DynamicSubclassOverride

@Suite(.macros([
    "DynamicSubclassHook": DynamicSubclassHookMacro.self,
    "DynamicSubclassOverride": DynamicSubclassOverrideMacro.self,
]))
struct DynamicSubclassOverrideMethodFamilyTests {

    @Test func copyFamilyOverrideReturningAnObjectIsRejected() {
        assertMacro {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "Copying")
            struct CopyingHook {
                @DynamicSubclassOverride("copyWithZone:")
                func copy(_ zone: OpaquePointer?) -> AnyObject? {
                    nil
                }
            }
            """
        } diagnostics: {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "Copying")
            struct CopyingHook {
                @DynamicSubclassOverride("copyWithZone:")
                func copy(_ zone: OpaquePointer?) -> AnyObject? {
                     ┬───
                     ╰─ 🛑 @DynamicSubclassOverride: 'copyWithZone:' is in the copy family, which hands its caller a reference to the object it returns. The block this macro installs returns the object without that reference, so the caller would release it once too often. A method in the alloc, copy, mutableCopy, new or init family that returns an object is not supported.
                    nil
                }
            }
            """
        }
    }
}

// MARK: - @RuntimeClassProxy

@Suite(.macros([
    "RuntimeClassProxy": RuntimeClassProxyMacro.self,
]))
struct RuntimeClassProxyMethodFamilyTests {

    @Test func initFamilyRequirementIsRejected() {
        assertMacro {
            """
            @RuntimeClassProxy("Tile")
            protocol DockTile {
                func initWithImage(_ image: AnyObject?) -> AnyObject?
            }
            """
        } diagnostics: {
            """
            @RuntimeClassProxy("Tile")
            ┬─────────────────────────
            ╰─ ⚠️ @RuntimeClassProxy: the protocol declares nothing to proxy. The generated type will validate an empty requirement list and dispatch nothing.
            protocol DockTile {
                func initWithImage(_ image: AnyObject?) -> AnyObject?
                     ┬────────────
                     ╰─ 🛑 @RuntimeClassProxy: 'initWithImage:' is in the init family, which takes over the reference to its receiver, and a proxy calls into an object it does not own. Create the object with DynamicObject instead: ObjC.ClassName(...) sends alloc and the initialiser together.
            }
            """
        }
    }

    @Test func initFamilyPropertyIsRejected() {
        assertMacro {
            """
            @RuntimeClassProxy("Tile")
            protocol DockTile {
                var initialImage: AnyObject? { get }
                var initImage: AnyObject? { get }
            }
            """
        } diagnostics: {
            """
            @RuntimeClassProxy("Tile")
            protocol DockTile {
                var initialImage: AnyObject? { get }
                var initImage: AnyObject? { get }
                    ┬────────
                    ╰─ 🛑 @RuntimeClassProxy: 'initImage' is in the init family, which takes over the reference to its receiver, and a proxy calls into an object it does not own. Create the object with DynamicObject instead: ObjC.ClassName(...) sends alloc and the initialiser together.
            }
            """
        }
    }
}
