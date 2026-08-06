#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Declares a struct or class as the container for method replacements against
/// a class that is only known by name at runtime.
///
/// ## Overview
///
/// Attach `@RuntimeClassHook("SomeClassName")` to a `struct` or `class` and
/// write the replacements inside it as ordinary Swift methods tagged with
/// ``RuntimeMethodReplacement(_:typeEncoding:isClassMethod:)``. The macro
/// derives the selector from each method's Swift signature, derives the
/// Objective-C type encoding from its Swift types, builds the
/// `@convention(block)` trampoline, and assembles the descriptor batch.
///
/// ## Why the derived encoding matters
///
/// Replacing an implementation requires the replacement's signature and the
/// method's real ABI to agree. Written by hand those are two independent
/// strings that nothing compares — typing `Int` where the method takes `Bool`
/// passes every check and then corrupts registers when the host calls in.
///
/// Deriving the encoding from the same Swift signature that becomes the block
/// makes disagreement impossible, which turns the install-time comparison
/// against the live class into a real assertion about the host rather than a
/// check of one guess against another. When an operating-system update changes
/// a signature, the batch is refused and logged; nothing is replaced.
///
/// ## Relationship to `@DynamicSubclassHook`
///
/// ``DynamicSubclassHook(of:prefix:suffix:adopts:)`` swizzles one instance's
/// `isa` and is the better tool whenever you hold the instances you want to
/// affect and the class exists at compile time. Reach for this macro when the
/// class has no header, when the instances are created by code you do not
/// control, or when the replacement has to apply to instances that do not exist
/// yet. The trade is bluntness: the change is process-wide and there is no
/// uninstall.
///
/// ## Generated members
///
/// 1. **Storage** — `let host: AnyObject` (the receiver) and
///    `let originalImplementation: IMP` (the implementation this replacement
///    displaced), plus the matching initialiser. The container is constructed
///    per invocation around the receiver, so a replacement addresses the host
///    object through `self.host`.
/// 2. **`descriptors()`** — the batch, one
///    ``RuntimeMethodHook/Descriptor`` per tagged method.
/// 3. **`install()`** — `throws`; hands `descriptors()` to
///    ``RuntimeMethodHook/installAtomically(_:)``. Compose several containers
///    into one atomic batch by concatenating their `descriptors()` instead.
///
/// ## Selector derivation
///
/// Same rules as ``DynamicSubclassHook(of:prefix:suffix:adopts:)``: zero
/// parameters give `<methodName>`; N parameters with `_` as the first label
/// give `<methodName>:<label2>:…`. A non-`_` first label is diagnosed, because
/// Swift's `@objc` bridging would have produced
/// `<methodName>With<CapitalizedLabel>:` and this derivation would not match —
/// pass an explicit selector in that case.
///
/// ## Example
///
/// ```swift
/// @RuntimeClassHook("Tile")
/// struct TileHooks {
///     @RuntimeMethodReplacement
///     func setImage(_ image: AnyObject?, preferredGlassBackgroundStyle: Int) {
///         guard let substitute = IconTable.replacement(for: host) else {
///             callOriginal(image, preferredGlassBackgroundStyle)
///             return
///         }
///         callOriginal(substitute, preferredGlassBackgroundStyle)
///     }
/// }
///
/// try TileHooks.install()
/// ```
///
/// - Parameter className: Name of the Objective-C class to replace methods on,
///   resolved with `objc_getClass` at install time.
@attached(
    member,
    names: named(host), named(originalImplementation), named(init),
    named(descriptors), named(install), named(runtimeClassName)
)
public macro RuntimeClassHook(_ className: String) = #externalMacro(
    module: "ObjCRuntimeToolboxMacros",
    type: "RuntimeClassHookMacro"
)

/// Marks a method on a ``RuntimeClassHook(_:)`` container as a replacement to
/// install, and injects a typed `callOriginal` helper into its body.
///
/// ## What it does
///
/// 1. **Opt-in marker** — the container macro only registers methods carrying
///    this attribute. Untagged methods stay ordinary Swift helpers, so a
///    `private func helper()` cannot accidentally claim a same-named selector
///    on the host class.
///
/// 2. **Body rewriter** — prepends a local `callOriginal(...)` whose signature
///    mirrors the method exactly. It dispatches through the implementation this
///    replacement displaced, cast to a `@convention(c)` function type over the
///    same types the encoding was derived from.
///
/// Calling `callOriginal` is how a replacement forwards to the host's own
/// behaviour. It goes straight to the saved implementation rather than through
/// the class's method table, so it cannot re-enter the replacement.
///
/// ## Example
///
/// ```swift
/// @RuntimeMethodReplacement
/// func setReplacementAppImage(_ image: AnyObject?, usesIconServices: Bool) {
///     guard !IconTable.blocks(host) else { return }   // drop it entirely
///     callOriginal(image, usesIconServices)
/// }
/// ```
///
/// ## Compile-time diagnostics
///
/// `throws`, `async`, `mutating`, `@MainActor`, actor-isolated methods, and
/// parameter or return types that are not Objective-C representable (`inout`,
/// multi-element tuples, bare Swift closures) are all rejected, as is a non-`_`
/// first parameter label without an explicit selector.
///
/// - Parameters:
///   - explicitSelector: Objective-C selector to use instead of the one derived
///     from the Swift signature. Pass when the signature cannot naturally
///     produce the selector you need.
///   - typeEncoding: Escape hatch overriding the derived type encoding. Needed
///     only for signatures the derivation cannot express — a struct parameter
///     outside the built-in table, for instance. Read the real value with
///     ``RuntimeMethodInspector/typeEncoding(forClassNamed:selector:isInstanceMethod:)``
///     rather than deriving it from a decompiler's rendering.
///   - isClassMethod: Replace the class method rather than the instance method.
///     `host` is then the class object.
@attached(body)
public macro RuntimeMethodReplacement(
    _ explicitSelector: String? = nil,
    typeEncoding: String? = nil,
    isClassMethod: Bool = false
) = #externalMacro(
    module: "ObjCRuntimeToolboxMacros",
    type: "RuntimeMethodReplacementMacro"
)

#endif
