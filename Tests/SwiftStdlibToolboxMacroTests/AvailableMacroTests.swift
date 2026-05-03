import MacroTesting
import Testing

@testable import SwiftStdlibToolboxMacros

@Suite(.macros([
    "AvailableNonMutating": AvailableNonMutatingMacro.self,
    "AvailableMutating": AvailableMutatingMacro.self,
]))
struct AvailableMacroTests {

    @Test func nonMutatingProperty() {
        assertMacro {
            """
            @AvailableNonMutating(WindowController())
            @available(macOS 15, *)
            private var windowController: WindowController
            """
        } expansion: {
            """
            @available(macOS 15, *)
            private var windowController: WindowController {
                get {
                    if let existingValue = windowControllerStorage as? WindowController {
                        return existingValue
                    }
                    let defaultValue: WindowController = WindowController()
                    windowControllerStorage = defaultValue
                    return defaultValue
                }
            }

            private var windowControllerStorage: Any?
            """
        }
    }

    @Test func mutatingProperty() {
        assertMacro {
            """
            @AvailableMutating(WindowController())
            @available(macOS 15, *)
            private var windowController: WindowController
            """
        } expansion: {
            """
            @available(macOS 15, *)
            private var windowController: WindowController {
                get {
                    if let existingValue = windowControllerStorage as? WindowController {
                        return existingValue
                    }
                    let defaultValue: WindowController = WindowController()
                    windowControllerStorage = defaultValue
                    return defaultValue
                }
                set {
                    windowControllerStorage = newValue
                }
            }

            private var windowControllerStorage: Any?
            """
        }
    }

    @Test func staticMutatingProperty() {
        assertMacro {
            """
            @AvailableMutating(WindowController())
            @available(macOS 15, *)
            private static var windowController: WindowController
            """
        } expansion: {
            """
            @available(macOS 15, *)
            private static var windowController: WindowController {
                get {
                    if let existingValue = windowControllerStorage as? WindowController {
                        return existingValue
                    }
                    let defaultValue: WindowController = WindowController()
                    windowControllerStorage = defaultValue
                    return defaultValue
                }
                set {
                    windowControllerStorage = newValue
                }
            }

            private static var windowControllerStorage: Any?
            """
        }
    }

    @Test func missingDefaultValue() {
        assertMacro {
            """
            @AvailableMutating
            private var windowController: WindowController
            """
        } diagnostics: {
            """
            @AvailableMutating
            ┬─────────────────
            ╰─ 🛑 @AvailableMutating requires a default value, either as a macro argument or as a property initializer.
            private var windowController: WindowController
            """
        }
    }

    @Test func mutatingPropertyWithInitializer() {
        assertMacro {
            """
            @AvailableMutating
            @available(macOS 12, *)
            private var attributedString: AttributedString = ""
            """
        } expansion: {
            """
            @available(macOS 12, *)
            private var attributedString: AttributedString {
                get {
                    if let existingValue = attributedStringStorage as? AttributedString {
                        return existingValue
                    }
                    let defaultValue: AttributedString = ""
                    attributedStringStorage = defaultValue
                    return defaultValue
                }
                set {
                    attributedStringStorage = newValue
                }
            }

            private var attributedStringStorage: Any?
            """
        }
    }

    @Test func nonMutatingPropertyWithInitializer() {
        assertMacro {
            """
            @AvailableNonMutating
            @available(macOS 15, *)
            private var windowController: WindowController = WindowController()
            """
        } expansion: {
            """
            @available(macOS 15, *)
            private var windowController: WindowController {
                get {
                    if let existingValue = windowControllerStorage as? WindowController {
                        return existingValue
                    }
                    let defaultValue: WindowController = WindowController()
                    windowControllerStorage = defaultValue
                    return defaultValue
                }
            }

            private var windowControllerStorage: Any?
            """
        }
    }

    @Test func conflictingArgumentAndInitializer() {
        assertMacro {
            """
            @AvailableMutating(WindowController())
            private var windowController: WindowController = WindowController()
            """
        } diagnostics: {
            """
            @AvailableMutating(WindowController())
            ┬─────────────────────────────────────
            ╰─ 🛑 @AvailableMutating cannot specify both a macro argument and a property initializer.
            private var windowController: WindowController = WindowController()
            """
        }
    }

    @Test func missingExplicitType() {
        assertMacro {
            """
            @AvailableNonMutating(WindowController())
            private var windowController
            """
        } diagnostics: {
            """
            @AvailableNonMutating(WindowController())
            ┬────────────────────────────────────────
            ╰─ 🛑 @AvailableNonMutating requires an explicit type annotation.
            private var windowController
            """
        }
    }
}
