#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import os

/// Per-instance ISA-swizzling primitives. Swaps a single instance's `isa` to
/// a dynamically-allocated subclass so a small set of selectors is overridden
/// for *that* instance only, without polluting the base class globally and
/// without subclassing at compile time.
///
/// ## Overview
///
/// Conceptually this is the Swift equivalent of the AppKitPlus
/// `_NSDynamicSubclass.h/.m` pair: ``getOrCreate(of:prefix:suffix:)`` wraps
/// `objc_allocateClassPair`, ``retain(_:dynamicSubclass:)`` /
/// ``release(_:)`` wrap `object_setClass` with a ref count and a dealloc
/// sentinel, and ``addOverrides(on:referenceClass:referenceProtocols:_:)``
/// wraps `class_addMethod`.
///
/// ## Two Surfaces
///
/// 1. **High-level macro surface** — ``DynamicSubclassHook`` and
///    ``DynamicSubclassOverride``. Best choice in nearly every case: it
///    derives selectors, generates `@convention(block)` trampolines, generates
///    typed `callSuper(...)` helpers, and runs all the compile-time
///    diagnostics that protect against unbridgeable signatures.
///
/// 2. **Low-level runtime surface** — the static API on this enum. Use it
///    when the selector set is computed at runtime, when integrating with an
///    existing handwritten override pipeline, or when the macro's expected
///    shape doesn't fit (e.g. you want to register IMPs without a Swift
///    container struct).
///
/// ## What gets installed
///
/// Every dynamic subclass produced by ``getOrCreate(of:prefix:suffix:)``
/// receives three baseline overrides at allocation time so introspection of a
/// hooked instance stays coherent:
///
/// * `-class` returns the pre-swizzle class (`originalClass(of:)` is the
///   source of truth). This is the same trick KVO uses to hide its
///   `NSKVONotifying_X` layer from user code reading `[obj class]`.
/// * `-respondsToSelector:` consults the real isa first, then falls through
///   to the original class's IMP, so the hook's added selectors stay
///   discoverable even though `-class` lies.
/// * `-conformsToProtocol:` does the same for protocol conformance so
///   `as? P` succeeds for protocols layered on via
///   ``addProtocols(on:_:)`` / the macro's `adopts:` argument.
///
/// ## Concurrency
///
/// All shared state (subclass cache, side table, override once-guard,
/// generation counter) lives behind a single `os_unfair_lock_s`. Public
/// entry points lock in for the duration of any mutation; the only work
/// done outside the lock is `objc_setAssociatedObject` on the dealloc
/// sentinel, because that primitive takes its own internal locks and we
/// don't want to nest. Generations on each ``retain(_:dynamicSubclass:)``
/// close the ABA window where an old sentinel deinit could otherwise
/// remove a fresh side-table entry.
///
/// ## Example (low-level)
///
/// ```swift
/// let dynamicClass = try DynamicSubclass.getOrCreate(
///     of: MyView.self,
///     prefix: "Drop"
/// )
/// let dragEnteredOverride = DynamicSubclass.Override(
///     selector: NSSelectorFromString("draggingEntered:"),
///     block: ({ (instance, info) -> NSDragOperation in
///         return .copy
///     }) as @convention(block) (AnyObject, NSDraggingInfo) -> NSDragOperation
///         as AnyObject
/// )
/// DynamicSubclass.addOverrides(
///     on: dynamicClass,
///     referenceProtocols: [NSDraggingDestination.self as Protocol],
///     [dragEnteredOverride]
/// )
/// DynamicSubclass.retain(view, dynamicSubclass: dynamicClass)
/// // ... later ...
/// DynamicSubclass.release(view)
/// ```
public enum DynamicSubclass {

    // MARK: - Public Types

    /// Descriptor for a single instance-method override registered against a
    /// dynamic subclass via ``addOverrides(on:referenceClass:referenceProtocols:_:)``.
    ///
    /// ## Contracts
    ///
    /// Direct hand-written use must honour three contracts; the macro fulfils
    /// them automatically so most callers never see `Override` directly:
    ///
    /// 1. ``block`` is a `@convention(block)` closure bridged through
    ///    `as AnyObject` so the Objective-C runtime can wrap it with
    ///    `imp_implementationWithBlock`. The block's **first parameter is the
    ///    receiving `self`** as `AnyObject` (or a concrete class); the
    ///    remaining parameters mirror the method's positional arguments. The
    ///    return type must be Objective-C representable (`@objc` class,
    ///    `Bool` / `Int` family, `String`, `Selector`, `AnyClass`,
    ///    `Optional<class>`, `Void`).
    /// 2. ``typeEncoding`` — when supplied — must be a valid Objective-C type
    ///    encoding string in the `<ret><size>@0:8<args>` format (for example
    ///    `v24@0:8@16` for a `void method:(id)`, or `B24@0:8:16` for a
    ///    `BOOL method:(SEL)`). When left `nil`,
    ///    ``addOverrides(on:referenceClass:referenceProtocols:_:)`` resolves
    ///    the encoding by consulting `referenceClass` then each
    ///    `referenceProtocols` entry.
    /// 3. ``selector`` is the runtime selector the IMP will be registered
    ///    under, exactly as `class_addMethod` expects.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let pingBlock: @convention(block) (AnyObject) -> Int = { _ in 42 }
    /// let override = DynamicSubclass.Override(
    ///     selector: NSSelectorFromString("ping"),
    ///     typeEncoding: "q16@0:8",   // returns long long (q)
    ///     block: pingBlock as AnyObject
    /// )
    /// ```
    public struct Override {
        /// Runtime selector the IMP will be registered under via
        /// `class_addMethod`.
        public let selector: Selector

