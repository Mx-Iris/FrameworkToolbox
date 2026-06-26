#if canImport(ObjectiveC)
import ObjectiveC

/// Declares the hook struct as a per-instance ISA-swizzling installer for
/// `baseClass`, identified by `suffix` in the dynamic-subclass cache.
///
/// Optional `adopts:` lists Objective-C protocols the dynamic subclass should
/// declare conformance to via `class_addProtocol`. The same protocols are used
/// to resolve type encodings for hook methods that aren't declared on
/// `baseClass` itself (typical for AppKit informal protocol methods like
/// `NSDraggingDestination` or `NSSpringLoadingDestination`).
///
/// Generated members:
/// 1. `let base: BaseClass` (the swizzled instance for one invocation) and the
///    matching memberwise `init`.
/// 2. Static helpers `install(on:)`, `uninstall(from:)`, `dynamicSubclass(for:)`
///    and the per-class `installOverridesIfNeeded(on:)` registry.
/// 3. For every instance method declared on the struct, a `@convention(block)`
///    bridge that wraps the method into an Objective-C IMP block, plus a
///    descriptor entry in `installOverridesIfNeeded(on:)`. The block resolves
///    the selector from the Swift method name + parameter labels (e.g.
///    `springLoadingActivated(_:draggingInfo:)` →
///    `springLoadingActivated:draggingInfo:`).
/// 4. A rewritten body for each instance method that prepends typed local
///    `callSuper(...)` and `callSuperIfImplemented(...)` helpers closing over
///    `base` and the resolved selector. Users write `callSuper(args...)` or
///    `callSuperIfImplemented(default: ..., args...)` and the helpers dispatch
///    to the original class's IMP through `unsafeBitCast`.
@attached(member, names: named(base), named(init), named(install), named(uninstall), named(dynamicSubclass), named(installOverridesIfNeeded))
@attached(memberAttribute)
public macro DynamicSubclassHook<BaseClass: AnyObject>(
    of baseClass: BaseClass.Type,
    suffix: String,
    adopts adoptedProtocols: [Any.Type] = []
) = #externalMacro(
    module: "ObjCRuntimeToolboxMacros",
    type: "DynamicSubclassHookMacro"
)

/// Internal body macro — applied automatically by `@DynamicSubclassHook` to
/// every instance method on the hook struct. Users do not write this attribute
/// directly.
@attached(body)
public macro _DynamicSubclassMethodBody() = #externalMacro(
    module: "ObjCRuntimeToolboxMacros",
    type: "DynamicSubclassMethodBodyMacro"
)

#endif
