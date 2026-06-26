import MacroTesting
import Testing

@testable import ObjCRuntimeToolboxMacros

// MARK: - Diagnostics

@Suite(.macros([
    "DynamicSubclassHook": DynamicSubclassHookMacro.self,
    "DynamicSubclassOverride": DynamicSubclassOverrideMacro.self,
]))
struct DynamicSubclassHookDiagnosticsTests {

    @Test func throwsIsRejected() {
        assertMacro {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "Throws")
            struct ThrowsHook {
                @DynamicSubclassOverride
                func greet() throws -> String { "" }
            }
            """
        } diagnostics: {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "Throws")
            struct ThrowsHook {
                @DynamicSubclassOverride
                func greet() throws -> String { "" }
                             ┬─────
                             ╰─ 🛑 @DynamicSubclassOverride does not support 'throws' methods. Catch the error inside the hook body instead.
            }
            """
        }
    }

    @Test func asyncIsRejected() {
        assertMacro {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "Async")
            struct AsyncHook {
                @DynamicSubclassOverride
                func greet() async -> String { "" }
            }
            """
        } diagnostics: {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "Async")
            struct AsyncHook {
                @DynamicSubclassOverride
                func greet() async -> String { "" }
                             ┬────
                             ╰─ 🛑 @DynamicSubclassOverride does not support 'async' methods — Objective-C IMP blocks cannot bridge Swift continuations.
            }
            """
        }
    }

    @Test func mainActorIsRejected() {
        assertMacro {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "MainActor")
            struct MainActorHook {
                @MainActor
                @DynamicSubclassOverride
                func greet() -> String { "" }
            }
            """
        } diagnostics: {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "MainActor")
            struct MainActorHook {
                @MainActor
                ┬─────────
                ╰─ 🛑 @DynamicSubclassOverride does not support @MainActor methods — the ObjC IMP block does not carry actor isolation.
                @DynamicSubclassOverride
                func greet() -> String { "" }
            }
            """
        }
    }

    @Test func inoutParameterIsRejected() {
        assertMacro {
            """
            @DynamicSubclassHook(of: Counter.self, suffix: "Inout")
            struct InoutHook {
                @DynamicSubclassOverride
                func bump(_ value: inout Int) { }
            }
            """
        } diagnostics: {
            """
            @DynamicSubclassHook(of: Counter.self, suffix: "Inout")
            struct InoutHook {
                @DynamicSubclassOverride
                func bump(_ value: inout Int) { }
                                   ┬────
                                   ╰─ 🛑 @DynamicSubclassOverride parameter cannot use 'inout' / 'borrowing' / 'consuming' — these specifiers don't bridge to @convention(c).
            }
            """
        }
    }

    @Test func nonUnderscoreFirstParameterLabelIsRejected() {
        assertMacro {
            """
            @DynamicSubclassHook(of: Formatter.self, suffix: "BadLabel")
            struct BadLabelHook {
                @DynamicSubclassOverride
                func format(message: String) -> String { "" }
            }
            """
        } diagnostics: {
            """
            @DynamicSubclassHook(of: Formatter.self, suffix: "BadLabel")
            struct BadLabelHook {
                @DynamicSubclassOverride
                func format(message: String) -> String { "" }
                            ┬──────
                            ╰─ 🛑 @DynamicSubclassOverride: first parameter label must be '_'. Swift's @objc bridging produces a selector like '<baseName>With<CapitalizedLabel>:' for labelled first parameters, but this macro derives '<baseName><label>:' which won't match. Either drop the label (use '_'), or pass an explicit selector: @DynamicSubclassOverride("real:selector:").
            }
            """
        }
    }

    @Test func enumContainerIsRejected() {
        assertMacro {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "Enum")
            enum EnumHook { }
            """
        } diagnostics: {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "Enum")
            ┬─────────────────────────────────────────────────────
            ╰─ 🛑 @DynamicSubclassHook can only be applied to a struct or class, not a enum.
            enum EnumHook { }
            """
        }
    }

    @Test func missingDiscriminatorIsRejected() {
        assertMacro {
            """
            @DynamicSubclassHook(of: Greeter.self)
            struct NoDiscriminatorHook { }
            """
        } diagnostics: {
            """
            @DynamicSubclassHook(of: Greeter.self)
            ┬─────────────────────────────────────
            ╰─ 🛑 @DynamicSubclassHook requires at least one of 'prefix:' or 'suffix:' to be non-empty. They identify the hook variant in the dynamic-subclass cache and must differ between variants targeting the same base class.
            struct NoDiscriminatorHook { }
            """
        }
    }

    @Test func bothEmptyPrefixAndSuffixIsRejected() {
        assertMacro {
            """
            @DynamicSubclassHook(of: Greeter.self, prefix: "", suffix: "")
            struct EmptyDiscriminatorHook { }
            """
        } diagnostics: {
            """
            @DynamicSubclassHook(of: Greeter.self, prefix: "", suffix: "")
            ┬─────────────────────────────────────────────────────────────
            ╰─ 🛑 @DynamicSubclassHook requires at least one of 'prefix:' or 'suffix:' to be non-empty. They identify the hook variant in the dynamic-subclass cache and must differ between variants targeting the same base class.
            struct EmptyDiscriminatorHook { }
            """
        }
    }

    @Test func baselineSelectorIsRejected() {
        assertMacro {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "Baseline")
            struct BaselineHook {
                @DynamicSubclassOverride
                func conformsToProtocol(_ proto: Protocol) -> Bool { false }
            }
            """
        } diagnostics: {
            """
            @DynamicSubclassHook(of: Greeter.self, suffix: "Baseline")
            ┬─────────────────────────────────────────────────────────
            ╰─ ⚠️ @DynamicSubclassHook: no methods are tagged with @DynamicSubclassOverride. The hook will install the dynamic subclass but register no IMP overrides. Did you forget to tag your override methods?
            struct BaselineHook {
                @DynamicSubclassOverride
                func conformsToProtocol(_ proto: Protocol) -> Bool { false }
                     ┬─────────────────
                     ╰─ 🛑 @DynamicSubclassOverride: 'conformsToProtocol:' is reserved for the dynamic subclass's baseline overrides (-class / -respondsToSelector: / -conformsToProtocol:). Choose a different selector or omit this method.
            }
            """
        }
    }
}
