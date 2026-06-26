#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Declares the hook struct (or class) as a per-instance ISA-swizzling
/// installer for `baseClass`, identified by `suffix` in the dynamic-subclass
/// cache.
///
/// Optional `adopts:` lists Objective-C protocols the dynamic subclass should
/// declare conformance to via `class_addProtocol`. The same protocols are used
/// to resolve type encodings for hook methods that aren't declared on
/// `baseClass` itself (typical for AppKit informal protocol methods like
/// `NSDraggingDestination` or `NSSpringLoadingDestination`).
///
/// Methods to install as ObjC overrides **must** be tagged with
/// `@DynamicSubclassOverride`. Untagged methods are treated as plain Swift
/// helpers and are not registered against the dynamic subclass — this avoids
/// the previous footgun where a `private func helper()` would silently swizzle
/// any same-named selector on the base class.
///
/// Generated members:
/// 1. `let base: BaseClass` (the swizzled instance for one invocation) and the
///    matching memberwise `init`.
/// 2. Static helpers `install(on:)`, `uninstall(from:)`, `dynamicSubclass(for:)`
///    and the per-class `installOverridesIfNeeded(on:)` registry. `install` /
///    `uninstall` are **ref-counted** — N installs require N uninstalls to
///    fully restore the ISA.
/// 3. For every `@DynamicSubclassOverride`-tagged instance method, a
///    `@convention(block)` bridge that wraps the method into an Objective-C IMP
///    block, plus a descriptor entry in `installOverridesIfNeeded(on:)`. The
///    selector is resolved from the optional explicit string argument on the
///    override attribute, otherwise derived from the Swift method name +
///    parameter labels (e.g. `springLoadingActivated(_:draggingInfo:)` →
///    `springLoadingActivated:draggingInfo:`). First-parameter labels other
///    than `_` are diagnosed: pass an explicit selector to the override
///    attribute when the Swift label needs preserving.
@attached(member, names: named(base), named(init), named(install), named(uninstall), named(dynamicSubclass), named(installOverridesIfNeeded))
public macro DynamicSubclassHook<BaseClass: NSObject>(
    of baseClass: BaseClass.Type,
    prefix: String = "",
    suffix: String = "",
    adopts adoptedProtocols: [Any.Type] = []
) = #externalMacro(
    module: "ObjCRuntimeToolboxMacros",
    type: "DynamicSubclassHookMacro"
)

/// Marks a method on a `@DynamicSubclassHook` container as an override to
/// install against the dynamic subclass.
///
/// The macro rewrites the method body, injecting two typed local helpers:
///
/// * `callSuper(args...) -> Ret` — dispatches unconditionally to the original
///   class's IMP. Traps if the original class doesn't implement the selector.
///   Use this for methods that are guaranteed to exist on the base class.
///
/// * `callSuperIfImplemented(args...)` (void) /
///   `callSuperIfImplemented(default:_:)` (returning) — dispatches only when
///   the original class actually implements the selector. Use this for
///   methods listed in `adopts:` informal protocols that the base class may
///   not implement.
///
/// `explicitSelector` overrides the auto-derived selector string. Use it when
/// the Swift signature can't naturally produce the ObjC selector you need —
/// e.g. when the first parameter has a non-`_` label so the natural derivation
/// (`format(message:)` → `format:`... or `formatmessage:`) wouldn't match the
/// real ObjC `format:message:` / Swift-bridged `formatWithMessage:` selector.
@attached(body)
public macro DynamicSubclassOverride(_ explicitSelector: String? = nil) = #externalMacro(
    module: "ObjCRuntimeToolboxMacros",
    type: "DynamicSubclassOverrideMacro"
)

#endif
