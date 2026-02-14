import MacroTesting
import Testing

@testable import FoundationToolboxMacros

@Suite(.macros(["URL": URLMacro.self]))
struct URLMacroTests {

    @Test func validURL() {
        assertMacro {
            """
            let url = #URL("https://www.apple.com")
            """
        } expansion: {
            """
            let url = URL(string: "https://www.apple.com")!
            """
        }
    }

    @Test func validURLWithPath() {
        assertMacro {
            """
            let url = #URL("https://example.com/path/to/resource?query=value")
            """
        } expansion: {
            """
            let url = URL(string: "https://example.com/path/to/resource?query=value")!
            """
        }
    }

    @Test func fileURL() {
        assertMacro {
            """
            let url = #URL("file:///tmp/test.txt")
            """
        } expansion: {
            """
            let url = URL(string: "file:///tmp/test.txt")!
            """
        }
    }

    @Test func invalidURL() {
        assertMacro {
            """
            let url = #URL("")
            """
        } diagnostics: {
            """
            let url = #URL("")
                      ┬───────
                      ╰─ 🛑 The string does not represent a valid URL
            """
        }
    }
}
