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
                    let defaultValue = WindowController()
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
                    let defaultValue = WindowController()
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
                    let defaultValue = WindowController()
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
            ╰─ 🛑 @AvailableMutating requires exactly one default value argument.
            private var windowController: WindowController
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