        /// Objective-C type encoding for the IMP, or `nil` to defer encoding
        /// resolution to
        /// ``DynamicSubclass/addOverrides(on:referenceClass:referenceProtocols:_:)``.
        ///
        /// Valid strings follow the standard Objective-C runtime convention,
        /// e.g. `v24@0:8@16` for `void method:(id)` or `q16@0:8` for an
        /// `NSInteger`-returning getter. See Apple's "Objective-C Runtime
        /// Programming Guide → Type Encodings" for the full table.
        public let typeEncoding: String?

        /// The IMP block, bridged to `AnyObject`.
        ///
        /// Must be a `@convention(block)` closure converted via `as AnyObject`
        /// so that `imp_implementationWithBlock` can wrap it. Its signature
        /// is `(self: AnyObject, arg1, arg2, ...) -> Ret` — note that the
        /// implicit `self` parameter is **explicit** in the block signature
        /// (unlike Swift methods where it's elided). Captures inside the
        /// closure are retained for the lifetime of the dynamic subclass and
        /// never re-released, so heavy captures should be avoided.
        public let block: AnyObject

        /// Construct an override descriptor.
        ///
        /// - Parameters:
        ///   - selector: The Objective-C selector this IMP will respond to.
        ///   - typeEncoding: Optional pre-resolved ObjC type encoding string.
        ///     Pass `nil` to let
        ///     ``DynamicSubclass/addOverrides(on:referenceClass:referenceProtocols:_:)``
        ///     resolve it from a reference class or protocol.
        ///   - block: The IMP block, bridged via `as AnyObject`. See the type
        ///     documentation on ``block`` for the required signature shape.
        public init(
            selector: Selector,
            typeEncoding: String? = nil,
            block: AnyObject
        ) {
            self.selector = selector
            self.typeEncoding = typeEncoding
            self.block = block
        }
    }

    /// Failure mode reported by ``getOrCreate(of:prefix:suffix:)``.
    ///
    /// Each case explains *why* the runtime cannot safely produce or reuse a
    /// dynamic subclass for the requested base, so callers can decide whether
    /// to surface a developer-facing error, fall back to a non-hooked
    /// implementation, or log and continue.
    ///
    /// The macro-generated `install(on:)` catches every case, routes it
    /// through ``logAllocationFailure(_:baseClass:)``, and bails out without
    /// retaining the instance — no half-installed state is left behind.
    public enum AllocationError: Error, CustomStringConvertible {
        /// `objc_allocateClassPair` returned `nil`, so a fresh runtime class
        /// could not be created.
        ///
        /// The most common cause is a name collision: another module
        /// (intentionally or accidentally) already registered a class with the
        /// same dynamic name and that class is **not** a descendant of
        /// `baseClass`. Other possible causes include severe memory pressure
        /// or runtime invariants temporarily preventing class pair creation.
        ///
        /// - Parameters:
        ///   - baseClass: The base class the caller asked to subclass.
        ///   - dynamicClassName: The exact name that
        ///     `objc_allocateClassPair` rejected.
        case allocateClassPairFailed(baseClass: AnyClass, dynamicClassName: String)

        /// A class with the requested dynamic-subclass name **already exists**
        /// in the runtime, but its superclass chain does not contain
        /// `baseClass`.
        ///
        /// Reusing it would let `object_setClass(instance, existingClass)`
        /// silently corrupt unrelated state (the new isa wouldn't share an
        /// ivar layout with the old one). This typically happens when two
        /// modules pick the same `prefix` / `suffix` for different base
        /// classes; choose a more unique discriminator to recover.
        ///
        /// - Parameters:
        ///   - baseClass: The base class the caller asked to subclass.
        ///   - existingClass: The unrelated class found at the name slot.
        ///   - dynamicClassName: The name slot whose occupant doesn't match.
        case existingClassNotDescendant(baseClass: AnyClass, existingClass: AnyClass, dynamicClassName: String)

        /// The base class is itself a metaclass.
        ///
        /// Per-instance ISA swizzling on a `Class` object would replace the
        /// metaclass of every existing instance of the underlying class
        /// system-wide — exactly what this module promises **not** to do.
        /// The fix is always to pass the original class (not its metaclass)
        /// as `baseClass`.
        ///
        /// - Parameter baseClass: The metaclass that was incorrectly supplied.
        case baseClassIsMetaClass(baseClass: AnyClass)

        /// Neither `prefix` nor `suffix` were supplied — at least one must be
        /// non-empty.
        ///
        /// The dynamic-subclass cache is keyed on the composed class name; if
        /// both discriminators are empty every hook variant of the same base
        /// class would collide on the same cache entry, breaking the
        /// per-(class, hook) once-guard inside
        /// ``claimOverrideInstallation(on:hookIdentifier:)`` and silently
        /// dropping later hooks' IMPs.
        ///
        /// - Parameter baseClass: The base class that was passed without a
        ///   discriminator.
        case missingDiscriminator(baseClass: AnyClass)

        public var description: String {
            switch self {
            case let .allocateClassPairFailed(baseClass, dynamicClassName):
                return "DynamicSubclass.getOrCreate: objc_allocateClassPair returned nil for base \(baseClass), name \(dynamicClassName). Likely cause: a class with that name is already registered."
            case let .existingClassNotDescendant(baseClass, existingClass, dynamicClassName):
                return "DynamicSubclass.getOrCreate: existing class \(existingClass) named \(dynamicClassName) is not a descendant of \(baseClass). Refusing to reuse it."
            case let .baseClassIsMetaClass(baseClass):
                return "DynamicSubclass.getOrCreate: base class \(baseClass) is a metaclass; per-instance ISA swizzling cannot target metaclasses."
            case let .missingDiscriminator(baseClass):
                return "DynamicSubclass.getOrCreate: at least one of prefix/suffix must be non-empty for base \(baseClass)."
            }
        }
    }

