// `AccessLevel` — the parameter type of `@Loggable` — is defined once, in
// `FrameworkToolbox`. Re-exporting it here means every layer stacked on top of
// this target sees that single definition instead of keeping its own copy, and
// callers writing `import OSToolbox` can still name `AccessLevel` directly.
@_exported import FrameworkToolbox

// `@Loggable` and `#log` expand to code naming `os.Logger`, `OSLog`, and
// `os_log`, so every call site needs `os` in scope. Re-exporting it here means
// annotating a type is enough — no second import to remember, and no expansion
// that fails to compile for a reason the source never mentions.
#if canImport(os)
@_exported import os
#endif
