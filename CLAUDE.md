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

FrameworkToolbox is a Swift Package (Swift 6.1, language mode Swift 5) providing layered libraries of utilities and Swift macros:

**Dependency chain:** `FrameworkToolbox` <- `OSToolbox` <- `SwiftStdlibToolbox` <- `FoundationToolbox`

`CoreFoundationToolbox` depends on `FrameworkToolbox`; `ObjCRuntimeToolbox` depends on `OSToolbox`.

| Library | Purpose |
|---------|---------|
| `FrameworkToolbox` | Core "box" pattern (`FrameworkToolbox<Base>`) with `@dynamicMemberLookup` for namespaced extensions via `FrameworkToolboxCompatible` protocol. Also the single definition of `AccessLevel` |
| `OSToolbox` | Everything layered directly on Apple's `os` module: `Mutex`, `WeakBox`, and the macros `@Mutex`, `@OSAllocatedUnfairLock`, `@Loggable`, `#log`. Depends on `os` and the stdlib only — no Foundation anywhere, which is why `@Loggable`'s default subsystem is the type name rather than a bundle identifier |
| `SwiftStdlibToolbox` | Swift stdlib extensions + macros (`@Equatable`, `@AssociatedValue`, `@CaseCheckable`, `@AvailableNonMutating`, `@AvailableMutating`, `@DyldInterpose`, `@DyldDynamicInterpose`, `@AddAsync`, `@AddAsyncAllMembers`, `@AddCompletionHandler`) |
| `FoundationToolbox` | Foundation extensions + macros (`#url`, `#selector`-style, `@Keychain`, `@UserDefault`), `NSLock`-based wrappers, shared `Storage` layer (Keychain + `UserDefaults`) |
| `CoreFoundationToolbox` | CoreFoundation wrappers, toll-free bridging, Mach error types (adapted from SwiftCF) |
| `ObjCRuntimeToolbox` | Objective-C runtime: method hooks, isa-swizzling (`DynamicSubclass`), runtime proxies, and `DynamicObject`/`ObjC` for calling classes with no header. Built as a `.dynamic` product so its process-wide runtime state stays a single copy |

`PointerAuthenticationSupport` is a C target backing `@DyldDynamicInterpose`, not a library product.

**Re-export chain — important when moving code between these targets.** `OSToolbox` re-exports `FrameworkToolbox` and `os`; `SwiftStdlibToolbox` re-exports `OSToolbox`; `FoundationToolbox` re-exports `SwiftStdlibToolbox` and `Combine`. That is why `import FoundationToolbox` alone resolves `@Mutex`, `@Loggable`, `AccessLevel`, and `os.Logger`. `@_exported import` carries macro declarations *and* their plugins across transitive dependencies, so a macro can be moved down a layer without breaking any existing call site — see `Documentations/Specs/2026-08-06-ostoolbox-extraction-design.md`.

## Architecture

### Macro System

Each library has a corresponding macro target (`*Macros`). A shared `MacroToolbox` target provides reusable protocols for lock-style macros (`LockMacroProtocol`, `LockPropertyParser`).

Macro targets depend on `swift-syntax` (509.1.0..<604.0.0). Each macro plugin is a `CompilerPlugin` entry point registering its macros.

Executable client targets (`*Client`) exist for manual macro expansion testing.

### Key Patterns

