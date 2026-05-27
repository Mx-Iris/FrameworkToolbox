/// Marks a function as a dyld interposer for another C function, the Swift
/// equivalent of the `DYLD_INTERPOSE` macro from `<mach-o/dyld-interposing.h>`.
///
/// Attach this attribute to a top-level Swift function whose signature exactly
/// matches the C function being replaced. The macro emits a section-placed
/// tuple `(replacement, target)` into `__DATA,__interpose`, which dyld reads
/// when the containing dylib is loaded via `DYLD_INSERT_LIBRARIES` (or linked
/// against a target binary), redirecting all calls to the target through the
/// replacement.
///
/// Usage:
/// ```swift
/// import Darwin
///
/// @DyldInterpose(getpid)
/// func myGetpid() -> pid_t {
///     return 12345
/// }
/// ```
///
/// Requirements:
/// - The macro must be attached to a top-level function (not a method).
/// - The function must not be generic, `throws`, `async`, or take `inout`
///   parameters; `@convention(c)` function types do not allow those.
/// - The function's signature must be ABI-compatible with the C target.
/// - The product must be built as a dynamic library (`.dynamic` product type).
///   dyld only honors the `__interpose` section in dylibs, not in main
///   executables.
///
/// Notes:
/// - The macro generates code guarded by `#if canImport(Darwin)`; on non-Apple
///   platforms it expands to nothing because dyld interposing is a Mach-O
///   feature.
/// - SE-0492 (`@section` / `@used`) was implemented in Swift 6.3. The macro
///   conditionally uses the underscored spellings (`@_section` / `@_used`) on
///   Swift 6.2 and earlier; on those toolchains the consuming target must opt
///   in via `-enable-experimental-feature SymbolLinkageMarkers`.
@attached(peer, names: prefixed(_dyldInterpose_))
public macro DyldInterpose(_ target: Any) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "DyldInterposeMacro"
)
