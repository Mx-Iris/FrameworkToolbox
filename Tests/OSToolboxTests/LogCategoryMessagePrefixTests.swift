import Testing
import os

@testable import OSToolbox

// A category declared with `prefixesMessages: true` makes `#log(category:)`
// start every message with its name in brackets. The expansion asks
// `LoggableMacro._messagePrefix(for:)` for that text on every call, prefix or
// not, because the category is a runtime value the macro cannot see into.

@Suite
struct LogCategoryMessagePrefixTests {

    @Test func aCategoryDoesNotPrefixMessagesByDefault() {
        let category = LogCategory("Network")

        #expect(category.prefixesMessages == false)
        #expect(LoggableMacro._messagePrefix(for: category) == "")
    }

    @Test func aPrefixingCategoryPutsItsNameInBrackets() {
        let category = LogCategory("EngineMirroring", prefixesMessages: true)

        #expect(LoggableMacro._messagePrefix(for: category) == "[EngineMirroring] ")
    }

    @Test func turningThePrefixOffExplicitlyMatchesTheDefault() {
        let category = LogCategory("Network", prefixesMessages: false)

        #expect(LoggableMacro._messagePrefix(for: category) == "")
    }

    /// The prefix uses the name exactly as declared — no case change, no
    /// escaping — so it reads the same as the category in `log stream`.
    @Test func thePrefixKeepsTheNameAsDeclared() {
        let category = LogCategory("LK-Activation", prefixesMessages: true)

        #expect(LoggableMacro._messagePrefix(for: category) == "[LK-Activation] ")
    }

    /// `init(_:)` is kept as a separate initializer rather than given a
    /// defaulted second parameter, so the initializer still converts to a
    /// `(String) -> LogCategory` function value. This line stops compiling if
    /// the two are ever merged.
    @Test func theSingleArgumentInitializerStillWorksAsAFunctionValue() {
        let categories = ["Network", "Persistence"].map(LogCategory.init)

        #expect(categories == [LogCategory("Network"), LogCategory("Persistence")])
    }
}

// MARK: - The runtime switches

extension ProcessWideSwitchTests {
    @Suite
    struct LogCategoryMessagePrefixSwitchTests {

        init() {
            LoggingControl.enableAllCategories()
        }

        /// The per-category switch matches categories by name, so disabling a
        /// category reaches it whether or not it was declared to prefix messages.
        @Test func categorySwitchMatchesByNameRegardlessOfThePrefix() {
            defer { LoggingControl.enableAllCategories() }

            LoggingControl.setEnabled(false, for: LogCategory("LogCategoryMessagePrefixTests.switch"))

            #expect(LoggingControl.isEnabled(for: LogCategory("LogCategoryMessagePrefixTests.switch", prefixesMessages: true)) == false)
        }
    }
}
