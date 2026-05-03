---
name: loggable-and-log
description: Use when adding os.log instrumentation in Swift code that depends on FrameworkToolbox — applying `@Loggable` to a type, writing `#log(.level, ...)` calls, configuring custom subsystem/category/access level, choosing a privacy level, or debugging logger setup and pre-macOS 11 fallback behavior.
---

# Using `@Loggable` and `#log`

## Overview

`@Loggable` and `#log` are a pair of Swift macros from `FoundationToolbox` (in the FrameworkToolbox package) that generate `os.log`-based logging infrastructure for a type with zero protocol conformance and zero boilerplate.

- `@Loggable` is an **attached member macro**. It synthesizes `subsystem`, `category`, `_osLog`, and `logger` storage on the annotated type.
- `#log` is a **freestanding expression macro**. It expands into a version-checked branch that calls `os.Logger` on macOS 11+/iOS 14+/watchOS 7+/tvOS 14+ and falls back to the legacy `os_log` C API on older OS versions.

**Core invariant — they are designed to be used together.** `#log` expands into code that references `Self.logger` and `Self._osLog`, which only exist on a type annotated with `@Loggable`. Using `#log` outside such a type is a compile error.

## When to Use

Use `@Loggable` + `#log` instead of any of the following:
- Hand-written `os.Logger(subsystem:category:)` stored properties
- Hand-written `static let _osLog = OSLog(...)` plus availability-gated branches
- Conformance to a "Loggable" protocol that exposes `logger`
- Wrapper functions like `log(_ message: String)` that lose `os_log`'s static format-string benefits

Skip these macros when:
- The target file does not `import FoundationToolbox` and adding the dependency is not desired.
- The platform does not have `os` (e.g., Linux). Both macros are wrapped in `#if canImport(os)` and the type's `logger`/`_osLog` will not exist there.
- The code is in a free function, top-level script, global constant, or extension on a type you cannot annotate with `@Loggable` — `#log` requires a `Self` with the synthesized members.

## Quick Reference

| Need | Code |
|------|------|
| Add a logger to a type | `@Loggable struct Foo { }` |
| Public logger members | `@Loggable(.public) struct Foo { }` |
| Custom subsystem | `@Loggable(subsystem: "com.acme.app") struct Foo { }` |
| Custom category | `@Loggable(category: "Network") struct Foo { }` |
| Both, with access level | `@Loggable(.internal, subsystem: "com.acme.app", category: "Network") class Foo { }` |
| Emit a log line | `#log(.info, "User \(id, privacy: .private) signed in")` |
| Available log levels | `.debug` / `.info` / `.default` / `.error` / `.fault` |
| Available privacy values | `.public` / `.private` / `.sensitive` / `.auto` (each also takes `mask: .hash` / `.none`) |
| Available format hints | `.fixed` / `.hex` / `.exponential` / `.hybrid` / `.decimal` / `.octal` (numeric) and `.left(columns:)` / `.right(columns:)` (string alignment) |

## Setup

```swift
import Foundation
import os.log
import FoundationToolbox
```

All three imports are required at the call site:

- `FoundationToolbox` — provides the `@Loggable` and `#log` macro declarations.
- `os.log` — the macro expansions reference `OSLog`, `os_log`, and `os.Logger` directly, so the `os` module must be in scope. (`import os` works too.)
- `Foundation` — `@Loggable` expands into code that reads `Bundle.main.bundleIdentifier` (or `Bundle(for: self).bundleIdentifier` on classes) when no explicit `subsystem:` is given.

The macros are gated on `#if canImport(os)`, so they are unavailable on platforms without Apple's `os` framework (Linux, Windows). Code that must compile cross-platform should wrap the call site in `#if canImport(os)` itself.

## `@Loggable` — Attached Member Macro

### Signature

```swift
@attached(member, names: named(_osLog), named(category), named(subsystem), named(logger))
public macro Loggable(
    _ accessLevel: AccessLevel = .private,
    subsystem: StaticString? = nil,
    category: StaticString? = nil
)
```

### What it generates

For `@Loggable struct UserService { }`:

```swift
struct UserService {
    private nonisolated static var category: String { "UserService" }
    private nonisolated static var subsystem: String { Bundle.main.bundleIdentifier ?? "UserService" }
    private nonisolated static let _osLog = OSLog(subsystem: subsystem, category: category)

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    private nonisolated static let logger = os.Logger(subsystem: subsystem, category: category)

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    private nonisolated var logger: os.Logger { Self.logger }
}
```

### Parameters

**`accessLevel`** — first positional argument, defaults to `.private`. Accepts `.private`, `.fileprivate`, `.internal`, `.package`, `.public`. Controls visibility of every generated member. The default `.private` is a deliberate choice — most call sites only need to use the logger from inside the type itself.

**`subsystem:`** — optional `StaticString`. When omitted, the macro synthesizes a `Bundle`-based default:
- For `class` types: `Bundle(for: self).bundleIdentifier ?? "<TypeName>"`
- For `struct` / `enum` / `actor`: `Bundle.main.bundleIdentifier ?? "<TypeName>"`

