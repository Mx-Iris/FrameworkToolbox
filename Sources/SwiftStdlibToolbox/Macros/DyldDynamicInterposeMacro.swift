/// Registers a function as a *dynamic* dyld interposer for another C function:
/// the replacement takes effect when the program asks for it, not when the
/// image is loaded.
///
/// This is the Swift revival of `dyld_dynamic_interpose` from `<mach-o/dyld_priv.h>`.
/// That API still exists, but since dyld4 its body is an unconditional
/// `return` (see `libdyld/libdyldGlue.cpp`, annotated with `rdar://74287303`) —
/// Apple disabled it after it broke Photoshop 2021 on macOS 12. The macro plus
/// ``DyldDynamicInterpose`` reproduce what dyld2's
/// `ImageLoaderMachOClassic::dynamicInterpose` used to do: walk an image's
/// symbol pointer sections and overwrite every slot whose current value is the
/// address of the function being replaced.
///
/// Usage:
/// ```swift
/// import Darwin
/// import SwiftStdlibToolbox
///
/// @DyldDynamicInterpose(puts)
/// func interposedPuts(_ string: UnsafePointer<CChar>?) -> Int32 {
///     fputs("[hooked] ", stdout)
///     // Reaches the real `puts`: the image declaring the interpose is
///     // excluded from rewriting by default, so this call does not recurse.
///     return puts(string)
/// }
///
/// // Take effect at a moment of your choosing…
/// DyldDynamicInterpose.applyAll()
/// // …and undo it later.
/// DyldDynamicInterpose.revertAll()
/// ```
///
/// How it differs from ``DyldInterpose``:
/// - ``DyldInterpose`` writes into `__DATA,__interpose`, which dyld consumes
///   at load time. It only works from a dynamic library and can never be
///   undone.
/// - This macro writes into a private `__DATA,__dyn_interpose` section that
///   dyld ignores. It works from any image — including a main executable —
///   takes effect only when ``DyldDynamicInterpose/applyAll(to:excludingDeclaringImage:declaredIn:)``
///   is called, and can be reverted.
///
/// Requirements (identical to ``DyldInterpose``, because the generated tuple is
/// the same):
/// - The macro must be attached to a top-level function (not a method).
/// - The function must not be generic, `throws`, `async`, or take `inout`
///   parameters; `@convention(c)` function types do not allow those.
/// - The function's signature must be ABI-compatible with the C target.
///
/// Limitations of dynamic interposing — all of them inherent to rewriting
/// pointers after the fact, and spelled out in dyld's own header:
/// - Only indirection slots are rewritten. Direct calls, inlined calls, and
///   function pointers the program already copied elsewhere are unaffected.
/// - Calls *between* shared-cache dylibs are mostly direct branches rather
///   than indirect ones, so interposing a libSystem function realistically
///   only redirects calls made from images you built yourself.
/// - Binaries old enough to still use lazy binding keep the stub binder's
///   address in a `__la_symbol_ptr` slot until the function is first called;
///   such a slot has nothing to match against yet. Binaries using chained
///   fixups — anything targeting macOS 12 / iOS 15 or newer — bind eagerly and
///   are unaffected.
///
/// Notes:
/// - The macro generates code guarded by `#if canImport(Darwin)`; on non-Apple
///   platforms it expands to nothing because interposing is a Mach-O feature.
/// - SE-0492 (`@section` / `@used`) was implemented in Swift 6.3. The macro
///   conditionally uses the underscored spellings (`@_section` / `@_used`) on
///   Swift 6.2 and earlier; on those toolchains the consuming target must opt
///   in via `-enable-experimental-feature SymbolLinkageMarkers`.
@attached(peer, names: prefixed(_dyldDynamicInterpose_))
public macro DyldDynamicInterpose(_ target: Any) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "DyldDynamicInterposeMacro"
)
