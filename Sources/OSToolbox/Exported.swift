// `AccessLevel` — the first parameter of `@Loggable` and `@Signpostable` — is
// defined once, in `FrameworkToolbox`. Re-exporting it here means every layer
// stacked on top of this target sees that single definition instead of keeping
// its own copy, and callers writing `import OSToolbox` can still name
// `AccessLevel` directly.
//
// This line is load-bearing, and it is worth being precise about when. Removing
// it does *not* break `@Loggable(.public)` today: Swift resolves a member of an
// already-known type without that type's module being imported, so only a call
// site spelling `AccessLevel` out fails, with `cannot find type 'AccessLevel' in
// scope`. Under SE-0444 `MemberImportVisibility` — an upcoming feature now, the
// default in the Swift 7 language mode — the leading-dot form fails as well:
//
//     error: enum case 'public' is not available due to missing import of
//            defining module 'FrameworkToolbox' [#MemberImportVisibility]
//
// That error lands in the caller's own file and names a module the caller never
// asked for. Both halves verified by building this package with the re-export
// removed, once as-is and once with `MemberImportVisibility` enabled.
@_exported import FrameworkToolbox

// `@Loggable` and `#log` expand to code naming `os.Logger`, `OSLog`, and
// `os_log`, so every call site needs `os` in scope. Re-exporting it here means
// annotating a type is enough — no second import to remember, and no expansion
// that fails to compile for a reason the source never mentions.
#if canImport(os)
@_exported import os
#endif
