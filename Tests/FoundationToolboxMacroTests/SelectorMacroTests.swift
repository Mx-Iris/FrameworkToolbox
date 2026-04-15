import MacroTesting
import Testing

@testable import FoundationToolboxMacros

@Suite(.macros(["Selector": SelectorMacro.self]))
struct SelectorMacroTests {

    @Test func singleArgumentSelector() {
        assertMacro {
            """
            let selector = #Selector("viewDidLoad")
            """
        } expansion: {
            """
            let selector = NSSelectorFromString("viewDidLoad")
            """
        }
    }

    @Test func multiArgumentSelector() {
        assertMacro {
            """
            let selector = #Selector("tableView:didSelectRowAtIndexPath:")
            """
        } expansion: {
            """
            let selector = NSSelectorFromString("tableView:didSelectRowAtIndexPath:")
            """
        }
    }

    @Test func emptyStringProducesDiagnostic() {
        assertMacro {
            """
            let selector = #Selector("")
            """
        } diagnostics: {
            """
            let selector = #Selector("")
                           ┬────────────
                           ╰─ 🛑 Selector string must be non-empty and must not contain whitespace
            """
        }
    }

    @Test func whitespaceStringProducesDiagnostic() {
        assertMacro {
            """
            let selector = #Selector("foo bar")
            """
        } diagnostics: {
            """
            let selector = #Selector("foo bar")
                           ┬───────────────────
                           ╰─ 🛑 Selector string must be non-empty and must not contain whitespace
            """
        }
    }

    @Test func nonLiteralArgumentProducesDiagnostic() {
        assertMacro {
            """
            let name = "viewDidLoad"
            let selector = #Selector(name)
            """
        } diagnostics: {
            """
            let name = "viewDidLoad"
            let selector = #Selector(name)
                           ┬──────────────
                           ╰─ 🛑 Argument must be a string literal
            """
        }
    }
}
