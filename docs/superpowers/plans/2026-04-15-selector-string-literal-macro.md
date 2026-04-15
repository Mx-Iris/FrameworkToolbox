# `#Selector` String Literal Macro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a freestanding expression macro `#Selector` in `FoundationToolbox` that wraps a string literal into a `Selector` value without triggering the `Selector(String)` compiler warning.

**Architecture:** Mirrors the existing `#URL` macro. `SelectorMacro` lives in the `FoundationToolboxMacros` compiler-plugin target as an `ExpressionMacro`. The public declaration lives in `FoundationToolbox/Macros/SelectorMacro.swift`. Expansion emits a call to `NSSelectorFromString` (which does not trigger the warning). Validation is lenient: single-segment string literal + non-empty + no whitespace.

**Tech Stack:** Swift 6.2 toolchain (language mode v5), `swift-syntax` 509.1.0..<602.0.0, `swift-macro-testing` 0.5.0, Swift Testing.

**Reference spec:** `docs/superpowers/specs/2026-04-15-selector-string-literal-macro-design.md`

**File map:**

| Role | Path |
|---|---|
| Macro implementation | `Sources/FoundationToolboxMacros/SelectorMacro.swift` (new) |
| Plugin registration  | `Sources/FoundationToolboxMacros/MainPlugin.swift` (modify) |
| Public declaration   | `Sources/FoundationToolbox/Macros/SelectorMacro.swift` (new) |
| Macro tests          | `Tests/FoundationToolboxMacroTests/SelectorMacroTests.swift` (new) |
| Runtime smoke test   | `Tests/FoundationToolboxTests/SelectorMacroRuntimeTests.swift` (new) |

---

## Task 1: Scaffold macro implementation stub + register with plugin

**Files:**
- Create: `Sources/FoundationToolboxMacros/SelectorMacro.swift`
- Modify: `Sources/FoundationToolboxMacros/MainPlugin.swift`

- [ ] **Step 1: Create macro implementation stub**

Create `Sources/FoundationToolboxMacros/SelectorMacro.swift` with the following contents. This intentionally starts as a stub that returns `NSSelectorFromString("")` so the test file in Task 2 will compile but the assertions will fail (so we can observe the red → green transition):

```swift
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

public struct SelectorMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        return #"NSSelectorFromString("")"#
    }
}

enum SelectorMacroError: Error, CustomStringConvertible {
    case noArguments
    case mustBeValidStringLiteral
    case containsWhitespaceOrEmpty

    var description: String {
        switch self {
        case .noArguments:
            return "The macro does not have any arguments"
        case .mustBeValidStringLiteral:
            return "Argument must be a string literal"
        case .containsWhitespaceOrEmpty:
            return "Selector string must be non-empty and must not contain whitespace"
        }
    }
}
```

- [ ] **Step 2: Register the macro in `MainPlugin`**

Open `Sources/FoundationToolboxMacros/MainPlugin.swift`. It currently looks like:

```swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MainPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        URLMacro.self,
        LoggableMacro.self,
        LogMacro.self,
        OSAllocatedUnfairLockMacro.self,
    ]
}
```

Add `SelectorMacro.self` to the list:

```swift
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MainPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        URLMacro.self,
        LoggableMacro.self,
        LogMacro.self,
        OSAllocatedUnfairLockMacro.self,
        SelectorMacro.self,
    ]
}
```

- [ ] **Step 3: Build the macro target to verify it compiles**

