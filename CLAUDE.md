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
| `SwiftStdlibToolbox` | Swift stdlib extensions + macros (`@Equatable`, `@AssociatedValue`, `@CaseCheckable`, `@Mutex`, `@AvailableNonMutating`, `@AvailableMutating`, `@DyldInterpose`, `@DyldDynamicInterpose`, `@AddAsync`, `@AddAsyncAllMembers`, `@AddCompletionHandler`) |
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
- **Logging:** `@Loggable` generates `category`/`subsystem`/`_osLog`/`logger` properties. `#log` emits version-checked code that uses `os.Logger` on macOS 11+ or falls back to the legacy `os_log` API with per-segment privacy support. `@Loggable` also always generates `logger(for:)`/`_osLog(for:)` accessors taking the library `LogCategory` struct (`FoundationToolbox/LogCategory.swift`), cached per subsystem/category pair in `Loggable.swift`. Users declare categories as static members (`extension LogCategory { static let network = LogCategory("network") }`, the `Notification.Name` pattern) and select one per call site via `#log(.debug, category: .network, ...)` — the macro transplants the category expression verbatim into the expansion, so leading-dot references get real autocomplete and call-site type checking.
- **Async bridging macros:** `@AddAsync` generates an `async` overload of a completion-handler function; `@AddCompletionHandler` generates the reverse; `@AddAsyncAllMembers` applies `@AddAsync` to every member of a type. `@AddAsync` and `@AddAsyncAllMembers` share `AddAsyncMacroCore`. All three are raw `swift-syntax`; the signature-rewriting helpers they need (`withAsyncModifier`/`withThrowsModifier`/`withParameters`/`withReturnType`/`withBody`/`withAttributes`, `asPassthroughArguments`, and the `isVoid` / `Result<Success, Failure>` type checks) live in `SwiftStdlibToolboxMacros/AsyncBridgingSupport.swift`.
- **Interposing macros:** `@DyldInterpose` and `@DyldDynamicInterpose` expand to the same `(replacement, replacee)` tuple of `@convention(c)` pointers — dyld's `dyld_interpose_tuple` layout — and share all parsing, validation and code generation via `SwiftStdlibToolboxMacros/DyldInterposeSupport.swift`; a `DyldInterposeExpansionConfiguration` is the only difference. `@DyldInterpose` targets `__DATA,__interpose`, which dyld consumes at load time (dylib only, irreversible). `@DyldDynamicInterpose` targets a private `__DATA,__dyn_interpose` that dyld ignores; the `DyldDynamicInterpose` runtime (in `SwiftStdlibToolbox/DyldInterpose/`) reads it back via `getsectiondata(#dsohandle, …)` and rewrites symbol pointer slots on demand — this revives `dyld_dynamic_interpose`, an empty function since dyld4 (`rdar://74287303`), by reproducing dyld2's `ImageLoaderMachOClassic::dynamicInterpose`. It works from a main executable, is revertible, and only reaches `S_NON_LAZY_SYMBOL_POINTERS` / `S_LAZY_SYMBOL_POINTERS` slots. The C target `PointerAuthenticationSupport` supplies the arm64e strip/sign intrinsics Swift cannot spell, and is a no-op elsewhere. Design and measured limits: `Documentations/Specs/2026-08-06-dyld-dynamic-interpose-design.md`.
- **Storage layer:** `FoundationToolbox/Storage/` holds two parallel codec protocols shared across storage backends. `DataStorable` (used by Keychain) encodes `Self ↔ Data`; `PlistStorable` (used by `UserDefaults`) encodes `Self ↔ Any` (plist-compatible objects). The same primitive set — `String`, `Data`, `Bool`, the integer/floating-point families, `Date`, `URL`, conditional `Optional<Wrapped>` — conforms to both. `DataCodableStorable` / `PlistCodableStorable` are markers that let any `Codable` type opt into JSON-backed storage. A shared internal `_AnyOptionalStorableValue` hook detects `nil` writes so backends dispatch to their "delete" path.
- **Keychain macro:** `@Keychain(key:service:synchronizable:accessible:)` is an accessor + peer macro that turns a stored property into a Keychain-backed one. The generated peers are `private let _<name> = KeychainStorage<Value>(...)` and `var $<name>: some Publisher<Value, Never>` (opaque type hides the underlying `PassthroughSubject`'s `.send`). The `KeychainStorage` runtime (in `FoundationToolbox/Keychain/`) wraps `SecItem*` directly — no third-party Keychain dependency. `KeychainStorable` / `KeychainCodableStorable` are typealiases of the shared `DataStorable` / `DataCodableStorable`.
- **UserDefault macro:** `@UserDefault(key:suite:)` mirrors `@Keychain` but persists to `UserDefaults`. Generated peers are `private let _<name> = UserDefaultStorage<Value>(...)` plus `var $<name>: some Publisher<Value, Never>`. The `UserDefaultStorage` runtime (in `FoundationToolbox/UserDefault/`) uses `set(_:forKey:)` / `object(forKey:)` for plist-native primitives, calls `removeObject(forKey:)` when an `Optional` value is written as `nil`, and subscribes to `UserDefaults.didChangeNotification` so the publisher also reflects writes made externally (system Settings.app, another piece of code in the process, another process targeting the same suite). A `suppressNextNotification` flag avoids double-publishing the value written through `set(_:)`. `UserDefaultStorable` / `UserDefaultCodableStorable` are typealiases of the shared `PlistStorable` / `PlistCodableStorable`.

### Platforms

iOS 13+, macOS 10.15+, watchOS 6+, tvOS 13+, macCatalyst 13+, visionOS 1+

### Dependencies

- `swift-syntax` — macro implementation
- `swift-macro-testing` (pointfree, test-only) — snapshot assertions for macro expansions
