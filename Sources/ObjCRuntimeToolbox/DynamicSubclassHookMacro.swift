#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Declares a struct or class as the **container** for a per-instance
/// ISA-swizzling hook against `baseClass`.
///
/// ## Overview
///
/// Attach `@DynamicSubclassHook(of: SomeNSObjectSubclass.self, ...)` to a
/// `struct` or `class`. The macro injects the install / uninstall surface,
/// the dynamic-subclass lookup, and the IMP-bridge registry. Hook methods
/// inside the container are written as plain Swift, tagged with
/// ``DynamicSubclassOverride(_:)``; the body macro on each tagged method
/// then injects typed `callSuper(...)` / `callSuperIfImplemented(...)`
/// helpers so the user's code can call super without writing
/// `unsafeBitCast` by hand.
///
/// ## Discriminator
///
/// `prefix` and `suffix` together identify the hook variant inside the
/// process-wide dynamic-subclass cache. At least one must be non-empty
/// (the macro diagnoses an empty discriminator at compile time). The
/// composed runtime class name follows
/// ``DynamicSubclass/getOrCreate(of:prefix:suffix:)``:
///
/// * prefix only: `_ObjCRuntimeToolbox_<prefix>_<baseClassName>`
/// * suffix only: `_ObjCRuntimeToolbox_<baseClassName>_<suffix>`
/// * both:        `_ObjCRuntimeToolbox_<prefix>_<baseClassName>_<suffix>`
///
/// Two hooks that pick the same `(baseClass, prefix, suffix)` triple share
/// the **same** runtime class. The macro's per-hook
/// ``DynamicSubclass/claimOverrideInstallation(on:hookIdentifier:)`` guard
/// keeps each hook's IMPs from clobbering the other's: this is the
/// "composition" pattern AppKitPlus uses to bundle multiple interactions
/// onto a single "Enhancements" subclass.
///
/// ## adopts:
///
/// Each entry in `adopts:` is an `@objc` protocol the dynamic subclass
/// should declare conformance to via `class_addProtocol`. The same
/// protocols are also used as the fallback type-encoding source for hook
/// methods that aren't declared on `baseClass` itself (typical for AppKit
/// informal-protocol selectors like `draggingEntered:` or
/// `springLoadingActivated:draggingInfo:`).
///
/// Entries **must** be written as `<Type>.self`; the macro diagnoses other
/// shapes at compile time.
///
/// ## Opt-in override marker
///
/// Methods to install as ObjC overrides **must** be tagged with
/// ``DynamicSubclassOverride(_:)``. Untagged methods stay plain Swift
/// helpers and are not registered against the dynamic subclass — this
/// avoids the footgun where a `private func helper()` would silently
/// swizzle any same-named selector on the base class.
///
/// ## Generated members
///
/// 1. **Storage**: `let base: BaseClass` plus the memberwise `init(base:)`.
///    The hook container is constructed per-invocation around the swizzled
///    instance, so user code addresses the original AppKit/Foundation object
///    through `self.base` (analogous to the `box.base` pattern elsewhere in
///    FrameworkToolbox).
/// 2. **Entry points**: `static func install(on: BaseClass)` and
///    `static func uninstall(from: BaseClass)`. **Ref-counted** — N installs
///    require N uninstalls to fully restore the isa. Both wrap
///    ``DynamicSubclass/retain(_:dynamicSubclass:)`` /
///    ``DynamicSubclass/release(_:)``.
/// 3. **Lifecycle helper**: `static func dynamicSubclass(for: BaseClass) -> AnyClass?`
///    looks up or lazily creates the runtime class (handling
///    ``DynamicSubclass/AllocationError`` via
///    ``DynamicSubclass/logAllocationFailure(_:baseClass:)`` and returning
///    `nil` on failure).
/// 4. **Registry**: a private `installOverridesIfNeeded(on:)` that, for every
///    `@DynamicSubclassOverride`-tagged method, builds a
///    `@convention(block)` trampoline and assembles a descriptor entry. The
///    once-guard inside it prevents repeat IMP allocation.
///
/// ## Selector derivation
///
/// Each tagged hook method's selector is derived from its Swift signature:
///
/// * Zero parameters: `<methodName>` (e.g. `greet` → `greet`).
/// * N parameters with `_` as the first label: `<methodName>:<param2Label>:...`
///   (e.g. `func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int)`
///   → `tableView:viewFor:row:`).
/// * Non-`_` first parameter label is diagnosed at compile time — Swift's
///   `@objc` bridging would have produced
///   `<methodName>With<CapitalizedLabel>:` for the first parameter, and
///   this macro's naive derivation would not match. Pass an explicit
///   selector to ``DynamicSubclassOverride(_:)`` when you need to preserve
///   a non-`_` label.
///
/// ## Example
///
/// ```swift
/// @DynamicSubclassHook(of: Greeter.self, suffix: "Loud")
/// struct LoudGreeterHook {
///     @DynamicSubclassOverride
///     func greet() -> String {
///         callSuper().uppercased() + "!"
///     }
/// }
///
/// let greeter = Greeter()
/// LoudGreeterHook.install(on: greeter)
/// _ = greeter.greet()                   // "HELLO!"
/// LoudGreeterHook.uninstall(from: greeter)
/// _ = greeter.greet()                   // "Hello"
/// ```
///
/// ## Compile-time diagnostics
///
/// The macro rejects (at compile time, with diagnostics anchored to the
/// offending source token) the following shapes:
///
/// * Containers other than `struct` / `class` (`enum`, `actor`, `extension`,
///   `protocol`).
/// * `throws`, `async`, `mutating`, `@MainActor`, actor-isolated hook methods.
/// * Parameters / return types using `inout`, Swift tuples (arity > 1),
///   bare Swift closure types, or other shapes not Objective-C representable.
/// * `adopts:` entries that aren't `<Type>.self`.
/// * Missing `of:`, missing both `prefix:` and `suffix:`, or any unknown
///   argument label.
/// * Selector collisions with the baseline overrides
///   (`class` / `respondsToSelector:` / `conformsToProtocol:`) or duplicate
///   selectors within the same hook.
///
/// - Parameters:
///   - baseClass: The Objective-C-bridged class to subclass per instance.
///     Must be `NSObject` or a descendant.
///   - prefix: Optional discriminator joined before the base class name in
///     the dynamic class's runtime name. Useful for grouping hooks by
///     installer.
///   - suffix: Optional discriminator joined after the base class name in
///     the dynamic class's runtime name. Useful for naming hooks by purpose.
///     At least one of `prefix` / `suffix` must be non-empty.
///   - adoptedProtocols: `@objc` protocols the dynamic subclass should
///     declare conformance to. Each entry must be written as `<P>.self`.
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