Run: `swift package update && swift build --target FoundationToolboxMacros 2>&1 | xcsift`
Expected: success with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/FoundationToolboxMacros/SelectorMacro.swift Sources/FoundationToolboxMacros/MainPlugin.swift
git commit -m "feat: scaffold SelectorMacro and register plugin"
```

---

## Task 2: Write failing macro tests

**Files:**
- Create: `Tests/FoundationToolboxMacroTests/SelectorMacroTests.swift`

- [ ] **Step 1: Create the macro test file**

Create `Tests/FoundationToolboxMacroTests/SelectorMacroTests.swift` with every test case up front. This follows the pattern in `URLMacroTests.swift` — `@Suite(.macros(...))` binds the short macro name to the implementation type, and each `@Test` uses `assertMacro`:

```swift
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
                           ┬───────────
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
                           ┬──────────────────
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
                           ┬─────────────
                           ╰─ 🛑 Argument must be a string literal
            """
        }
    }
}
```

> NOTE: the exact underline lengths and emoji column in the `diagnostics` expectations are generated by `swift-macro-testing`. If the test file reports a mismatch when you run it in Task 3, re-record by running with the `MT_ASSERT_MACRO_RECORD=1` environment variable (see `swift-macro-testing` README) and commit the regenerated fixtures. Do this only after confirming the diagnostic *message* is correct.

- [ ] **Step 2: Run the tests — they should fail**

Run: `swift test --filter FoundationToolboxMacroTests.SelectorMacroTests 2>&1 | xcsift`
Expected: the two `expansion` tests fail because the stub always returns `NSSelectorFromString("")`; the three `diagnostics` tests fail because the stub does not emit any diagnostics. Confirm the failures are about assertion mismatches, not build errors.

- [ ] **Step 3: Commit the failing tests**

```bash
git add Tests/FoundationToolboxMacroTests/SelectorMacroTests.swift
git commit -m "test: add failing SelectorMacro expansion and diagnostic tests"
```

---

## Task 3: Implement the macro expansion logic

**Files:**
- Modify: `Sources/FoundationToolboxMacros/SelectorMacro.swift`

- [ ] **Step 1: Replace the stub `expansion` body with real logic**

Open `Sources/FoundationToolboxMacros/SelectorMacro.swift` and replace the body of `expansion(of:in:)` so the full file reads:

```swift
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

public struct SelectorMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let argument = node.arguments.first else {
            throw SelectorMacroError.noArguments
        }

        guard let stringLiteralExpr = argument.expression.as(StringLiteralExprSyntax.self),
              stringLiteralExpr.segments.count == 1,
              let segment = stringLiteralExpr.segments.first?.as(StringSegmentSyntax.self)
        else {
            throw SelectorMacroError.mustBeValidStringLiteral
        }

        let text = segment.content.text

        guard !text.isEmpty,
              text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            throw SelectorMacroError.containsWhitespaceOrEmpty
        }

        return #"NSSelectorFromString("\#(raw: text)")"#
    }
}

enum SelectorMacroError: Error, CustomStringConvertible {
    case noArguments
    case mustBeValidStringLiteral
    case containsWhitespaceOrEmpty

    var description: String {
        switch self {
        case .noArguments:
            return "The macro does not have any arguments"
        case .mustBeValidStringLiteral:
            return "Argument must be a string literal"
        case .containsWhitespaceOrEmpty:
            return "Selector string must be non-empty and must not contain whitespace"
        }
    }
}
```

Notes on the key moves:
- `node.arguments.first` — freestanding macros expose arguments as `LabeledExprListSyntax`; `.first?.expression` is the underlying expression tree.
- `StringLiteralExprSyntax.segments.count == 1` — rejects interpolated or multi-segment literals (same guard as `URLMacro`).
- `segment.content.text` — raw string value from the source.
- `CharacterSet.whitespacesAndNewlines` covers space, tab, newline, and other Unicode whitespace — matches the spec's "no whitespace" rule without hand-rolling the set.
- The `#"..."#` raw string with `\#(raw: text)` interpolates without re-escaping.

- [ ] **Step 2: Run the macro tests — they should pass**

Run: `swift test --filter FoundationToolboxMacroTests.SelectorMacroTests 2>&1 | xcsift`
Expected: all five tests pass. If the `diagnostics` tests fail with underline-length mismatches, re-record them per the NOTE at the end of Task 2 Step 1.

- [ ] **Step 3: Commit the implementation**

```bash
git add Sources/FoundationToolboxMacros/SelectorMacro.swift
git commit -m "feat: implement SelectorMacro expansion and validation"
```

---

## Task 4: Add the public macro declaration

**Files:**
- Create: `Sources/FoundationToolbox/Macros/SelectorMacro.swift`

- [ ] **Step 1: Create the public declaration file**

Create `Sources/FoundationToolbox/Macros/SelectorMacro.swift`:

```swift
import Foundation

/// A freestanding macro that wraps a string literal into a `Selector` value
/// without triggering the `Selector(String)` initializer warning.
///
/// Use this when you need to reference a selector whose method is not visible
/// to the Swift compiler (for example, a private or dynamically added method).
/// When the method *is* visible, prefer the built-in `#selector`, which
/// performs full compile-time validation against the real declaration.
///
/// Creating a `Selector` from a string literal like this
///
///     let selector = #Selector("tableView:didSelectRowAtIndexPath:")
///
/// results in the following code automatically
///
///     NSSelectorFromString("tableView:didSelectRowAtIndexPath:")
///
/// The macro performs a lenient compile-time check: the argument must be a
/// single-segment string literal that is non-empty and contains no whitespace.
/// It does **not** validate that the string is a syntactically legal
/// Objective-C method name.
@freestanding(expression)
public macro Selector(_ name: StaticString) -> Selector = #externalMacro(
    module: "FoundationToolboxMacros",
    type: "SelectorMacro"
)
```

- [ ] **Step 2: Build the full package to verify the declaration links**

Run: `swift build 2>&1 | xcsift`
Expected: success with no errors.

- [ ] **Step 3: Commit the declaration**

```bash
git add Sources/FoundationToolbox/Macros/SelectorMacro.swift
git commit -m "feat: expose #Selector macro from FoundationToolbox"
```

---

## Task 5: Runtime smoke test

**Files:**
- Create: `Tests/FoundationToolboxTests/SelectorMacroRuntimeTests.swift`

- [ ] **Step 1: Create the runtime test file**

Create `Tests/FoundationToolboxTests/SelectorMacroRuntimeTests.swift`:

```swift
import Testing
import Foundation
@testable import FoundationToolbox

@Suite("#Selector runtime behavior")
struct SelectorMacroRuntimeTests {

    @Test("single-argument selector matches #selector")
    func singleArgumentMatchesBuiltIn() {
        let fromMacro = #Selector("description")
        let fromBuiltIn = #selector(NSObject.description)
        #expect(fromMacro == fromBuiltIn)
    }

    @Test("selector string round-trips through the ObjC runtime")
    func roundTripString() {
        let raw = "viewDidLoad"
        let selector = #Selector("viewDidLoad")
        #expect(NSStringFromSelector(selector) == raw)
    }

    @Test("multi-argument selector round-trips")
    func multiArgumentRoundTrip() {
        let raw = "tableView:didSelectRowAtIndexPath:"
        let selector = #Selector("tableView:didSelectRowAtIndexPath:")
        #expect(NSStringFromSelector(selector) == raw)
    }
}
```

- [ ] **Step 2: Run the runtime tests**

Run: `swift test --filter FoundationToolboxTests.SelectorMacroRuntimeTests 2>&1 | xcsift`
Expected: all three tests pass.

- [ ] **Step 3: Run the full test suite as a final regression check**

Run: `swift test 2>&1 | xcsift`
Expected: all tests pass across all test targets, no new warnings, no regressions in the other macro suites.

- [ ] **Step 4: Commit**

```bash
git add Tests/FoundationToolboxTests/SelectorMacroRuntimeTests.swift
git commit -m "test: add #Selector runtime smoke tests"
```

---

## Done criteria

- [ ] `swift build` passes with no warnings from `#Selector` usages in the package.
- [ ] `SelectorMacroTests` (5 tests) pass.
- [ ] `SelectorMacroRuntimeTests` (3 tests) pass.
- [ ] `swift test` passes end-to-end.
- [ ] Five commits, one per task.
- [ ] Spec `docs/superpowers/specs/2026-04-15-selector-string-literal-macro-design.md` is fully realized: public declaration, implementation, lenient validation, `NSSelectorFromString` expansion, `SelectorMacroError` enum, macro tests for valid/invalid/non-literal cases, runtime smoke test.