**`category:`** — optional `StaticString`. When omitted, defaults to the type name as a string literal (e.g., `"UserService"`).

The `StaticString` requirement means **only string literals are accepted**. You cannot pass a runtime `String`, a constant defined elsewhere, or a string-interpolation expression.

### Type support

Works on `struct`, `class`, `enum`, and `actor`. The `class` variant uses `Bundle(for: self)` so that the bundle identifier is resolved against the bundle that owns the class — important for frameworks where `Bundle.main` would resolve to the host app instead of the framework.

`MainActor`-isolated types are supported because every generated member is marked `nonisolated`. You can call `#log(...)` from any actor isolation domain.

## `#log` — Freestanding Expression Macro

### Signature

```swift
@freestanding(expression)
public macro log(_ level: LoggableMacro.OSLogType, _ message: LoggableMacro.OSLogMessage) -> Void
```

### What it generates

```swift
#log(.debug, "Processing \(value, privacy: .public) with \(secret, privacy: .private)")
```

expands to:

```swift
{
    if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
        Self.logger.debug("Processing \(value, privacy: .public) with \(secret, privacy: .private)")
    } else {
        os_log(.debug, log: Self._osLog,
               "Processing %{public}@ with %{private}@",
               "\(value)", "\(secret)")
    }
}()
```

The expansion is wrapped in an immediately-invoked closure so it remains a single expression and can be used anywhere a `Void` expression is valid.

### Log level mapping

The level passed to `#log` maps differently to the modern and legacy APIs:

| `#log` level | `os.Logger` method (macOS 11+) | `os_log` `OSLogType` (legacy) |
|--------------|-------------------------------|-------------------------------|
| `.debug`     | `debug(_:)`                   | `.debug`                      |
| `.info`      | `info(_:)`                    | `.info`                       |
| `.default`   | `notice(_:)`                  | `.default`                    |
| `.error`     | `error(_:)`                   | `.error`                      |
| `.fault`     | `critical(_:)`                | `.fault`                      |

Note the modern-API names: `.default` becomes `notice(_:)`, and `.fault` becomes `critical(_:)`. Apple chose those modern names to match the OS log severity model; the macro hides the discrepancy.

### Privacy

Privacy values accepted in interpolation:

| Privacy | Modern API | Legacy `os_log` format specifier |
|---------|------------|----------------------------------|
| `.public`                     | `\(x, privacy: .public)`     | `%{public}@`  |
| `.private` / `.private(mask:)`| `\(x, privacy: .private)`    | `%{private}@` |
| `.sensitive` / `.sensitive(mask:)` | `\(x, privacy: .sensitive)` | `%{private}@` (legacy has no `sensitive`) |
| `.auto` / `.auto(mask:)`      | `\(x, privacy: .auto)`       | `%{public}@` (defaults to visible) |
| _omitted_                     | `\(x)` (uses Apple's `auto` default) | `%{public}@` |

The legacy fallback intentionally errs on the side of **visibility**: if you don't specify privacy, the value is logged publicly. This matches what `os_log` would do without an explicit privacy qualifier and avoids accidentally redacting useful diagnostics on older OS versions. If you need a value to remain private on every supported OS, annotate it explicitly with `.private` or `.sensitive`.

### Format and alignment

Interpolation supports the same `format:` and `align:` parameters as `OSLogMessage`:

```swift
#log(.info, "id: \(id, format: .hex, privacy: .public)")
#log(.info, "name: \(s, align: .left(columns: 20), privacy: .public)")
#log(.debug, "val: \(n, format: .decimal(minDigits: 4), align: .right(columns: 10), privacy: .private)")
#log(.info, "pi: \(pi, format: .fixed(precision: 2))")
```

On macOS 11+ these parameters are passed through to `os.Logger` verbatim. On the legacy fallback, formatting and alignment are stripped — every interpolation becomes a `%{privacy}@` specifier with the value coerced via `"\(value)"`. This is a deliberate trade-off: legacy `os_log` does not support the modern interpolation surface area, so the macro produces a correct, simple format string instead of attempting to translate every option.

### Percent literals

A literal `%` in the format string is automatically escaped to `%%` in the legacy branch so that `os_log` does not interpret it as a format specifier. The modern branch is unaffected.

```swift
#log(.info, "100% done: \(x)")
// legacy: os_log(.info, log: Self._osLog, "100%% done: %{public}@", "\(x)")
```

## Critical Constraints

1. **`#log` must be inside a type annotated with `@Loggable`** (or one that otherwise provides `Self.logger` and `Self._osLog` with matching shapes). The expansion references `Self.logger` and `Self._osLog` — using it from a free function or top-level script will fail to compile.
2. **`subsystem:` and `category:` arguments must be string literals.** They are typed as `StaticString?` and the macro extracts the source via `StringLiteralExprSyntax`. Passing a `let constant: String = "..."` will not compile.
3. **`accessLevel` is positional, not labeled.** Write `@Loggable(.public)`, not `@Loggable(accessLevel: .public)`. The other two parameters are labeled.
4. **Both macros require `canImport(os)`.** They are unavailable on Linux/Windows. Wrap cross-platform call sites in `#if canImport(os)`.
5. **Generated members are `nonisolated`.** This is intentional — it lets you log from any isolation domain. Do not try to redeclare `logger` with a different isolation; the synthesized one is final.
6. **`@Loggable` does not add protocol conformance.** It directly synthesizes members. There is a separate `Loggable` protocol in `FoundationToolbox/Loggable.swift`, but it exists for *manual* opt-in (e.g., extending a type you cannot annotate). The macro path and the protocol path are independent.

## Common Mistakes

| Mistake | What happens | Fix |
|---------|--------------|-----|
| `#log(.info, "...")` in a free function | Compile error: `Self` is not in scope, or `logger`/`_osLog` not found. | Move the call into a method on a `@Loggable` type, or annotate the enclosing type with `@Loggable`. |
| `@Loggable(subsystem: someConstant)` | Compile error: macro expects a string literal. | Inline the literal: `@Loggable(subsystem: "com.acme.app")`. |
| `@Loggable(accessLevel: .public)` | Compile error: unknown argument label. | Drop the label: `@Loggable(.public)`. |
| Expecting `.sensitive` to redact on iOS 13 | The legacy `os_log` API has no `sensitive`; the macro maps it to `%{private}@`. | If you truly need redaction on iOS 13, that is what you get — just be aware the wire-format collapses to `private`. |
| Logger doesn't appear in Console for the right subsystem | The default subsystem falls back to the type name when `bundleIdentifier` is `nil` (e.g., command-line tool, unit test). | Pass an explicit `subsystem:` argument. |
| Mixing `import os` and `import FoundationToolbox` and getting `Logger` ambiguity | Both modules expose `Logger`-related symbols; the macro emits fully-qualified `os.Logger` to avoid this. Your own code may still need disambiguation. | Use `os.Logger` explicitly when you write hand-rolled code beside the macros. |
| Calling `#log` inside a closure captured by an `@escaping` parameter, expecting it to capture nothing | Each `#log` expansion still references `Self.logger`. In a class, that captures `self` strongly via the metatype. The cost is the same as referring to a static member. | Not usually a problem; if you need to avoid it, hoist the logger into a local before the closure: `let logger = Self.logger` and call `logger.debug(...)` directly. |

## Worked Example

```swift
import Foundation
import os.log
import FoundationToolbox

@Loggable(.internal, subsystem: "com.acme.networking", category: "API")
final class APIClient {
    func send(_ request: URLRequest) async throws -> Data {
        #log(.info, "Sending \(request.httpMethod ?? "GET", privacy: .public) to \(request.url?.absoluteString ?? "", privacy: .private)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            #log(.debug, "Got \(data.count, format: .byteCount, privacy: .public) bytes from \((response as? HTTPURLResponse)?.statusCode ?? -1, privacy: .public)")
            return data
        } catch {
            #log(.error, "Request failed: \(error)")
            throw error
        }
    }
}
```

Decisions made above:
- `.internal` access level so other types in the same module can read `APIClient.logger` (e.g., for testing) but consumers of the framework cannot.
- Explicit `subsystem` so the logger ends up under `com.acme.networking` regardless of which app embeds the framework.
- `category: "API"` instead of the auto-derived `"APIClient"` — categories are the granularity used in `log stream --predicate` and Console.app filtering, so a stable, human-readable name is more useful than the type name.
- `.private` for the URL because URLs frequently contain query parameters with PII.
- `.public` for HTTP method and status code because they are operational data with no privacy concern.
- `.byteCount` format on the response size for human-readable Console output.
- Plain `\(error)` for the error — `OSLogMessage` has an `Error` overload, and the legacy fallback will `String`-coerce it.

## Reference: source files

- `Sources/FoundationToolbox/Macros/LoggableMacro.swift` — macro declaration and doc comment for `@Loggable`.
- `Sources/FoundationToolbox/Macros/LogMacro.swift` — macro declaration and doc comment for `#log`, plus the `LoggableMacro` namespace types (`OSLogType`, `OSLogPrivacy`, `OSLogMessage`, etc.) that exist purely to give IDE autocomplete in interpolation positions.
- `Sources/FoundationToolboxMacros/LoggableMacro.swift` — implementation of the member macro.
- `Sources/FoundationToolboxMacros/LogMacro.swift` — implementation of the expression macro, including the legacy-format builder and privacy-name mapping.
- `Sources/FoundationToolbox/Loggable.swift` — the (separate, optional) `Loggable` protocol for manual opt-in.
- `Tests/FoundationToolboxMacroTests/LoggingMacroTests.swift` — golden expansion tests covering every access level, every type kind, every level, every privacy variant, mask variants, format/align passthrough, and percent escaping. Read these to confirm exact expansion shape before changing call sites.