    // MARK: - Subclass Lifecycle

    /// Look up or lazily create the dynamic subclass identified by
    /// `(baseClass, prefix, suffix)`.
    ///
    /// ## Class-name composition
    ///
    /// The composed name is `_ObjCRuntimeToolbox` joined with the non-empty
    /// discriminators and the base class name by underscores:
    ///
    /// | Discriminators | Class name |
    /// |---|---|
    /// | prefix only | `_ObjCRuntimeToolbox_<prefix>_<baseClassName>` |
    /// | suffix only | `_ObjCRuntimeToolbox_<baseClassName>_<suffix>` |
    /// | both | `_ObjCRuntimeToolbox_<prefix>_<baseClassName>_<suffix>` |
    ///
    /// At least one of `prefix` and `suffix` must be non-empty — otherwise
    /// every hook against the same base class would collide on the same cache
    /// entry, dropping every hook's overrides except the first.
    ///
    /// ## Caching
    ///
    /// Successful results are memoised in a process-wide
    /// `[String: AnyClass]` cache, so repeated calls with the same arguments
    /// return the same `AnyClass` reference without re-running
    /// `objc_allocateClassPair`. Resolution proceeds:
    ///
    /// 1. In-memory cache hit — return immediately.
    /// 2. `objc_getClass(name)` hit — verify the existing class descends from
    ///    `baseClass` (otherwise throw
    ///    ``AllocationError/existingClassNotDescendant(baseClass:existingClass:dynamicClassName:)``);
    ///    idempotently reinstall baseline overrides; cache and return.
    /// 3. Otherwise allocate a new class pair, install baseline overrides,
    ///    register, cache, return.
    ///
    /// ## Baseline overrides
    ///
    /// Every freshly-allocated (or freshly-cached) dynamic subclass receives
    /// `-class`, `-respondsToSelector:`, and `-conformsToProtocol:` overrides
    /// before being registered. See the type-level discussion under
    /// ``DynamicSubclass`` for what each one does.
    ///
    /// - Parameters:
    ///   - baseClass: Class to subclass. Must not be a metaclass.
    ///   - prefix: Optional discriminator joined before the base class name.
    ///     Useful for grouping hooks by *who* installed them
    ///     (e.g. `"DropTarget"`, `"AppKitPlus"`).
    ///   - suffix: Optional discriminator joined after the base class name.
    ///     Useful for naming hooks by *what* they do (e.g. `"Loud"`,
    ///     `"Logging"`). At least one of `prefix` / `suffix` must be
    ///     non-empty.
    ///
    /// - Returns: The cached or freshly-created `AnyClass` descendant of
    ///   `baseClass`.
    /// - Throws: ``AllocationError`` on metaclass input, missing
    ///   discriminator, name collision with an unrelated class, or
    ///   `objc_allocateClassPair` failure.
    public static func getOrCreate(
        of baseClass: AnyClass,
        prefix: String = "",
        suffix: String = ""
    ) throws -> AnyClass {
        if class_isMetaClass(baseClass) {
            throw AllocationError.baseClassIsMetaClass(baseClass: baseClass)
        }
        if prefix.isEmpty && suffix.isEmpty {
            throw AllocationError.missingDiscriminator(baseClass: baseClass)
        }

        sharedLockLock()
        defer { sharedLockUnlock() }

        let baseClassName = String(cString: class_getName(baseClass))
        let dynamicClassName = composeDynamicClassName(
            prefix: prefix,
            baseClassName: baseClassName,
            suffix: suffix
        )

        if let cached = sharedSubclassCache[dynamicClassName] {
            return cached
        }

        let resolved: AnyClass
        if let existing = objc_getClass(dynamicClassName) as? AnyClass {
            // Verify the existing class actually descends from baseClass —
            // otherwise we'd be reusing an unrelated class with the same name
            // (cross-bundle collision, third-party framework, test stub, …)
            // and corrupt state on object_setClass.
            guard classChain(existing, contains: baseClass) else {
                throw AllocationError.existingClassNotDescendant(
                    baseClass: baseClass,
                    existingClass: existing,
                    dynamicClassName: dynamicClassName
                )
            }
            // class_addMethod is idempotent — re-running installBaselineOverrides
            // is safe and ensures the three KVO-compatible overrides exist even
            // when the class was registered by an older / unrelated load.
            installBaselineOverrides(on: existing)
            resolved = existing
        } else {
            guard let created = objc_allocateClassPair(baseClass, dynamicClassName, 0) else {
                throw AllocationError.allocateClassPairFailed(
                    baseClass: baseClass,
                    dynamicClassName: dynamicClassName
                )
            }

            installBaselineOverrides(on: created)
            objc_registerClassPair(created)
            resolved = created
        }

        sharedSubclassCache[dynamicClassName] = resolved
        return resolved
    }

