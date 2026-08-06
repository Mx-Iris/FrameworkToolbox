import MacroTesting
import Testing

@testable import ObjCRuntimeToolboxMacros

// MARK: - Type Encoding Derivation
//
// Unit tests on the mapper itself. These are the strings every hook and proxy
// is checked against, so getting them wrong would make every downstream
// assertion meaningless.

struct ObjCTypeEncodingDerivationTests {

    @Test func voidAndPrimitiveReturns() {
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: nil, parameterTypeTexts: []) == "v@:")
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: "Void", parameterTypeTexts: []) == "v@:")
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: "Int", parameterTypeTexts: []) == "q@:")
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: "Bool", parameterTypeTexts: []) == "B@:")
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: "Double", parameterTypeTexts: []) == "d@:")
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: "CGFloat", parameterTypeTexts: []) == "d@:")
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: "UInt32", parameterTypeTexts: []) == "I@:")
    }

    @Test func objectReturnsAndParameters() {
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: "AnyObject", parameterTypeTexts: []) == "@@:")
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: "String", parameterTypeTexts: []) == "@@:")
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: "URL", parameterTypeTexts: []) == "@@:")
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: nil, parameterTypeTexts: ["AnyObject?", "Bool"]) == "v@:@B")
        #expect(ObjCTypeEncoding.methodEncoding(returnTypeText: nil, parameterTypeTexts: ["AnyObject?", "Int"]) == "v@:@q")
    }

    @Test func runtimeReferenceTypes() {
        #expect(ObjCTypeEncoding.encoding(forTypeText: "AnyClass") == "#")
        #expect(ObjCTypeEncoding.encoding(forTypeText: "Selector") == ":")
        #expect(ObjCTypeEncoding.encoding(forTypeText: "UnsafeRawPointer") == "^v")
        #expect(ObjCTypeEncoding.encoding(forTypeText: "UnsafeMutablePointer<Int>") == "^v")
    }

    @Test func optionalityIsIrrelevantToTheEncoding() {
        // An Objective-C method taking `id` is the same method whether Swift
        // spells the parameter `AnyObject` or `AnyObject?`.
        for spelling in ["AnyObject", "AnyObject?", "AnyObject!", "Optional<AnyObject>", "(AnyObject)?"] {
            #expect(ObjCTypeEncoding.encoding(forTypeText: spelling) == "@", "\(spelling)")
        }
        for spelling in ["Int", "Int?", "Int!", "Optional<Int>"] {
            #expect(ObjCTypeEncoding.encoding(forTypeText: spelling) == "q", "\(spelling)")
        }
    }

    @Test func sugarAndQualificationResolveToObjects() {
        #expect(ObjCTypeEncoding.encoding(forTypeText: "[String]") == "@")
        #expect(ObjCTypeEncoding.encoding(forTypeText: "[String: Int]") == "@")
        #expect(ObjCTypeEncoding.encoding(forTypeText: "any NSCopying") == "@")
        #expect(ObjCTypeEncoding.encoding(forTypeText: "Foundation.URL") == "@")
        #expect(ObjCTypeEncoding.encoding(forTypeText: "Swift.Int") == "q")
    }

    @Test func structsInTheTableEncodeTheirLayout() {
        #expect(ObjCTypeEncoding.encoding(forTypeText: "CGPoint") == "{CGPoint=dd}")
        #expect(ObjCTypeEncoding.encoding(forTypeText: "CGRect") == "{CGRect={CGPoint=dd}{CGSize=dd}}")
        #expect(ObjCTypeEncoding.encoding(forTypeText: "NSRange") == "{_NSRange=QQ}")
    }

    @Test func unknownIdentifiersAreAssumedToBeObjects() {
        // A wrong guess here cannot corrupt a host: struct encodings never look
        // like `@`, so the install-time comparison rejects the batch instead.
        #expect(ObjCTypeEncoding.encoding(forTypeText: "NSView") == "@")
        #expect(ObjCTypeEncoding.encoding(forTypeText: "CGImage") == "@")
        #expect(ObjCTypeEncoding.encoding(forTypeText: "SomePrivateHostClass") == "@")
        #expect(ObjCTypeEncoding.isKnownType("SomePrivateHostClass") == false)
        #expect(ObjCTypeEncoding.isKnownType("Int") == true)
    }
}

