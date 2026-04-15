# `#Selector` String Literal Macro — Design

Date: 2026-04-15
Target library: `FoundationToolbox`

## Motivation

Constructing an Objective-C selector from a plain string in Swift triggers the compiler warning:

> Use `#selector` instead of explicitly constructing a `Selector`

`#selector` is the right tool when the referenced method is visible to the Swift compiler, but it cannot be used when the selector targets a private/undocumented API, a method added at runtime, or any name that is only known as a string. The usual workaround is `NSSelectorFromString("...")`, which compiles cleanly but:

- loses the "this is a selector literal" affordance,
- offers no compile-time sanity check on the string,
- reads as a runtime conversion rather than a literal construction.

This design introduces a freestanding expression macro `#Selector` that parses a string literal at compile time, performs a small amount of validation, and expands to `NSSelectorFromString(...)`.

## Goals

- Provide a literal-style syntax for building `Selector` values from a fixed string.
- Avoid the `Selector(String)` constructor warning without suppressing it anywhere.
- Catch the most common typos (empty strings, whitespace-containing strings, non-literal arguments) at compile time.
- Follow the existing `#URL` macro conventions so the two macros feel like a matched set.

## Non-Goals

- Validating that the selector is syntactically a legal Objective-C method name (no letter-start check, no colon-count check). Users may deliberately target unusual private selectors.
- Resolving the selector at compile time against any class, protocol, or runtime.
- Replacing `#selector` for the common case where the referenced method exists in Swift.

## Usage

```swift
import FoundationToolbox

let selector = #Selector("tableView:didSelectRowAtIndexPath:")
// Expands to:
let selector = NSSelectorFromString("tableView:didSelectRowAtIndexPath:")
```

Typical call sites:

- `perform(_:with:)` on private selectors.
- `NSInvocation`-style dynamic dispatch.
- Bridging to Objective-C runtime APIs where the method name is only available as a string.

## Design

### Files

| Role | Path |
|---|---|
| Public macro declaration | `Sources/FoundationToolbox/Macros/SelectorMacro.swift` |
| Macro implementation     | `Sources/FoundationToolboxMacros/SelectorMacro.swift` |
| Plugin registration      | `Sources/FoundationToolboxMacros/MainPlugin.swift` (add `SelectorMacro.self`) |
| Macro tests              | `Tests/FoundationToolboxMacroTests/SelectorMacroTests.swift` |
| Runtime smoke test       | `Tests/FoundationToolboxTests/SelectorMacroRuntimeTests.swift` |

### Public declaration

```swift
import Foundation

/// A freestanding macro that wraps a string literal into a `Selector` value
/// without triggering the `Selector(String)` initializer warning.
///
/// Use this when you need to reference a selector whose method is not visible
/// to the Swift compiler (e.g. private API, dynamically added methods). When
/// the method *is* visible, prefer the built-in `#selector`, which performs
/// full compile-time validation against the real declaration.
///
///     let selector = #Selector("tableView:didSelectRowAtIndexPath:")
///
/// expands to
///
///     NSSelectorFromString("tableView:didSelectRowAtIndexPath:")
@freestanding(expression)
public macro Selector(_ name: StaticString) -> Selector = #externalMacro(
    module: "FoundationToolboxMacros",
    type: "SelectorMacro"
)
```

`StaticString` mirrors `#URL` and forces the argument to be a literal at the language level (a helpful hint before we re-validate it in the macro).

### Expansion

The macro emits a call to `NSSelectorFromString`, not `Selector(_:)`. The latter would re-introduce the very warning the macro is meant to avoid, because warnings are still reported on macro-expanded code.

```swift
return "NSSelectorFromString(\"\(raw: text)\")"
```

### Validation rules

Inside `expansion(of:in:)`:

1. The macro must have exactly one argument. Otherwise throw `noArguments`.
2. The argument must be a single-segment `StringLiteralExprSyntax` (no interpolation, no multi-segment literals). Otherwise throw `mustBeValidStringLiteral`. This mirrors `URLMacro`'s check.
3. The extracted text must be non-empty and must not contain any character from `CharacterSet.whitespacesAndNewlines`. Otherwise throw `containsWhitespaceOrEmpty`.

Deliberately **not** checked:

- Whether the string is a valid Objective-C identifier.
- Whether the colon count matches a realistic arity.
- Whether the selector actually exists on any class.

### Errors

```swift
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

Style matches `URLError` exactly.

## Testing

### Macro tests (`swift-macro-testing`)

Using `assertMacro` in `SelectorMacroTests.swift`:

- **Single-argument selector:** `#Selector("viewDidLoad")` expands to `NSSelectorFromString("viewDidLoad")`.
- **Multi-argument selector:** `#Selector("tableView:didSelectRowAtIndexPath:")` expands as expected.
- **Empty string:** `#Selector("")` produces the `containsWhitespaceOrEmpty` diagnostic.
- **Whitespace string:** `#Selector("foo bar")` produces the `containsWhitespaceOrEmpty` diagnostic.
- **Non-literal argument:** `#Selector(name)` (where `name` is a variable) produces the `mustBeValidStringLiteral` diagnostic.
- **Interpolated string:** `#Selector("\(foo):")` produces the `mustBeValidStringLiteral` diagnostic.

### Runtime smoke test

In `FoundationToolboxTests`, assert that `#Selector("description")` is equal to `#selector(NSObject.description)` at runtime, to confirm the expansion compiles and round-trips through the ObjC runtime.

## Documentation

The doc-comment on the public `#Selector` declaration explains:

- Why this macro exists (`Selector(String)` warning).
- When to prefer `#selector` (compile-time method check) vs `#Selector` (opaque string).
- That no syntactic validation of selector format is performed.

No separate README entry required unless the repo-wide macro list is updated elsewhere.

## Out of scope / future work

- Strict validation mode (letter-start, colon matching) could be added later behind a separate macro if real usage shows it is wanted.
- A `@freestanding(expression)` overload returning `String` for APIs that want the raw selector name is not planned.
