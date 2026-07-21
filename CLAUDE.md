# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build the entire package
swift build 2>&1 | xcsift

# Build a specific target
swift build --target FoundationToolbox 2>&1 | xcsift

# Run tests
swift test 2>&1 | xcsift

# Run a specific test
swift test --filter FrameworkToolboxTests 2>&1 | xcsift

# Run a macro client for manual testing
swift run FoundationToolboxClient 2>&1 | xcsift
```

Always pipe `swift build` / `swift test` output through `xcsift`.

## Project Overview

FrameworkToolbox is a Swift Package (Swift 6.1, language mode Swift 5) providing three layered libraries of utilities and Swift macros:

**Dependency chain:** `FrameworkToolbox` <- `SwiftStdlibToolbox` <- `FoundationToolbox`

| Library | Purpose |
|---------|---------|
| `FrameworkToolbox` | Core "box" pattern (`FrameworkToolbox<Base>`) with `@dynamicMemberLookup` for namespaced extensions via `FrameworkToolboxCompatible` protocol |
| `SwiftStdlibToolbox` | Swift stdlib extensions + macros (`@Equatable`, `@AssociatedValue`, `@CaseCheckable`, `@Mutex`, `@AvailableNonMutating`, `@AvailableMutating`, `@DyldInterpose`, `@AddAsync`, `@AddAsyncAllMembers`, `@AddCompletionHandler`) |
| `FoundationToolbox` | Foundation extensions + macros (`@Loggable`, `#log`, `#url`, `@OSAllocatedUnfairLock`, `@Keychain`, `@UserDefault`), lock wrappers, logging, shared `Storage` layer (Keychain + `UserDefaults`) |

## Architecture

### Macro System

Each library has a corresponding macro target (`*Macros`). A shared `MacroToolbox` target provides reusable protocols for lock-style macros (`LockMacroProtocol`, `LockPropertyParser`).

Macro targets depend on `swift-syntax` (509.1.0..<602.0.0). Each macro plugin is a `CompilerPlugin` entry point registering its macros.

Executable client targets (`*Client`) exist for manual macro expansion testing.

### Key Patterns

- **Box pattern:** `FrameworkToolboxCompatible` conformance gives any type a `.box` accessor returning `FrameworkToolbox<Self>`, enabling namespaced extensions without polluting the type's API surface.
- **Lock macros:** `@Mutex`, `@OSAllocatedUnfairLock` share logic via `LockMacroProtocol` in `MacroToolbox`. They generate a backing stored property and computed accessors with lock/unlock around access.
- **Available storage macros:** `@AvailableNonMutating` and `@AvailableMutating` generate `Any?` backing storage plus lazy accessors for `@available`-gated properties whose storage cannot mention the gated type directly. The mutating variant also emits a setter.
- **Logging:** `@Loggable` generates `category`/`subsystem`/`_osLog`/`logger` properties. `#log` emits version-checked code that uses `os.Logger` on macOS 11+ or falls back to the legacy `os_log` API with per-segment privacy support. `@Loggable(categories: "network", "ui")` additionally generates a nested `LogCategory` enum plus `logger(for:)`/`_osLog(for:)` accessors (cached per subsystem/category pair in `Loggable.swift`), selected per call site via `#log(.debug, category: \.network, ...)` — the `category:` parameter is typed as a key path into the `@dynamicMemberLookup` dummy `LoggableMacro.Categories` so any name type-checks, and the macro re-resolves the name against the generated enum at expansion time (concrete types only; not protocols).
- **Async bridging macros:** `@AddAsync` generates an `async` overload of a completion-handler function; `@AddCompletionHandler` generates the reverse; `@AddAsyncAllMembers` applies `@AddAsync` to every member of a type. These are implemented in `SwiftStdlibToolboxMacros` using the `swift-macro-toolkit` (`MacroToolkit`) helpers rather than raw `swift-syntax`.
- **Storage layer:** `FoundationToolbox/Storage/` holds two parallel codec protocols shared across storage backends. `DataStorable` (used by Keychain) encodes `Self ↔ Data`; `PlistStorable` (used by `UserDefaults`) encodes `Self ↔ Any` (plist-compatible objects). The same primitive set — `String`, `Data`, `Bool`, the integer/floating-point families, `Date`, `URL`, conditional `Optional<Wrapped>` — conforms to both. `DataCodableStorable` / `PlistCodableStorable` are markers that let any `Codable` type opt into JSON-backed storage. A shared internal `_AnyOptionalStorableValue` hook detects `nil` writes so backends dispatch to their "delete" path.
- **Keychain macro:** `@Keychain(key:service:synchronizable:accessible:)` is an accessor + peer macro that turns a stored property into a Keychain-backed one. The generated peers are `private let _<name> = KeychainStorage<Value>(...)` and `var $<name>: some Publisher<Value, Never>` (opaque type hides the underlying `PassthroughSubject`'s `.send`). The `KeychainStorage` runtime (in `FoundationToolbox/Keychain/`) wraps `SecItem*` directly — no third-party Keychain dependency. `KeychainStorable` / `KeychainCodableStorable` are typealiases of the shared `DataStorable` / `DataCodableStorable`.
- **UserDefault macro:** `@UserDefault(key:suite:)` mirrors `@Keychain` but persists to `UserDefaults`. Generated peers are `private let _<name> = UserDefaultStorage<Value>(...)` plus `var $<name>: some Publisher<Value, Never>`. The `UserDefaultStorage` runtime (in `FoundationToolbox/UserDefault/`) uses `set(_:forKey:)` / `object(forKey:)` for plist-native primitives, calls `removeObject(forKey:)` when an `Optional` value is written as `nil`, and subscribes to `UserDefaults.didChangeNotification` so the publisher also reflects writes made externally (system Settings.app, another piece of code in the process, another process targeting the same suite). A `suppressNextNotification` flag avoids double-publishing the value written through `set(_:)`. `UserDefaultStorable` / `UserDefaultCodableStorable` are typealiases of the shared `PlistStorable` / `PlistCodableStorable`.

### Platforms

iOS 13+, macOS 10.15+, watchOS 6+, tvOS 13+, macCatalyst 13+, visionOS 1+

### Dependencies

- `swift-syntax` — macro implementation
- `swift-macro-toolkit` (stackotter) — higher-level macro helpers used by `SwiftStdlibToolboxMacros` for the async bridging macros (`@AddAsync`, `@AddAsyncAllMembers`, `@AddCompletionHandler`)
