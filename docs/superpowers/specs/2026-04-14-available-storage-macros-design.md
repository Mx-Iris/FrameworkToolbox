# Available Storage Macros Design

## Goal

Add property macros that make it practical to expose properties gated by Swift's `@available` attribute when the backing storage cannot itself mention the gated type. The macro-generated storage must use `Any?`, while the public property keeps the caller's explicit type and availability attributes.

## API

The feature adds two attached property macros to `SwiftStdlibToolbox`:

```swift
@AvailableNonMutating(AppleMusicLyrics.WindowController())
@available(macOS 15, *)
private var appleMusicLyricsWindowController: AppleMusicLyrics.WindowController

@AvailableMutating(AppleMusicLyrics.WindowController())
@available(macOS 15, *)
private var editableWindowController: AppleMusicLyrics.WindowController
```

`@AvailableNonMutating` generates a lazy getter only. `@AvailableMutating` generates the same lazy getter plus a setter that stores the assigned value in the backing storage.

Both macros require:

- attachment to a single variable declaration;
- an explicit type annotation;
- exactly one default value expression argument;
- no existing accessor block.

## Expansion Shape

For:

```swift
@AvailableNonMutating(AppleMusicLyrics.WindowController())
@available(macOS 15, *)
private var appleMusicLyricsWindowController: AppleMusicLyrics.WindowController
```

the macro expands to:

```swift
@available(macOS 15, *)
private var appleMusicLyricsWindowController: AppleMusicLyrics.WindowController {
    get {
        if let existingValue = appleMusicLyricsWindowControllerStorage as? AppleMusicLyrics.WindowController {
            return existingValue
        }
        let defaultValue = AppleMusicLyrics.WindowController()
        appleMusicLyricsWindowControllerStorage = defaultValue
        return defaultValue
    }
}

private var appleMusicLyricsWindowControllerStorage: Any?
```

`@AvailableMutating` adds:

```swift
set {
    appleMusicLyricsWindowControllerStorage = newValue
}
```

The backing storage name uses the property name plus `Storage`, matching the motivating example and avoiding a gated type in the generated storage.

## Placement

The macros belong in `SwiftStdlibToolbox` and `SwiftStdlibToolboxMacros` because the implementation only needs Swift language primitives: `Any?`, type casts, generated accessors, and peer storage. `FoundationToolbox` already exports `SwiftStdlibToolbox`, so Foundation-facing users can still import `FoundationToolbox` and use the macros.

## Testing

Use macro expansion tests in `SwiftStdlibToolboxMacroTests` with the existing `MacroTesting` style. Cover:

- `@AvailableNonMutating` getter-only expansion;
- `@AvailableMutating` getter and setter expansion;
- `static var` storage generation;
- diagnostics for missing default value argument, missing explicit type, invalid declaration kind, multiple bindings, and existing accessors.

After implementation, verify with a narrow macro test filter first, then run the relevant SwiftPM build or test command according to the repository workflow.
