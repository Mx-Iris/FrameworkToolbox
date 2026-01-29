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
| `SwiftStdlibToolbox` | Swift stdlib extensions + macros (`@Equatable`, `@AssociatedValue`, `@CaseCheckable`, `@Mutex`) |
| `FoundationToolbox` | Foundation extensions + macros (`@Loggable`, `#log`, `#url`, `@OSAllocatedUnfairLock`), lock wrappers, logging |

## Architecture

### Macro System

Each library has a corresponding macro target (`*Macros`). A shared `MacroToolbox` target provides reusable protocols for lock-style macros (`LockMacroProtocol`, `LockPropertyParser`).

Macro targets depend on `swift-syntax` (509.1.0..<602.0.0). Each macro plugin is a `CompilerPlugin` entry point registering its macros.

Executable client targets (`*Client`) exist for manual macro expansion testing.

### Key Patterns

- **Box pattern:** `FrameworkToolboxCompatible` conformance gives any type a `.box` accessor returning `FrameworkToolbox<Self>`, enabling namespaced extensions without polluting the type's API surface.
- **Lock macros:** `@Mutex`, `@OSAllocatedUnfairLock` share logic via `LockMacroProtocol` in `MacroToolbox`. They generate a backing stored property and computed accessors with lock/unlock around access.
- **Logging:** `@Loggable` generates `logger`/`logCategory`/`logSubsystem` properties. `#log` emits version-checked code that uses `os.Logger` on macOS 11+ or falls back to `swift-log`.

### Platforms

iOS 13+, macOS 10.15+, watchOS 6+, tvOS 13+, macCatalyst 13+, visionOS 1+

### Dependencies

- `swift-syntax` — macro implementation
- `swift-log` — logging fallback for older OS versions