    /// Install `dynamicSubclass` as the runtime class of `object`, or — if it
    /// is already installed — bump the per-object retain count.
    ///
    /// ## Ref-counted semantics
    ///
    /// This call **must be paired with exactly one ``release(_:)``** to
    /// restore the isa. N concurrent installers each call `retain` once and
    /// `release` once; only the final `release` flips the isa back. The
    /// generated macro entry points (`HookType.install(on:)` /
    /// `HookType.uninstall(from:)`) wrap this primitive transparently — direct
    /// users should match calls just as carefully as they would
    /// `Unmanaged.retain` / `Unmanaged.release`.
    ///
    /// ## First-install side effects
    ///
    /// On the first install for an object:
    /// * `object_getClass(object)` is captured as the original class. KVO
    ///   subclasses (`NSKVONotifying_X`) are detected by prefix and refused —
    ///   trying to save such a class as "original" would let the `-class`
    ///   override leak the KVO subclass through `type(of:)`. Install the hook
    ///   *before* you start observing.
    /// * A new entry lands in the side table with `retainCount = 1` and a
    ///   monotonically-increasing `generation` token.
    /// * `object_setClass(object, dynamicSubclass)` flips the isa.
    /// * A weak-ish dealloc sentinel (a `NSObject` capturing the generation)
    ///   is attached via `objc_setAssociatedObject` so that an unmatched
    ///   release (host deallocs while still installed) still drains the side
    ///   table.
    ///
    /// ## Preconditions
    ///
    /// * `dynamicSubclass` must not be a metaclass — a metaclass installed on
    ///   `object` would corrupt global class behavior.
    /// * If `object` already has a side-table entry, the existing
    ///   `dynamicSubclass` must `===` the one passed in. Stacking two
    ///   different dynamic subclasses on the same instance is rejected with
    ///   `preconditionFailure` rather than silently dropping the second
    ///   hook's IMPs. Uninstall the first hook before installing the second.
    ///
    /// - Parameters:
    ///   - object: The instance to swizzle. Must not be `nil`.
    ///   - dynamicSubclass: The previously-prepared dynamic subclass (typically
    ///     from ``getOrCreate(of:prefix:suffix:)``).
    public static func retain(_ object: AnyObject, dynamicSubclass: AnyClass) {
        precondition(
            !class_isMetaClass(dynamicSubclass),
            "DynamicSubclass.retain: dynamicSubclass is a metaclass — refusing to install on \(object)."
        )

        sharedLockLock()

        let objectKey = ObjectIdentifier(object)
        if var existing = sharedSideTable[objectKey] {
            // A different hook is already installed on this instance. Refuse
            // silently overwriting it — the user would observe the second
            // hook's overrides as "never firing".
            precondition(
                existing.dynamicSubclass === dynamicSubclass,
                "DynamicSubclass.retain: \(object) is already installed under \(existing.dynamicSubclass); cannot stack \(dynamicSubclass) on top. Uninstall the existing hook first."
            )
            existing.retainCount += 1
            sharedSideTable[objectKey] = existing
            sharedLockUnlock()
            return
        }

        let currentClass: AnyClass = object_getClass(object) ?? type(of: object)

        // KVO and other layered ISA swizzlers stick a NSKVONotifying_X subclass
        // ahead of the real class. Saving that as "original" would make the
        // -class override leak the KVO subclass through type(of:).
        if classNameSuggestsKVO(currentClass) {
            sharedLockUnlock()
            os_log(
                .fault,
                log: DynamicSubclass.runtimeLog,
                "DynamicSubclass.retain: refusing to install on %{public}@ — its current class %{public}@ looks KVO-installed (NSKVONotifying_…). Install the hook BEFORE adding KVO observers.",
                String(describing: object),
                String(cString: class_getName(currentClass))
            )
            assertionFailure("Install before KVO observation; see os_log for context.")
            return
        }

        let generationValue = nextGeneration
        nextGeneration &+= 1

        sharedSideTable[objectKey] = SideTableEntry(
            originalClass: currentClass,
            dynamicSubclass: dynamicSubclass,
            retainCount: 1,
            generation: generationValue
        )
        object_setClass(object, dynamicSubclass)

        let sentinel = DynamicSubclassSentinel(
            trackedObjectIdentifier: objectKey,
            generation: generationValue
        )
        sharedLockUnlock()

        // Attach sentinel outside the lock — associated-object setters take
        // their own locks internally and we don't want to nest. The sentinel
        // carries the generation it was created under; `cleanupSideTableEntry`
        // refuses to remove a newer entry, which closes the ABA window where
        // an old sentinel deinit fires after a new install has replaced the
        // side-table entry.
        objc_setAssociatedObject(object, &sentinelAssociationKey, sentinel, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Decrement `object`'s install retain count and, on zero, restore its
    /// original class.
    ///
    /// Symmetric counterpart to ``retain(_:dynamicSubclass:)``: every retain
    /// must be balanced by a release. Over-release (releasing an object that
    /// has no side-table entry) is a programmer error and triggers
    /// `assertionFailure` in Debug builds; in Release it is a silent no-op so
    /// production runs don't crash on an asymmetry that may have come from a
    /// late-deinit path.
    ///
    /// ## On retainCount → 0
    ///
    /// * If `object_getClass(object) === entry.dynamicSubclass` the isa is
    ///   restored to the saved original class. The "still matches" guard
    ///   means a KVO observation added *after* install (which layered another
    ///   `NSKVONotifying_X` on top of our dynamic subclass) leaves that
    ///   external swizzle intact — overwriting it would break KVO. Yes, that
    ///   leaves a small leak window; opting to install hooks before KVO is
    ///   the supported answer.
    /// * The side-table entry is removed.
    /// * The dealloc sentinel associated object is dropped. Because the
    ///   sentinel carries the install generation, removing it does not race
    ///   against a subsequent re-install — the deinit checks the generation
    ///   before touching the table.
    ///
    /// - Parameter object: The instance previously installed via
    ///   ``retain(_:dynamicSubclass:)``.
    public static func release(_ object: AnyObject) {
        sharedLockLock()

        let objectKey = ObjectIdentifier(object)
        guard var entry = sharedSideTable[objectKey] else {
            sharedLockUnlock()
            assertionFailure("DynamicSubclass.release: \(object) is not installed — over-release.")
            return
        }

        entry.retainCount -= 1
        if entry.retainCount > 0 {
            sharedSideTable[objectKey] = entry
            sharedLockUnlock()
            return
        }

        let currentClass: AnyClass? = object_getClass(object)
        if currentClass === entry.dynamicSubclass {
            object_setClass(object, entry.originalClass)
        }
        sharedSideTable.removeValue(forKey: objectKey)
        sharedLockUnlock()

        // Detach sentinel outside the lock to avoid lock nesting with the
        // associated-object internal locks. Setting to nil here drops the
        // sentinel without firing cleanupSideTableEntry against a fresh entry,
        // because we already removed our entry above and the sentinel's own
        // deinit (via generation check) is a no-op against any newer entry.
        objc_setAssociatedObject(object, &sentinelAssociationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Whether `object` currently has a side-table entry — i.e. at least one
    /// ``retain(_:dynamicSubclass:)`` is unmatched by a ``release(_:)``.
    ///
    /// Useful in tests and in code that needs to behave differently for
    /// hooked vs. untouched instances. The result is a momentary snapshot:
    /// another thread may install or release between the call returning and
    /// the next line of caller code, so do not gate critical work on the
    /// answer without your own synchronisation.
    ///
    /// - Parameter object: Any object reference.
    /// - Returns: `true` if a side-table entry exists for `object`,
    ///   regardless of retain count value.
    public static func isInstalled(on object: AnyObject) -> Bool {
        sharedLockLock()
        defer { sharedLockUnlock() }
        return sharedSideTable[ObjectIdentifier(object)] != nil
    }

    /// The class the object had *before* any dynamic-subclass swizzling by
    /// this module.
    ///
    /// Reads the saved `originalClass` from the side table when the object is
    /// currently installed. When it isn't installed, this falls back to
    /// `object_getClass(object) ?? type(of: object)` — which may return an
    /// externally-installed swizzle layer such as `NSKVONotifying_X` if some
    /// other system (KVO, a different runtime tool) is layered on. That's
    /// **not** the bare-original-original class; if you need to strip
    /// external layers too you'll need to walk `class_getSuperclass` past
    /// the recognisable wrapper prefixes yourself.
    ///
    /// Used internally by the baseline `-class` override to keep
    /// `type(of: hookedInstance)` returning the user-visible class.
    ///
    /// - Parameter object: Any object reference.
    /// - Returns: The recorded pre-swizzle class for installed objects, or
    ///   the current isa fallback for everything else.
    public static func originalClass(of object: AnyObject) -> AnyClass {
        sharedLockLock()
        if let entry = sharedSideTable[ObjectIdentifier(object)] {
            sharedLockUnlock()
            return entry.originalClass
        }
        sharedLockUnlock()
        return object_getClass(object) ?? type(of: object)
    }

    // MARK: - Override Registration

    /// Idempotently register `overrides` on `dynamicSubclass`.
    ///
    /// ## Idempotency and leak avoidance
    ///
    /// `class_addMethod` only succeeds when the selector is not already
    /// implemented on `dynamicSubclass`. On a repeat call (e.g. the macro's
    /// `installOverridesIfNeeded` running for a second hook against the same
    /// shared subclass) this method:
    /// * Allocates a fresh trampoline via `imp_implementationWithBlock`.
    /// * Calls `class_addMethod`. If it succeeds, the trampoline retains the
    ///   block for the dynamic subclass's lifetime.
    /// * If `class_addMethod` returns `false` (slot already filled), the
    ///   trampoline is reclaimed via `imp_removeBlock` — without this,
    ///   every repeat install would leak one IMP per selector.
    ///
    /// First-wins resolution means hooks composing against a shared dynamic
    /// subclass cannot accidentally clobber each other's selectors.
    ///
    /// ## Type encoding resolution chain
    ///
    /// For each ``Override`` the type encoding is resolved in this order
    /// (later steps only run if earlier ones return `nil`):
    ///
    /// 1. ``Override/typeEncoding`` — caller-supplied string.
    /// 2. The same selector on `referenceClass`, via
    ///    `class_getInstanceMethod` + `method_getTypeEncoding`.
    /// 3. For each `referenceProtocols` entry, `protocol_getMethodDescription`
    ///    in `(required: true, instance: true)` then `(required: false,
    ///    instance: true)` order.
    /// 4. Fallback string `v24@0:8@16` (void return + single `id` argument).
    ///    Falling through to (4) logs an `os_log` warning and trips a
    ///    Debug-only `assertionFailure`, since an incorrect type encoding
    ///    will misbehave under `NSMethodSignature`, `NSInvocation`, KVO
    ///    forwarding, and debug reflection — even though plain
    ///    `objc_msgSend` doesn't care.
    ///
    /// ## Precondition
    ///
    /// `dynamicSubclass` must not be equal to `referenceClass`. The install
    /// path keeps this branch unreachable for macro users, but a low-level
    /// caller could mistakenly pass the base class as the dynamic subclass,
    /// which would globally swizzle every instance of that class. The
    /// precondition trips before any IMPs are registered.
    ///
    /// - Parameters:
    ///   - dynamicSubclass: The class returned by
    ///     ``getOrCreate(of:prefix:suffix:)``.
    ///   - referenceClass: Class consulted for type-encoding resolution
    ///     (typically the original base class). May be `nil`.
    ///   - referenceProtocols: Protocols consulted for type-encoding
    ///     resolution when `referenceClass` doesn't declare the selector
    ///     (covers AppKit informal protocols like `NSDraggingDestination`).
    ///   - overrides: Descriptors to install. Order doesn't matter; each
    ///     selector is registered at most once on a given dynamic subclass.
    public static func addOverrides(
        on dynamicSubclass: AnyClass,
        referenceClass: AnyClass? = nil,
        referenceProtocols: [Protocol] = [],
        _ overrides: [Override]
    ) {
        // Last-line defense: refuse to land overrides on a base class. The
        // install path tries to keep this branch unreachable, but a manual
        // caller could pass a dynamicSubclass that equals the base.
        precondition(
            referenceClass.map { dynamicSubclass !== $0 } ?? true,
            "DynamicSubclass.addOverrides: dynamicSubclass === referenceClass; refusing to globally swizzle the base class."
        )

        for override in overrides {
            let encoding = resolveTypeEncoding(
                for: override.selector,
                explicitEncoding: override.typeEncoding,
                referenceClass: referenceClass,
                referenceProtocols: referenceProtocols
            )
            let imp = imp_implementationWithBlock(override.block)
            let added = class_addMethod(dynamicSubclass, override.selector, imp, encoding)
            if !added {
                // class_addMethod refused (selector already present). Reclaim
                // the trampoline; otherwise every repeat install leaks an IMP.
                imp_removeBlock(imp)
            }
        }
    }

    /// Idempotently declare that `dynamicSubclass` conforms to each given
    /// protocol via `class_addProtocol`.
    ///
    /// Pair this with ``addOverrides(on:referenceClass:referenceProtocols:_:)``
    /// when the hook implements informal-protocol methods on a base class
    /// that didn't originally declare conformance. After this call, hooked
    /// instances:
    ///
    /// * Return `true` from `-conformsToProtocol:` for the protocol — both
    ///   directly and via the baseline override that consults the real isa.
    /// * Bridge through `as? P` to the Swift protocol view.
    ///
    /// `class_addProtocol` is itself idempotent (re-adding the same protocol
    /// is a no-op), so it's safe to call this on every install path.
    ///
    /// - Parameters:
    ///   - dynamicSubclass: The class returned by
    ///     ``getOrCreate(of:prefix:suffix:)``.
    ///   - protocols: Objective-C protocols to declare conformance to.
    ///     `Protocol` values are obtainable in Swift via
    ///     `MyObjcProtocol.self as Protocol` (note: `@objc` is required —
    ///     plain Swift protocols are not bridgeable).
    public static func addProtocols(on dynamicSubclass: AnyClass, _ protocols: [Protocol]) {
        for proto in protocols {
            class_addProtocol(dynamicSubclass, proto)
        }
    }

    /// Once-guard for hook override installation.
    ///
    /// Returns `true` exactly once per `(dynamicSubclass, hookIdentifier)`
    /// pair and `false` on every subsequent call. Macro-generated
    /// `installOverridesIfNeeded(on:)` consults this guard before constructing
    /// any `@convention(block)` trampolines: the first install for a given
    /// hook builds them and registers IMPs; subsequent installs short-circuit
    /// and avoid the trampoline allocation and the `imp_implementationWithBlock`
    /// + `imp_removeBlock` dance entirely.
    ///
    /// ## Why per-(class, hook), not per-class
    ///
    /// Two hooks targeting the same base class with the same discriminator
    /// share one ``getOrCreate(of:prefix:suffix:)`` result — that's the
    /// intended composition pattern (e.g. AppKitPlus's "Enhancements"
    /// subclass collects overrides from a handful of interaction hooks). A
    /// per-class guard would let the first hook claim the shared class and
    /// silently lock the second one out. The per-(class, hook) key lets each
    /// hook claim its own slot, so both register exactly once and neither
    /// trample the other.
    ///
    /// Calling this directly is only required by handwritten installers; the
    /// macro path always uses it.
    ///
    /// - Parameters:
    ///   - dynamicSubclass: The class from ``getOrCreate(of:prefix:suffix:)``.
    ///   - hookIdentifier: A string uniquely identifying the hook *within*
    ///     `dynamicSubclass`. The macro uses the hook struct's source name
    ///     (e.g. `"LoudGreeterHook"`); handwritten installers should pick a
    ///     stable, module-unique identifier so they can be re-invoked
    ///     idempotently.
    /// - Returns: `true` on the first call (caller should proceed to install
    ///   overrides), `false` otherwise.
    public static func claimOverrideInstallation(
        on dynamicSubclass: AnyClass,
        hookIdentifier: String
    ) -> Bool {
        sharedLockLock()
        defer { sharedLockUnlock() }
        let key = InstallationKey(
            classIdentifier: ObjectIdentifier(dynamicSubclass),
            hookIdentifier: hookIdentifier
        )
        return sharedInstalledOverrides.insert(key).inserted
    }

    /// Public-but-internal escape hatch used by macro-generated code to
    /// surface ``getOrCreate(of:prefix:suffix:)`` failures via `os_log`
    /// without forcing the call site to `import os` itself.
    ///
    /// The message is logged at `.fault` against the
    /// `ObjCRuntimeToolbox/DynamicSubclass` `OSLog` subsystem, so it shows up
    /// in Console.app and survives in fault traces. Production code can rely
    /// on this remaining public; nothing prevents handwritten installers from
    /// using the same logger.
    ///
    /// - Parameters:
    ///   - error: The error thrown by ``getOrCreate(of:prefix:suffix:)``
    ///     (typically an ``AllocationError`` value).
    ///   - baseClass: The base class the install attempt was targeting; logged
    ///     alongside the error to make Console output identifiable.
    public static func logAllocationFailure(_ error: Error, baseClass: AnyClass) {
        os_log(
            .fault,
            log: runtimeLog,
            "@DynamicSubclassHook: failed to materialise dynamic subclass for %{public}@ — %{public}@",
            String(describing: baseClass),
            String(describing: error)
        )
    }

    // MARK: - Super-Call Helpers

    /// Resolve the original class's IMP for `selector` so a hook can call
    /// "super".
    ///
    /// ## Usage pattern
    ///
    /// Macro-generated `callSuper(...)` thunks call this and `unsafeBitCast`
    /// the resulting IMP to a `@convention(c)` function pointer with the
    /// hook method's *concrete* argument and return types:
    ///
    /// ```swift
    /// let imp = DynamicSubclass.resolveSuperImplementation(
    ///     for: instance,
    ///     selector: NSSelectorFromString("greet")
    /// )
    /// let f = unsafeBitCast(
    ///     imp,
    ///     to: (@convention(c) (AnyObject, Selector) -> String).self
    /// )
    /// return f(instance, NSSelectorFromString("greet"))
    /// ```
    ///
    /// The cast must happen at the call site, not inside a generic helper —
    /// Swift refuses to form a `@convention(c)` function type whose
    /// signature mentions an unresolved generic parameter (representability
    /// can't be proven for an arbitrary `T`). The macro pushes this into
    /// generated code so user-facing hook methods never have to write the
    /// cast themselves.
    ///
    /// ## When it traps
    ///
    /// Traps with `fatalError` if the original class doesn't implement
    /// `selector`. This is almost always a mis-use: hooking an informal
    /// protocol method (`adopts:`-only) and calling `callSuper()` instead of
    /// `callSuperIfImplemented(default:)`. Switch to
    /// ``resolveSuperImplementationIfAvailable(for:selector:)`` for those
    /// cases.
    ///
    /// - Parameters:
    ///   - instance: The hooked instance. Used to recover the saved original
    ///     class via ``originalClass(of:)``.
    ///   - selector: The selector to dispatch to.
    /// - Returns: The original class's IMP for `selector`.
    public static func resolveSuperImplementation(
        for instance: AnyObject,
        selector: Selector
    ) -> IMP {
        let originalClassValue: AnyClass = originalClass(of: instance)
        guard let method = class_getInstanceMethod(originalClassValue, selector) else {
            fatalError(
                """
                DynamicSubclass.resolveSuperImplementation: original class \(originalClassValue) does not implement \(selector). \
                This typically happens when a hook method targets an informal-protocol selector (e.g. adopts: protocol entries) — use `callSuperIfImplemented(default:)` instead of `callSuper()` for those.
                """
            )
        }
        return method_getImplementation(method)
    }

    /// Non-trapping companion to ``resolveSuperImplementation(for:selector:)``.
    ///
    /// Use this when the hook's selector might not exist on the original
    /// class — typically because it comes from a protocol that the base
    /// class doesn't declare conformance to, but that the hook installs via
    /// `adopts:`. The macro's `callSuperIfImplemented(default:)` helper is
    /// built on top of this entry point.
    ///
    /// - Parameters:
    ///   - instance: The hooked instance.
    ///   - selector: The selector to look up.
    /// - Returns: The original class's IMP for `selector`, or `nil` if the
    ///   original class does not implement it.
    public static func resolveSuperImplementationIfAvailable(
        for instance: AnyObject,
        selector: Selector
    ) -> IMP? {
        let originalClassValue: AnyClass = originalClass(of: instance)
        guard let method = class_getInstanceMethod(originalClassValue, selector) else {
            return nil
        }
        return method_getImplementation(method)
    }

    // MARK: - Internal Storage

    private struct SideTableEntry {
        let originalClass: AnyClass
        let dynamicSubclass: AnyClass
        var retainCount: Int
        let generation: UInt64
    }

    // `os_unfair_lock` is available since iOS 10 / macOS 10.12, fits our
    // platform floor, and avoids both a FoundationToolbox dependency and the
    // iOS 16 / macOS 13 gate that `OSAllocatedUnfairLock` carries. The lock
    // protects all three shared collections plus `nextGeneration`.
    nonisolated(unsafe) private static var sharedLockStorage = os_unfair_lock_s()
    nonisolated(unsafe) private static var sharedSubclassCache: [String: AnyClass] = [:]
    nonisolated(unsafe) private static var sharedSideTable: [ObjectIdentifier: SideTableEntry] = [:]
    private struct InstallationKey: Hashable {
        let classIdentifier: ObjectIdentifier
        let hookIdentifier: String
    }
    nonisolated(unsafe) private static var sharedInstalledOverrides: Set<InstallationKey> = []
    nonisolated(unsafe) private static var nextGeneration: UInt64 = 1

    static let runtimeLog = OSLog(subsystem: "ObjCRuntimeToolbox", category: "DynamicSubclass")

    private static func sharedLockLock() {
        withUnsafeMutablePointer(to: &sharedLockStorage) { os_unfair_lock_lock($0) }
    }

    private static func sharedLockUnlock() {
        withUnsafeMutablePointer(to: &sharedLockStorage) { os_unfair_lock_unlock($0) }
    }

    // MARK: - Internal Helpers

    private static func composeDynamicClassName(
        prefix: String,
        baseClassName: String,
        suffix: String
    ) -> String {
        var components: [String] = ["_ObjCRuntimeToolbox"]
        if !prefix.isEmpty { components.append(prefix) }
        components.append(baseClassName)
        if !suffix.isEmpty { components.append(suffix) }
        return components.joined(separator: "_")
    }

    private static func classChain(_ start: AnyClass, contains target: AnyClass) -> Bool {
        var cursor: AnyClass? = start
        while let current = cursor {
            if current === target { return true }
            cursor = class_getSuperclass(current)
        }
        return false
    }

    private static func classNameSuggestsKVO(_ cls: AnyClass) -> Bool {
        let name = String(cString: class_getName(cls))
        return name.hasPrefix("NSKVONotifying_")
    }

    /// Install `-class`, `-respondsToSelector:`, and `-conformsToProtocol:`
    /// overrides on a freshly-allocated dynamic subclass. The `-class` override
    /// powers the KVO illusion; the other two ensure introspection sees the
    /// real ISA's added members despite `-class` lying.
    private static func installBaselineOverrides(on dynamicSubclass: AnyClass) {
        let classOverride: @convention(block) (AnyObject) -> AnyClass = { instance in
            originalClass(of: instance)
        }
        let classImplementation = imp_implementationWithBlock(classOverride as AnyObject)
        let classSelector = NSSelectorFromString("class")
        if !class_addMethod(dynamicSubclass, classSelector, classImplementation, baselineEncoding(for: classSelector, fallback: "#16@0:8")) {
            imp_removeBlock(classImplementation)
        }

        let respondsSelector = NSSelectorFromString("respondsToSelector:")
        let respondsOverride: @convention(block) (AnyObject, Selector) -> Bool = { instance, querySelector in
            if class_respondsToSelector(object_getClass(instance), querySelector) {
                return true
            }
            let originalCls: AnyClass = originalClass(of: instance)
            guard let method = class_getInstanceMethod(originalCls, respondsSelector) else {
                return false
            }
            let imp = method_getImplementation(method)
            let function = unsafeBitCast(
                imp,
                to: (@convention(c) (AnyObject, Selector, Selector) -> Bool).self
            )
            return function(instance, respondsSelector, querySelector)
        }
        let respondsImplementation = imp_implementationWithBlock(respondsOverride as AnyObject)
        if !class_addMethod(dynamicSubclass, respondsSelector, respondsImplementation, baselineEncoding(for: respondsSelector, fallback: "B24@0:8:16")) {
            imp_removeBlock(respondsImplementation)
        }

        let conformsSelector = NSSelectorFromString("conformsToProtocol:")
        let conformsOverride: @convention(block) (AnyObject, Protocol) -> Bool = { instance, queryProtocol in
            if class_conformsToProtocol(object_getClass(instance), queryProtocol) {
                return true
            }
            let originalCls: AnyClass = originalClass(of: instance)
            guard let method = class_getInstanceMethod(originalCls, conformsSelector) else {
                return false
            }
            let imp = method_getImplementation(method)
            let function = unsafeBitCast(
                imp,
                to: (@convention(c) (AnyObject, Selector, Protocol) -> Bool).self
            )
            return function(instance, conformsSelector, queryProtocol)
        }
        let conformsImplementation = imp_implementationWithBlock(conformsOverride as AnyObject)
        if !class_addMethod(dynamicSubclass, conformsSelector, conformsImplementation, baselineEncoding(for: conformsSelector, fallback: "B24@0:8@16")) {
            imp_removeBlock(conformsImplementation)
        }
    }

    /// Read the real encoding from `NSObject` so x86_64 macOS / Mac Catalyst —
    /// where `BOOL` is `signed char` (`c`) rather than `bool` (`B`) — gets the
    /// architecture-correct string. Only the hand-written literal is used as
    /// a fallback when `NSObject` somehow doesn't expose the selector.
    private static func baselineEncoding(for selector: Selector, fallback: String) -> String {
        if let method = class_getInstanceMethod(NSObject.self, selector),
           let encoding = method_getTypeEncoding(method)
        {
            return String(cString: encoding)
        }
        return fallback
    }

    private static func resolveTypeEncoding(
        for selector: Selector,
        explicitEncoding: String?,
        referenceClass: AnyClass?,
        referenceProtocols: [Protocol]
    ) -> String {
        if let explicit = explicitEncoding {
            return explicit
        }
        if let referenceClass,
           let method = class_getInstanceMethod(referenceClass, selector),
           let encoding = method_getTypeEncoding(method)
        {
            return String(cString: encoding)
        }
        for referenceProtocol in referenceProtocols {
            // Try required-instance first, then optional-instance.
            let requiredInstance = protocol_getMethodDescription(referenceProtocol, selector, true, true)
            if let types = requiredInstance.types {
                return String(cString: types)
            }
            let optionalInstance = protocol_getMethodDescription(referenceProtocol, selector, false, true)
            if let types = optionalInstance.types {
                return String(cString: types)
            }
        }
        os_log(
            .info,
            log: runtimeLog,
            "DynamicSubclass.resolveTypeEncoding: no encoding found for %{public}@ on referenceClass=%{public}@ referenceProtocols=%{public}d; using fallback v24@0:8@16. NSMethodSignature / NSInvocation / KVO forwarding may observe an incorrect signature.",
            NSStringFromSelector(selector),
            referenceClass.map { String(cString: class_getName($0)) } ?? "<none>",
            referenceProtocols.count
        )
        assert(false, "Unresolved ObjC type encoding for \(selector); see os_log for context.")
        return "v24@0:8@16"
    }
}

// MARK: - Dealloc Sentinel

/// Associated-object sentinel: when the tracked object deallocates without an
/// explicit `release(_:)`, this sentinel cleans up its side-table entry. The
/// captured `generation` lets `cleanupSideTableEntry` ignore the deinit if the
/// side-table entry has since been replaced by a newer install — closing an
/// ABA window where an old sentinel would otherwise delete a fresh entry.
private final class DynamicSubclassSentinel: NSObject {
    private let trackedObjectIdentifier: ObjectIdentifier
    private let generation: UInt64
    init(trackedObjectIdentifier: ObjectIdentifier, generation: UInt64) {
        self.trackedObjectIdentifier = trackedObjectIdentifier
        self.generation = generation
        super.init()
    }
    deinit {
        DynamicSubclass.cleanupSideTableEntry(for: trackedObjectIdentifier, generation: generation)
    }
}

private nonisolated(unsafe) var sentinelAssociationKey: UInt8 = 0

extension DynamicSubclass {
    fileprivate static func cleanupSideTableEntry(
        for trackedObjectIdentifier: ObjectIdentifier,
        generation: UInt64
    ) {
        sharedLockLock()
        if let entry = sharedSideTable[trackedObjectIdentifier], entry.generation == generation {
            sharedSideTable.removeValue(forKey: trackedObjectIdentifier)
        }
        sharedLockUnlock()
    }
}

#endif