// MARK: - @RuntimeClassHook Diagnostics

@Suite(.macros([
    "RuntimeClassHook": RuntimeClassHookMacro.self,
    "RuntimeMethodReplacement": RuntimeMethodReplacementMacro.self,
]))
struct RuntimeClassHookDiagnosticsTests {

    @Test func enumContainerIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            enum TileHooks {
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            ┬────────────────────────
            ╰─ 🛑 @RuntimeClassHook can only be applied to a struct or class, not a enum. The container is constructed around the receiver on every invocation, so it needs stored properties.
            enum TileHooks {
            }
            """
        }
    }

    @Test func missingClassNameIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook
            struct TileHooks {
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook
            ┬────────────────
            ╰─ 🛑 @RuntimeClassHook requires the target class name, e.g. @RuntimeClassHook("NSStatusBarWindow").
            struct TileHooks {
            }
            """
        }
    }

    @Test func nonLiteralClassNameIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook(someRuntimeValue)
            struct TileHooks {
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook(someRuntimeValue)
                              ┬───────────────
                              ╰─ 🛑 @RuntimeClassHook: the class name must be a string literal — it is resolved with objc_getClass at install time.
            struct TileHooks {
            }
            """
        }
    }

    @Test func emptyClassNameIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook("")
            struct TileHooks {
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("")
                              ┬─
                              ╰─ 🛑 @RuntimeClassHook: the class name must not be empty.
            struct TileHooks {
            }
            """
        }
    }

    @Test func containerWithNoTaggedMethodsWarns() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                func notTagged() {}
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            ┬────────────────────────
            ╰─ ⚠️ @RuntimeClassHook: no methods are tagged with @RuntimeMethodReplacement. descriptors() will be empty and install() will replace nothing. Did you forget to tag your replacement methods?
            struct TileHooks {
                func notTagged() {}
            }
            """
        } expansion: {
            """
            struct TileHooks {
                func notTagged() {}

                static let runtimeClassName: String = "Tile"

                let host: AnyObject

                let originalImplementation: IMP

                init(host: AnyObject, originalImplementation: IMP) {
                    self.host = host
                    self.originalImplementation = originalImplementation
                }

                static func descriptors() -> [ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor] {
                    []
                }

                static func install() throws {
                    try ObjCRuntimeToolbox.RuntimeMethodHook.installAtomically(descriptors())
                }
            }
            """
        }
    }

    @Test func throwsIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setImage() throws {}
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setImage() throws {}
                                ┬─────
                                ╰─ 🛑 @RuntimeMethodReplacement does not support 'throws' methods. Catch the error inside the hook body instead.
            }
            """
        }
    }

    @Test func asyncIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setImage() async {}
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setImage() async {}
                                ┬────
                                ╰─ 🛑 @RuntimeMethodReplacement does not support 'async' methods — Objective-C IMP blocks cannot bridge Swift continuations.
            }
            """
        }
    }

    @Test func mainActorIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                @MainActor
                func setImage() {}
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                @MainActor
                ┬─────────
                ╰─ 🛑 @RuntimeMethodReplacement does not support @MainActor methods — the ObjC IMP block does not carry actor isolation.
                func setImage() {}
            }
            """
        }
    }

    @Test func staticMethodIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                static func setImage() {}
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                static func setImage() {}
                ┬─────
                ╰─ 🛑 @RuntimeMethodReplacement cannot be applied to a 'static' or 'class' method. Declare it as an instance method — the container is rebuilt around the receiver on every invocation, and 'host' is how the replacement reaches it. To replace an Objective-C *class* method, keep the Swift method non-static and pass isClassMethod: true.
            }
            """
        }
    }

    @Test func labelledFirstParameterIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setImage(image: AnyObject?) {}
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setImage(image: AnyObject?) {}
                              ┬────
                              ╰─ 🛑 @RuntimeMethodReplacement: first parameter label must be '_'. Swift's @objc bridging produces a selector like '<baseName>With<CapitalizedLabel>:' for labelled first parameters, but this macro derives '<baseName><label>:' which won't match. Either drop the label (use '_'), or pass an explicit selector: @RuntimeMethodReplacement("real:selector:").
            }
            """
        }
    }

    @Test func tupleParameterIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setImage(_ pair: (Int, Int)) {}
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setImage(_ pair: (Int, Int)) {}
                                      ┬─────────
                                      ╰─ 🛑 @RuntimeMethodReplacement parameter cannot use Swift tuples — Objective-C has no tuple type.
            }
            """
        }
    }

    @Test func duplicateSelectorIsRejected() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setImage(_ image: AnyObject?) {}
                @RuntimeMethodReplacement("setImage:")
                func setImageAgain(_ image: AnyObject?) {}
            }
            """
        } diagnostics: {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setImage(_ image: AnyObject?) {}
                @RuntimeMethodReplacement("setImage:")
                func setImageAgain(_ image: AnyObject?) {}
                     ┬────────────
                     ╰─ 🛑 @RuntimeMethodReplacement: selector 'setImage:' is already declared by 'setImage'. Installing the same method twice would chain the replacements, so each one's original would be the other's replacement.
            }
            """
        }
    }
}

// MARK: - @RuntimeClassHook Expansion

@Suite(.macros([
    "RuntimeClassHook": RuntimeClassHookMacro.self,
    "RuntimeMethodReplacement": RuntimeMethodReplacementMacro.self,
]))
struct RuntimeClassHookExpansionTests {

    @Test func voidMethodWithObjectAndBooleanParameters() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setReplacementAppImage(_ image: AnyObject?, usesIconServices: Bool) {
                    callOriginal(image, usesIconServices)
                }
            }
            """
        } expansion: {
            """
            struct TileHooks {
                func setReplacementAppImage(_ image: AnyObject?, usesIconServices: Bool) {
                    @discardableResult
                    func callOriginal(_ argument0: AnyObject?, _ argument1: Bool) {
                        let dispatchFunction = unsafeBitCast(self.originalImplementation, to: (@convention(c) (AnyObject, Selector, AnyObject?, Bool) -> Void).self)
                        dispatchFunction(self.host, NSSelectorFromString("setReplacementAppImage:usesIconServices:"), argument0, argument1)
                    }
                    callOriginal(image, usesIconServices)
                }

                static let runtimeClassName: String = "Tile"

                let host: AnyObject

                let originalImplementation: IMP

                init(host: AnyObject, originalImplementation: IMP) {
                    self.host = host
                    self.originalImplementation = originalImplementation
                }

                static func descriptors() -> [ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor] {
                    [
                        ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor(
                            className: "Tile",
                            selector: NSSelectorFromString("setReplacementAppImage:usesIconServices:"),
                            isInstanceMethod: true,
                            expectedTypeEncoding: "v@:@B",
                            makeReplacement: { originalImplementation in
                                let replacementBlock_setReplacementAppImage_0: @convention(block) (AnyObject, AnyObject?, Bool) -> Void = { hostObject, argument0, argument1 in
                                    TileHooks(host: hostObject, originalImplementation: originalImplementation).setReplacementAppImage(argument0, usesIconServices: argument1)
                                }
                                return imp_implementationWithBlock(replacementBlock_setReplacementAppImage_0 as AnyObject)
                            }
                        ),
                    ]
                }

                static func install() throws {
                    try ObjCRuntimeToolbox.RuntimeMethodHook.installAtomically(descriptors())
                }
            }
            """
        }
    }

    @Test func returningMethodLiftsItsImplicitReturn() {
        assertMacro {
            """
            @RuntimeClassHook("Greeter")
            struct GreeterHooks {
                @RuntimeMethodReplacement
                func greet() -> String {
                    callOriginal().uppercased()
                }
            }
            """
        } expansion: {
            """
            struct GreeterHooks {
                func greet() -> String {
                    @discardableResult
                    func callOriginal() -> String {
                        let dispatchFunction = unsafeBitCast(self.originalImplementation, to: (@convention(c) (AnyObject, Selector) -> String).self)
                        return dispatchFunction(self.host, NSSelectorFromString("greet"))
                    }
                    return callOriginal().uppercased()
                }

                static let runtimeClassName: String = "Greeter"

                let host: AnyObject

                let originalImplementation: IMP

                init(host: AnyObject, originalImplementation: IMP) {
                    self.host = host
                    self.originalImplementation = originalImplementation
                }

                static func descriptors() -> [ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor] {
                    [
                        ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor(
                            className: "Greeter",
                            selector: NSSelectorFromString("greet"),
                            isInstanceMethod: true,
                            expectedTypeEncoding: "@@:",
                            makeReplacement: { originalImplementation in
                                let replacementBlock_greet_0: @convention(block) (AnyObject) -> String = { hostObject in
                                    GreeterHooks(host: hostObject, originalImplementation: originalImplementation).greet()
                                }
                                return imp_implementationWithBlock(replacementBlock_greet_0 as AnyObject)
                            }
                        ),
                    ]
                }

                static func install() throws {
                    try ObjCRuntimeToolbox.RuntimeMethodHook.installAtomically(descriptors())
                }
            }
            """
        }
    }

    @Test func explicitSelectorOverridesTheDerivedOne() {
        assertMacro {
            """
            @RuntimeClassHook("Formatter")
            struct FormatterHooks {
                @RuntimeMethodReplacement("formatWithMessage:level:")
                func format(message: String, level: Int) -> String {
                    callOriginal(message, level)
                }
            }
            """
        } expansion: {
            """
            struct FormatterHooks {
                func format(message: String, level: Int) -> String {
                    @discardableResult
                    func callOriginal(_ argument0: String, _ argument1: Int) -> String {
                        let dispatchFunction = unsafeBitCast(self.originalImplementation, to: (@convention(c) (AnyObject, Selector, String, Int) -> String).self)
                        return dispatchFunction(self.host, NSSelectorFromString("formatWithMessage:level:"), argument0, argument1)
                    }
                    return callOriginal(message, level)
                }

                static let runtimeClassName: String = "Formatter"

                let host: AnyObject

                let originalImplementation: IMP

                init(host: AnyObject, originalImplementation: IMP) {
                    self.host = host
                    self.originalImplementation = originalImplementation
                }

                static func descriptors() -> [ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor] {
                    [
                        ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor(
                            className: "Formatter",
                            selector: NSSelectorFromString("formatWithMessage:level:"),
                            isInstanceMethod: true,
                            expectedTypeEncoding: "@@:@q",
                            makeReplacement: { originalImplementation in
                                let replacementBlock_format_0: @convention(block) (AnyObject, String, Int) -> String = { hostObject, argument0, argument1 in
                                    FormatterHooks(host: hostObject, originalImplementation: originalImplementation).format(message: argument0, level: argument1)
                                }
                                return imp_implementationWithBlock(replacementBlock_format_0 as AnyObject)
                            }
                        ),
                    ]
                }

                static func install() throws {
                    try ObjCRuntimeToolbox.RuntimeMethodHook.installAtomically(descriptors())
                }
            }
            """
        }
    }

    @Test func explicitTypeEncodingOverridesTheDerivedOne() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement(typeEncoding: "v24@0:8{CGSize=dd}16")
                func setTileSize(_ size: CGSize) {
                    callOriginal(size)
                }
            }
            """
        } expansion: {
            """
            struct TileHooks {
                func setTileSize(_ size: CGSize) {
                    @discardableResult
                    func callOriginal(_ argument0: CGSize) {
                        let dispatchFunction = unsafeBitCast(self.originalImplementation, to: (@convention(c) (AnyObject, Selector, CGSize) -> Void).self)
                        dispatchFunction(self.host, NSSelectorFromString("setTileSize:"), argument0)
                    }
                    callOriginal(size)
                }

                static let runtimeClassName: String = "Tile"

                let host: AnyObject

                let originalImplementation: IMP

                init(host: AnyObject, originalImplementation: IMP) {
                    self.host = host
                    self.originalImplementation = originalImplementation
                }

                static func descriptors() -> [ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor] {
                    [
                        ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor(
                            className: "Tile",
                            selector: NSSelectorFromString("setTileSize:"),
                            isInstanceMethod: true,
                            expectedTypeEncoding: "v24@0:8{CGSize=dd}16",
                            makeReplacement: { originalImplementation in
                                let replacementBlock_setTileSize_0: @convention(block) (AnyObject, CGSize) -> Void = { hostObject, argument0 in
                                    TileHooks(host: hostObject, originalImplementation: originalImplementation).setTileSize(argument0)
                                }
                                return imp_implementationWithBlock(replacementBlock_setTileSize_0 as AnyObject)
                            }
                        ),
                    ]
                }

                static func install() throws {
                    try ObjCRuntimeToolbox.RuntimeMethodHook.installAtomically(descriptors())
                }
            }
            """
        }
    }

    @Test func classMethodReplacement() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement(isClassMethod: true)
                func sharedTile() -> AnyObject? {
                    callOriginal()
                }
            }
            """
        } expansion: {
            """
            struct TileHooks {
                func sharedTile() -> AnyObject? {
                    @discardableResult
                    func callOriginal() -> AnyObject? {
                        let dispatchFunction = unsafeBitCast(self.originalImplementation, to: (@convention(c) (AnyObject, Selector) -> AnyObject?).self)
                        return dispatchFunction(self.host, NSSelectorFromString("sharedTile"))
                    }
                    return callOriginal()
                }

                static let runtimeClassName: String = "Tile"

                let host: AnyObject

                let originalImplementation: IMP

                init(host: AnyObject, originalImplementation: IMP) {
                    self.host = host
                    self.originalImplementation = originalImplementation
                }

                static func descriptors() -> [ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor] {
                    [
                        ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor(
                            className: "Tile",
                            selector: NSSelectorFromString("sharedTile"),
                            isInstanceMethod: false,
                            expectedTypeEncoding: "@@:",
                            makeReplacement: { originalImplementation in
                                let replacementBlock_sharedTile_0: @convention(block) (AnyObject) -> AnyObject? = { hostObject in
                                    TileHooks(host: hostObject, originalImplementation: originalImplementation).sharedTile()
                                }
                                return imp_implementationWithBlock(replacementBlock_sharedTile_0 as AnyObject)
                            }
                        ),
                    ]
                }

                static func install() throws {
                    try ObjCRuntimeToolbox.RuntimeMethodHook.installAtomically(descriptors())
                }
            }
            """
        }
    }

    @Test func untaggedMethodsAreLeftAlone() {
        assertMacro {
            """
            @RuntimeClassHook("Tile")
            struct TileHooks {
                @RuntimeMethodReplacement
                func setImage(_ image: AnyObject?) {
                    guard shouldReplace(image) else {
                        callOriginal(image)
                        return
                    }
                    callOriginal(nil)
                }

                private func shouldReplace(_ image: AnyObject?) -> Bool {
                    image != nil
                }
            }
            """
        } expansion: {
            """
            struct TileHooks {
                func setImage(_ image: AnyObject?) {
                    @discardableResult
                    func callOriginal(_ argument0: AnyObject?) {
                        let dispatchFunction = unsafeBitCast(self.originalImplementation, to: (@convention(c) (AnyObject, Selector, AnyObject?) -> Void).self)
                        dispatchFunction(self.host, NSSelectorFromString("setImage:"), argument0)
                    }
                    guard shouldReplace(image) else {
                                callOriginal(image)
                                return
                            }
                    callOriginal(nil)
                }

                private func shouldReplace(_ image: AnyObject?) -> Bool {
                    image != nil
                }

                static let runtimeClassName: String = "Tile"

                let host: AnyObject

                let originalImplementation: IMP

                init(host: AnyObject, originalImplementation: IMP) {
                    self.host = host
                    self.originalImplementation = originalImplementation
                }

                static func descriptors() -> [ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor] {
                    [
                        ObjCRuntimeToolbox.RuntimeMethodHook.Descriptor(
                            className: "Tile",
                            selector: NSSelectorFromString("setImage:"),
                            isInstanceMethod: true,
                            expectedTypeEncoding: "v@:@",
                            makeReplacement: { originalImplementation in
                                let replacementBlock_setImage_0: @convention(block) (AnyObject, AnyObject?) -> Void = { hostObject, argument0 in
                                    TileHooks(host: hostObject, originalImplementation: originalImplementation).setImage(argument0)
                                }
                                return imp_implementationWithBlock(replacementBlock_setImage_0 as AnyObject)
                            }
                        ),
                    ]
                }

                static func install() throws {
                    try ObjCRuntimeToolbox.RuntimeMethodHook.installAtomically(descriptors())
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
struct RuntimeClassProxyMacroTests {

    @Test func appliedToAStructIsRejected() {
        assertMacro {
            """
            @RuntimeClassProxy("Tile")
            struct DockTile {
            }
            """
        } diagnostics: {
            """
            @RuntimeClassProxy("Tile")
            ┬─────────────────────────
            ╰─ 🛑 @RuntimeClassProxy can only be applied to a protocol. Protocol requirements have no bodies, which is what lets the declaration stay plain Swift with nothing to stub out.
            struct DockTile {
            }
            """
        }
    }

    @Test func missingClassNameIsRejected() {
        assertMacro {
            """
            @RuntimeClassProxy
            protocol DockTile {
            }
            """
        } diagnostics: {
            """
            @RuntimeClassProxy
            ┬─────────────────
            ╰─ 🛑 @RuntimeClassProxy requires the target class name, e.g. @RuntimeClassProxy("NSStatusBarWindow").
            protocol DockTile {
            }
            """
        }
    }

    @Test func nonOptionalReturnIsRejected() {
        assertMacro {
            """
            @RuntimeClassProxy("Tile")
            protocol DockTile {
                func dock() -> AnyObject
            }
            """
        } diagnostics: {
            """
            @RuntimeClassProxy("Tile")
            ┬─────────────────────────
            ╰─ ⚠️ @RuntimeClassProxy: the protocol declares nothing to proxy. The generated type will validate an empty requirement list and dispatch nothing.
            protocol DockTile {
                func dock() -> AnyObject
                               ┬────────
                               ╰─ 🛑 @RuntimeClassProxy: a returning proxy method must declare an optional return type. Dispatch into a class resolved at runtime can fail, and there is no honest default to invent — write 'AnyObject?' and handle nil (or '?? someDefault') at the call site.
            }
            """
        }
    }

    @Test func nonOptionalPropertyIsRejected() {
        assertMacro {
            """
            @RuntimeClassProxy("Tile")
            protocol DockTile {
                var fileURL: URL { get }
            }
            """
        } diagnostics: {
            """
            @RuntimeClassProxy("Tile")
            ┬─────────────────────────
            ╰─ ⚠️ @RuntimeClassProxy: the protocol declares nothing to proxy. The generated type will validate an empty requirement list and dispatch nothing.
            protocol DockTile {
                var fileURL: URL { get }
                             ┬──
                             ╰─ 🛑 @RuntimeClassProxy: a proxied property must be optional. Reading a class resolved at runtime can fail, and there is no honest default to invent — write 'URL?' and handle nil at the call site.
            }
            """
        }
    }

    @Test func emptyProtocolWarns() {
        assertMacro {
            """
            @RuntimeClassProxy("Tile")
            protocol DockTile {
            }
            """
        } diagnostics: {
            """
            @RuntimeClassProxy("Tile")
            ┬─────────────────────────
            ╰─ ⚠️ @RuntimeClassProxy: the protocol declares nothing to proxy. The generated type will validate an empty requirement list and dispatch nothing.
            protocol DockTile {
            }
            """
        } expansion: {
            """
            protocol DockTile {
            }

            /// Signature-checked caller for `Tile`, generated by `@RuntimeClassProxy`.
            struct DockTileImplementation: DockTile {
                /// Name of the Objective-C class this proxy calls into.
                static let runtimeClassName: String = "Tile"

                /// Every method this proxy dispatches, with the signature it assumes.
                static let methodRequirements: [ObjCRuntimeToolbox.RuntimeClassProxySupport.MethodRequirement] = []

                /// Whether the class is present and every requirement still matches.
                /// Evaluated once; a mismatch is logged with both encodings.
                static let isSupported: Bool = ObjCRuntimeToolbox.RuntimeClassProxySupport.validate(
                    className: runtimeClassName,
                    requirements: methodRequirements,
                    proxyTypeName: "DockTileImplementation"
                )

                /// The object being called into.
                let host: AnyObject

                /// Wraps `host`, or fails when the class no longer matches what this
                /// proxy was generated against, or when `host` is not one of them.
                init?(_ host: AnyObject) {
                    guard Self.isSupported else {
                        return nil
                    }
                    guard ObjCRuntimeToolbox.RuntimeClassProxySupport.isInstance(host, ofClassNamed: Self.runtimeClassName) else {
                        return nil
                    }
                    self.host = host
                }


            }
            """
        }
    }

    @Test func methodsAndPropertiesExpand() {
        assertMacro {
            """
            @RuntimeClassProxy("Tile")
            protocol DockTile {
                var fileURL: URL? { get }
                var label: NSString? { get set }
                func dock() -> AnyObject?
                func removeReplacementAppImage()
                func setImage(_ image: AnyObject?, preferredGlassBackgroundStyle: Int)
            }
            """
        } expansion: {
            """
            protocol DockTile {
                var fileURL: URL? { get }
                var label: NSString? { get set }
                func dock() -> AnyObject?
                func removeReplacementAppImage()
                func setImage(_ image: AnyObject?, preferredGlassBackgroundStyle: Int)
            }

            /// Signature-checked caller for `Tile`, generated by `@RuntimeClassProxy`.
            struct DockTileImplementation: DockTile {
                /// Name of the Objective-C class this proxy calls into.
                static let runtimeClassName: String = "Tile"

                /// Every method this proxy dispatches, with the signature it assumes.
                static let methodRequirements: [ObjCRuntimeToolbox.RuntimeClassProxySupport.MethodRequirement] = [
                    .init(selector: NSSelectorFromString("fileURL"), typeEncoding: "@@:"),
                    .init(selector: NSSelectorFromString("label"), typeEncoding: "@@:"),
                    .init(selector: NSSelectorFromString("setLabel:"), typeEncoding: "v@:@"),
                    .init(selector: NSSelectorFromString("dock"), typeEncoding: "@@:"),
                    .init(selector: NSSelectorFromString("removeReplacementAppImage"), typeEncoding: "v@:"),
                    .init(selector: NSSelectorFromString("setImage:preferredGlassBackgroundStyle:"), typeEncoding: "v@:@q"),
                ]

                /// Whether the class is present and every requirement still matches.
                /// Evaluated once; a mismatch is logged with both encodings.
                static let isSupported: Bool = ObjCRuntimeToolbox.RuntimeClassProxySupport.validate(
                    className: runtimeClassName,
                    requirements: methodRequirements,
                    proxyTypeName: "DockTileImplementation"
                )

                /// The object being called into.
                let host: AnyObject

                /// Wraps `host`, or fails when the class no longer matches what this
                /// proxy was generated against, or when `host` is not one of them.
                init?(_ host: AnyObject) {
                    guard Self.isSupported else {
                        return nil
                    }
                    guard ObjCRuntimeToolbox.RuntimeClassProxySupport.isInstance(host, ofClassNamed: Self.runtimeClassName) else {
                        return nil
                    }
                    self.host = host
                }

                var fileURL: URL? {
                    let selector = NSSelectorFromString("fileURL")
                    guard let implementation = ObjCRuntimeToolbox.RuntimeClassProxySupport.implementation(of: selector, on: host) else {
                        return nil
                    }
                    let dispatchFunction = unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?).self)
                    return dispatchFunction(host, selector)?.takeUnretainedValue() as? URL
                }

                var label: NSString? {
                    get {
                        let selector = NSSelectorFromString("label")
                        guard let implementation = ObjCRuntimeToolbox.RuntimeClassProxySupport.implementation(of: selector, on: host) else {
                            return nil
                        }
                        let dispatchFunction = unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?).self)
                        return dispatchFunction(host, selector)?.takeUnretainedValue() as? NSString
                    }
                    nonmutating set {
                        let selector = NSSelectorFromString("setLabel:")
                        guard let implementation = ObjCRuntimeToolbox.RuntimeClassProxySupport.implementation(of: selector, on: host) else {
                            return
                        }
                        let dispatchFunction = unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector, NSString?) -> Void).self)
                        dispatchFunction(host, selector, newValue)
                    }
                }

                func dock() -> AnyObject? {
                    let selector = NSSelectorFromString("dock")
                    guard let implementation = ObjCRuntimeToolbox.RuntimeClassProxySupport.implementation(of: selector, on: host) else {
                        return nil
                    }
                    let dispatchFunction = unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?).self)
                    return dispatchFunction(host, selector)?.takeUnretainedValue()
                }

                func removeReplacementAppImage() {
                    let selector = NSSelectorFromString("removeReplacementAppImage")
                    guard let implementation = ObjCRuntimeToolbox.RuntimeClassProxySupport.implementation(of: selector, on: host) else {
                        return
                    }
                    let dispatchFunction = unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector) -> Void).self)
                    dispatchFunction(host, selector)
                }

                func setImage(_ image: AnyObject?, preferredGlassBackgroundStyle: Int) {
                    let selector = NSSelectorFromString("setImage:preferredGlassBackgroundStyle:")
                    guard let implementation = ObjCRuntimeToolbox.RuntimeClassProxySupport.implementation(of: selector, on: host) else {
                        return
                    }
                    let dispatchFunction = unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector, AnyObject?, Int) -> Void).self)
                    dispatchFunction(host, selector, image, preferredGlassBackgroundStyle)
                }
            }
            """
        }
    }

    @Test func copyFamilySelectorsTakeARetainedValue() {
        assertMacro {
            """
            @RuntimeClassProxy("Tile")
            protocol DockTile {
                func copyBadge() -> AnyObject?
                func newBadge() -> AnyObject?
                func copyright() -> AnyObject?
            }
            """
        } expansion: {
            """
            protocol DockTile {
                func copyBadge() -> AnyObject?
                func newBadge() -> AnyObject?
                func copyright() -> AnyObject?
            }

            /// Signature-checked caller for `Tile`, generated by `@RuntimeClassProxy`.
            struct DockTileImplementation: DockTile {
                /// Name of the Objective-C class this proxy calls into.
                static let runtimeClassName: String = "Tile"

                /// Every method this proxy dispatches, with the signature it assumes.
                static let methodRequirements: [ObjCRuntimeToolbox.RuntimeClassProxySupport.MethodRequirement] = [
                    .init(selector: NSSelectorFromString("copyBadge"), typeEncoding: "@@:"),
                    .init(selector: NSSelectorFromString("newBadge"), typeEncoding: "@@:"),
                    .init(selector: NSSelectorFromString("copyright"), typeEncoding: "@@:"),
                ]

                /// Whether the class is present and every requirement still matches.
                /// Evaluated once; a mismatch is logged with both encodings.
                static let isSupported: Bool = ObjCRuntimeToolbox.RuntimeClassProxySupport.validate(
                    className: runtimeClassName,
                    requirements: methodRequirements,
                    proxyTypeName: "DockTileImplementation"
                )

                /// The object being called into.
                let host: AnyObject

                /// Wraps `host`, or fails when the class no longer matches what this
                /// proxy was generated against, or when `host` is not one of them.
                init?(_ host: AnyObject) {
                    guard Self.isSupported else {
                        return nil
                    }
                    guard ObjCRuntimeToolbox.RuntimeClassProxySupport.isInstance(host, ofClassNamed: Self.runtimeClassName) else {
                        return nil
                    }
                    self.host = host
                }

                func copyBadge() -> AnyObject? {
                    let selector = NSSelectorFromString("copyBadge")
                    guard let implementation = ObjCRuntimeToolbox.RuntimeClassProxySupport.implementation(of: selector, on: host) else {
                        return nil
                    }
                    let dispatchFunction = unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?).self)
                    return dispatchFunction(host, selector)?.takeRetainedValue()
                }

                func newBadge() -> AnyObject? {
                    let selector = NSSelectorFromString("newBadge")
                    guard let implementation = ObjCRuntimeToolbox.RuntimeClassProxySupport.implementation(of: selector, on: host) else {
                        return nil
                    }
                    let dispatchFunction = unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?).self)
                    return dispatchFunction(host, selector)?.takeRetainedValue()
                }

                func copyright() -> AnyObject? {
                    let selector = NSSelectorFromString("copyright")
                    guard let implementation = ObjCRuntimeToolbox.RuntimeClassProxySupport.implementation(of: selector, on: host) else {
                        return nil
                    }
                    let dispatchFunction = unsafeBitCast(implementation, to: (@convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?).self)
                    return dispatchFunction(host, selector)?.takeUnretainedValue()
                }
            }
            """
        }
    }
}