- **Box pattern:** `FrameworkToolboxCompatible` conformance gives any type a `.box` accessor returning `FrameworkToolbox<Self>`, enabling namespaced extensions without polluting the type's API surface.
- **Lock macros:** `@Mutex`, `@OSAllocatedUnfairLock` share logic via `LockMacroProtocol` in `MacroToolbox`. They generate a backing stored property and computed accessors with lock/unlock around access.
- **Available storage macros:** `@AvailableNonMutating` and `@AvailableMutating` generate `Any?` backing storage plus lazy accessors for `@available`-gated properties whose storage cannot mention the gated type directly. The mutating variant also emits a setter.
- **Logging:** `@Loggable` generates `category`/`subsystem`/`_osLog`/`logger` properties. `#log` emits version-checked code that uses `os.Logger` on macOS 11+ or falls back to the legacy `os_log` API with per-segment privacy support. `@Loggable` also always generates `logger(for:)`/`_osLog(for:)` accessors taking the library `LogCategory` struct (`OSToolbox/LogCategory.swift`), cached per subsystem/category pair in `Loggable.swift`. Users declare categories as static members (`extension LogCategory { static let network = LogCategory("network") }`, the `Notification.Name` pattern) and select one per call site via `#log(.debug, category: .network, ...)` — the macro transplants the category expression verbatim into the expansion, so leading-dot references get real autocomplete and call-site type checking.
- **Async bridging macros:** `@AddAsync` generates an `async` overload of a completion-handler function; `@AddCompletionHandler` generates the reverse; `@AddAsyncAllMembers` applies `@AddAsync` to every member of a type. `@AddAsync` and `@AddAsyncAllMembers` share `AddAsyncMacroCore`. All three are raw `swift-syntax`; the signature-rewriting helpers they need (`withAsyncModifier`/`withThrowsModifier`/`withParameters`/`withReturnType`/`withBody`/`withAttributes`, `asPassthroughArguments`, and the `isVoid` / `Result<Success, Failure>` type checks) live in `SwiftStdlibToolboxMacros/AsyncBridgingSupport.swift`.
- **Interposing macros:** `@DyldInterpose` and `@DyldDynamicInterpose` expand to the same `(replacement, replacee)` tuple of `@convention(c)` pointers — dyld's `dyld_interpose_tuple` layout — and share all parsing, validation and code generation via `SwiftStdlibToolboxMacros/DyldInterposeSupport.swift`; a `DyldInterposeExpansionConfiguration` is the only difference. `@DyldInterpose` targets `__DATA,__interpose`, which dyld consumes at load time (dylib only, irreversible). `@DyldDynamicInterpose` targets a private `__DATA,__dyn_interpose` that dyld ignores; the `DyldDynamicInterpose` runtime (in `SwiftStdlibToolbox/DyldInterpose/`) reads it back via `getsectiondata(#dsohandle, …)` and rewrites symbol pointer slots on demand — this revives `dyld_dynamic_interpose`, an empty function since dyld4 (`rdar://74287303`), by reproducing dyld2's `ImageLoaderMachOClassic::dynamicInterpose`. It works from a main executable, is revertible, and only reaches `S_NON_LAZY_SYMBOL_POINTERS` / `S_LAZY_SYMBOL_POINTERS` slots. The C target `PointerAuthenticationSupport` supplies the arm64e strip/sign intrinsics Swift cannot spell, and is a no-op elsewhere. Design and measured limits: `Documentations/Specs/2026-08-06-dyld-dynamic-interpose-design.md`.
- **Dynamic invocation:** `ObjCRuntimeToolbox/DynamicInvocation/` provides `DynamicObject` (aliased `ObjC`) for calling classes and methods that have no header, via `@dynamicMemberLookup` + `@dynamicCallable` over `NSInvocation`. Adapted from [mhdhejazi/Dynamic](https://github.com/mhdhejazi/Dynamic) under Apache 2.0 (`LICENSES/Dynamic-LICENSE`). Two rules matter when editing it: every `unsafeBitCast` to a `@convention(c)` signature lives in `NSInvocationBridge.swift` so the signatures can be reviewed as a set, and an object return must be spelled `AnyObject?` — `Any?` compiles fine and corrupts memory, because it is a 32-byte existential container rather than an `id`-sized pointer. `DynamicObject` and `RuntimeInvocation` both carry `@Loggable(subsystem: "ObjCRuntimeToolbox", category: "DynamicInvocation")` — the same pair on purpose, so one `log stream` predicate covers the whole path. See `Documentations/Specs/2026-08-06-dynamic-invocation-design.md`.
- **`@Loggable` on a `@dynamicMemberLookup` type is safe** (verified, not assumed). `@Loggable` emits its members `private`, and private members are excluded from the member lookup that dynamic member lookup falls back from — so `logger`/`_osLog`/`subsystem`/`category` stay forwardable to Objective-C from outside the type, while `#log` still resolves `Self.logger` inside it. What *does* shadow is any member visible to the caller: `public` members, and protocol-extension members (statically dispatched, so the compiler binds them before dynamic lookup gets a chance). Adding a protocol layer does not avoid this — visibility is what decides, not where the member comes from.
- **`#log` inside an instance method needs explicit `self.`** on any interpolated property. The macro expands to an immediately-invoked closure, so `\(debugDescription)` fails to compile while `\(self.debugDescription)` works.
- **A macro must not expand to code naming a module the caller may not have imported.** `@Loggable`'s default subsystem used to expand to `Bundle.main.bundleIdentifier ?? "…"`, which fails with `cannot find 'Bundle' in scope` in any file that skipped `import Foundation` — and the error points at generated code the source never mentions. Wrapping the *generated* code in `#if canImport(Foundation)` does not fix it: `canImport` reports whether a module could be imported (always true for Foundation on Apple platforms), not whether this file imported it. Either drop the dependency (what `@Loggable` did — the default subsystem is now just the type name) or move it into a runtime helper inside the macro's own module. `Sources/OSToolboxClient/LoggableWithoutFoundation.swift` guards this at compile time.
- **`canImport(X)` is not a platform guard.** It answers "can this module be imported", not "does this symbol exist here", and Apple's umbrella frameworks are routinely importable-but-unavailable on derived platforms: `canImport(QuartzCore)` is true on watchOS where `CATransform3D` is unavailable, and `canImport(AppKit)` is true under Mac Catalyst where nearly all of AppKit is. Guard those with `os(...)` / `!os(...)`. Since `swift build` only covers macOS and these regressions are compile-time (no unit test can catch them), build every declared platform after touching a guard — the loop is in `Documentations/Specs/2026-08-06-dynamic-invocation-design.md`.
- **`os_log` treats string interpolations as private by default**, so an unannotated trace reads `call [<private> <private>]` and is worthless. The convention in `DynamicInvocation/` is to mark structural values (class names, selectors, member names) `privacy: .public` and leave payloads (wrapped-object descriptions, argument and return values) private, since those can carry arbitrary user data.
- **Storage layer:** `FoundationToolbox/Storage/` holds two parallel codec protocols shared across storage backends. `DataStorable` (used by Keychain) encodes `Self ↔ Data`; `PlistStorable` (used by `UserDefaults`) encodes `Self ↔ Any` (plist-compatible objects). The same primitive set — `String`, `Data`, `Bool`, the integer/floating-point families, `Date`, `URL`, conditional `Optional<Wrapped>` — conforms to both. `DataCodableStorable` / `PlistCodableStorable` are markers that let any `Codable` type opt into JSON-backed storage. A shared internal `_AnyOptionalStorableValue` hook detects `nil` writes so backends dispatch to their "delete" path.
- **Keychain macro:** `@Keychain(key:service:synchronizable:accessible:)` is an accessor + peer macro that turns a stored property into a Keychain-backed one. The generated peers are `private let _<name> = KeychainStorage<Value>(...)` and `var $<name>: some Publisher<Value, Never>` (opaque type hides the underlying `PassthroughSubject`'s `.send`). The `KeychainStorage` runtime (in `FoundationToolbox/Keychain/`) wraps `SecItem*` directly — no third-party Keychain dependency. `KeychainStorable` / `KeychainCodableStorable` are typealiases of the shared `DataStorable` / `DataCodableStorable`.
- **UserDefault macro:** `@UserDefault(key:suite:)` mirrors `@Keychain` but persists to `UserDefaults`. Generated peers are `private let _<name> = UserDefaultStorage<Value>(...)` plus `var $<name>: some Publisher<Value, Never>`. The `UserDefaultStorage` runtime (in `FoundationToolbox/UserDefault/`) uses `set(_:forKey:)` / `object(forKey:)` for plist-native primitives, calls `removeObject(forKey:)` when an `Optional` value is written as `nil`, and subscribes to `UserDefaults.didChangeNotification` so the publisher also reflects writes made externally (system Settings.app, another piece of code in the process, another process targeting the same suite). A `suppressNextNotification` flag avoids double-publishing the value written through `set(_:)`. `UserDefaultStorable` / `UserDefaultCodableStorable` are typealiases of the shared `PlistStorable` / `PlistCodableStorable`.

### Platforms

iOS 13+, macOS 10.15+, watchOS 6+, tvOS 13+, macCatalyst 13+, visionOS 1+

### Dependencies

- `swift-syntax` — macro implementation
- `swift-macro-testing` (pointfree, test-only) — snapshot assertions for macro expansions