/// Marks a method on a ``DynamicSubclassHook(of:prefix:suffix:adopts:)``
/// container as an override that should be installed against the dynamic
/// subclass, and injects typed `callSuper` helpers into the method body.
///
/// ## What it does
///
/// `@DynamicSubclassOverride` plays two roles at once:
///
/// 1. **Opt-in marker** — the ``DynamicSubclassHook(of:prefix:suffix:adopts:)``
///    member macro only registers methods tagged with this attribute. Plain
///    `func` declarations on the same hook container stay as ordinary Swift
///    helpers and are *not* exposed to the Objective-C runtime, which
///    eliminates the footgun where a `private func helper()` would
///    accidentally swizzle a base-class selector by name collision.
///
/// 2. **Body rewriter** — the method body is rewritten to prepend two
///    locally-scoped helper functions whose signatures mirror the user
///    method exactly:
///
///    * `callSuper(args...) -> Ret` — dispatches unconditionally to the
///      original class's IMP. Traps via
///      ``DynamicSubclass/resolveSuperImplementation(for:selector:)`` if the
///      original class doesn't implement the selector (which is almost
///      always a mistake — see `callSuperIfImplemented` below).
///
///    * `callSuperIfImplemented(args...)` (for `Void`-returning methods) /
///      `callSuperIfImplemented(default: Ret, args...) -> Ret` (for
///      returning methods) — dispatches via
///      ``DynamicSubclass/resolveSuperImplementationIfAvailable(for:selector:)``,
///      returning early (or returning the explicit `default`) when the
///      original class doesn't implement the selector. Use this for hook
///      methods that target a selector introduced through the `adopts:`
///      protocol set on the container, since the base class isn't required
///      to provide an implementation.
///
/// The user's own statements follow the injected helpers unchanged. Single-
/// expression bodies are automatically lifted to an explicit `return` so the
/// rewrite never breaks Swift's implicit-return rule.
///
/// ## Selector derivation
///
/// When ``explicitSelector`` is `nil` (the default), the selector is derived
/// from the Swift method name and parameter labels — see the discussion on
/// ``DynamicSubclassHook(of:prefix:suffix:adopts:)`` for the rules and the
/// non-`_` first-label diagnostic.
///
/// ``explicitSelector`` is the escape hatch when the Swift signature can't
/// naturally produce the Objective-C selector you need. Two common reasons:
///
/// * The first parameter has a non-`_` label that Swift's `@objc` bridge
///   would have rendered as `<methodName>With<CapitalizedLabel>:`. The
///   macro's naive derivation would not match, so it diagnoses; pass an
///   explicit selector like `"formatWithMessage:level:"` instead.
/// * The hook method targets a selector whose ObjC spelling is hand-crafted
///   (camel-cased differently than the Swift `@objc` bridge produces, or
///   coming from a `+initialize`-stamped private API).
///
/// ## Example — basic override
///
/// ```swift
/// @DynamicSubclassHook(of: Greeter.self, suffix: "Loud")
/// struct LoudGreeterHook {
///     @DynamicSubclassOverride
///     func greet() -> String {
///         callSuper().uppercased() + "!"
///     }
///
///     // Plain Swift helper — not registered against the dynamic subclass.
///     func decorate(_ text: String) -> String { text + "!" }
/// }
/// ```
///
/// ## Example — explicit selector
///
/// ```swift
/// @DynamicSubclassHook(of: Formatter.self, suffix: "Bridged")
/// struct BridgedFormatterHook {
///     @DynamicSubclassOverride("formatWithMessage:level:")
///     func format(message: String, level: Int) -> String {
///         callSuper(message, level).uppercased()
///     }
/// }
/// ```
///
/// ## Example — `adopts:` informal protocol with `callSuperIfImplemented`
///
/// ```swift
/// @objc protocol Greetable {
///     func greetingPrefix() -> String
/// }
///
/// @DynamicSubclassHook(of: BareSpeaker.self, suffix: "Polite",
///                      adopts: [Greetable.self])
/// struct PoliteSpeakerHook {
///     @DynamicSubclassOverride
///     func greetingPrefix() -> String {
///         // BareSpeaker doesn't actually implement greetingPrefix; the
///         // helper falls back to the explicit default.
///         callSuperIfImplemented(default: "Mx. ")
///     }
/// }
/// ```
///
/// ## Compile-time diagnostics
///
/// Same rejection rules as ``DynamicSubclassHook(of:prefix:suffix:adopts:)``:
/// `throws`, `async`, `mutating`, `@MainActor`, actor-isolated, non-ObjC
/// representable parameters / return types (`inout`, multi-element tuples,
/// bare Swift closures), non-`_` first parameter labels (without an
/// `explicitSelector`), reserved baseline selectors (`class`,
/// `respondsToSelector:`, `conformsToProtocol:`), and duplicate selectors
/// within the same hook are all caught and reported with diagnostics
/// anchored to the user's source token.
///
/// - Parameter explicitSelector: Optional Objective-C selector string to use
///   instead of the auto-derived one. Pass when the Swift signature can't
///   produce the selector you need.
@attached(body)
public macro DynamicSubclassOverride(_ explicitSelector: String? = nil) = #externalMacro(
    module: "ObjCRuntimeToolboxMacros",
    type: "DynamicSubclassOverrideMacro"
)

#endif
