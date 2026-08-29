// Also brings in `OSToolbox` and, through it, `FrameworkToolbox` and `os` —
// which is why `@Loggable`, `#log`, `@Mutex`, `AccessLevel`, and `os.Logger`
// all keep resolving from a bare `import FoundationToolbox`.
@_exported import SwiftStdlibToolbox

// `#URL` and `#Selector` expand to `URL(string:)!` and `NSSelectorFromString(_:)`
// — both Foundation. Without this line a caller who writes only
// `import FoundationToolbox` gets errors pointing at generated code their source
// never mentions, which is the exact defect class already fixed once for `#log`
// (`fix(OSToolbox): drop #log's hidden Foundation dependency`) and written up in
// `CLAUDE.md`. `#Selector` fails the plain way, `cannot find
// 'NSSelectorFromString' in scope`. `#URL` fails a far more confusing way: with
// Foundation absent, the `URL` in the expansion resolves to *this module's own
// `URL` macro*, so the compiler reports `expansion of macro 'URL' requires
// leading '#'` — an error about the wrong `URL` entirely.
//
// Re-exporting is the right fix here rather than rewriting the expansions the
// way `#log` was rewritten: this target's whole purpose is Foundation, its
// public API vends `URL` and `Selector` directly, and under SE-0444
// `MemberImportVisibility` a caller would need the import to touch those return
// values anyway. `Sources/FoundationToolboxSoleImportClient/` pins it.
#if canImport(Foundation)
@_exported import Foundation
#endif

#if canImport(Combine)
@_exported import Combine
#endif
