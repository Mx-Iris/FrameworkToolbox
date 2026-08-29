// This target's public API spells `FrameworkToolbox<…>` out in the open — 59
// declarations do, counting the `extension FrameworkToolbox<CFString>` headers
// and every `allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default`
// default argument. A caller who writes only `import CoreFoundationToolbox` can
// reach `.box` (member lookup finds it through the conformance declared here)
// but cannot name the box type itself, so passing an explicit allocator fails
// with `cannot find 'FrameworkToolbox' in scope`.
//
// Re-exporting also keeps `AccessLevel` and the box pattern resolving from this
// target the way they already do from `OSToolbox` upwards — see the note on the
// matching line in `Sources/OSToolbox/Exported.swift` for why that matters more
// under SE-0444 `MemberImportVisibility`.
@_exported import FrameworkToolbox

// Every type this target extends is a CoreFoundation type, so a caller cannot
// use any of it without `CFString`, `CFArray`, `CFAllocator` and friends in
// scope. Re-exporting spares them a second import that is never optional.
@_exported import CoreFoundation
