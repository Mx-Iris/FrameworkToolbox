#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import os

/// Per-instance ISA-swizzling primitives. Provides the same lifecycle and
/// override-registration surface as the AppKitPlus `_NSDynamicSubclass.h/.m`
/// pair (`objc_allocateClassPair`, `class_addMethod`, `object_setClass`, etc.)
/// in idiomatic Swift.
///
/// This is the lower-level runtime layer used by the `@DynamicSubclassHook`
/// macro; it is also usable directly when the macro's compile-time aggregation
/// is not desired (e.g. dynamically computed selector sets).
public enum DynamicSubclass {

    // MARK: - Public Types

    /// Descriptor for a single instance-method override registered against a
    /// dynamic subclass.
    ///
    /// Direct hand-written use requires the caller to honour three contracts:
    /// 1. `block` is a `@convention(block)` closure cast through `as AnyObject`
    ///    so the Objective-C runtime can bridge it through
    ///    `imp_implementationWithBlock`. The block's first parameter is the
    ///    receiving `self` (`AnyObject`); subsequent parameters match the
    ///    method's positional arguments.
    /// 2. If `typeEncoding` is supplied it must be a valid Objective-C type
    ///    encoding string (e.g. `v24@0:8@16`). When `nil`, `addOverrides`
    ///    resolves the encoding from `referenceClass` / `referenceProtocols`.
    /// 3. `selector` is the runtime selector the IMP will be registered under.
    public struct Override {
        public let selector: Selector
        /// Caller-supplied ObjC type encoding for the IMP. If `nil`,
        /// `addOverrides` resolves it from `referenceClass` / `referenceProtocols`.
        public let typeEncoding: String?
        /// The IMP block. Must be a `@convention(block)` closure bridged via
        /// `as AnyObject`; its signature is `(self: AnyObject, args...) -> Ret`.
        public let block: AnyObject

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

    /// Failure mode reported by `getOrCreate(of:suffix:)`.
    public enum AllocationError: Error, CustomStringConvertible {
        /// `objc_allocateClassPair` returned `nil`. Common causes: a class with
        /// the same name already exists in the runtime, or the runtime is out
        /// of memory.
        case allocateClassPairFailed(baseClass: AnyClass, dynamicClassName: String)
        /// Found an existing class with the dynamic-subclass name, but its
        /// superclass chain does not contain `baseClass` — refusing to reuse
        /// it would silently corrupt unrelated state.
        case existingClassNotDescendant(baseClass: AnyClass, existingClass: AnyClass, dynamicClassName: String)
        /// The base class is itself a metaclass — installing per-instance
        /// hooks on a Class object would corrupt every instance system-wide.
        case baseClassIsMetaClass(baseClass: AnyClass)
        /// Neither `prefix` nor `suffix` were supplied — at least one must be
        /// non-empty to disambiguate hooks against the same base class.
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

    /// Get or create a cached dynamic subclass of `baseClass`. The dynamic
    /// class name combines `_ObjCRuntimeToolbox`, the optional `prefix`, the
    /// base class name, and the optional `suffix` separated by `_`:
    ///
    /// * prefix only: `_ObjCRuntimeToolbox_<prefix>_<baseClassName>`
    /// * suffix only: `_ObjCRuntimeToolbox_<baseClassName>_<suffix>`
    /// * both: `_ObjCRuntimeToolbox_<prefix>_<baseClassName>_<suffix>`
    ///
    /// At least one of `prefix` or `suffix` must be non-empty — supplying
    /// neither would let every hook of `baseClass` collide on the same cache
    /// entry. The created subclass carries three baseline overrides:
    ///
    /// * `-class` returns the original `baseClass` — KVO pattern.
    /// * `-respondsToSelector:` and `-conformsToProtocol:` consult the real ISA
    ///   first so that any selectors / protocols layered onto the dynamic
    ///   subclass remain discoverable even though `-class` lies.
    ///
    /// Throws `AllocationError` on failure; callers should bail out of the
    /// install path when the dynamic subclass cannot be obtained.
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

    /// First retain swaps the object's isa to `dynamicSubclass`; subsequent
    /// retains just bump the per-object counter.
    ///
    /// This is **ref-counted**: every call must be paired with exactly one
    /// `release(_:)` for the dynamic subclass to be uninstalled. The macro
    /// surface (`HookType.install/uninstall`) wraps these primitives.
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

    /// Decrement the per-object retain count; when it hits zero, restore the
    /// original isa (only if the current isa still matches the dynamic
    /// subclass — KVO/other layered swizzlers may have layered on top).
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

    public static func isInstalled(on object: AnyObject) -> Bool {
        sharedLockLock()
        defer { sharedLockUnlock() }
        return sharedSideTable[ObjectIdentifier(object)] != nil
    }

    /// Returns the class the object had before any dynamic-subclass swizzling.
    /// Falls back to the current `object_getClass` reading when no entry is
    /// installed — if the object was swizzled by an external mechanism (e.g.
    /// KVO) this returns the externally-installed class (such as
    /// `NSKVONotifying_X`), not the bare original.
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

    /// Idempotently install instance-method overrides on the dynamic subclass.
    /// Already-installed selectors are left untouched (`class_addMethod`
    /// semantics) and the unused IMP block is reclaimed via `imp_removeBlock`
    /// so repeat installs don't leak trampolines. The type encoding is
    /// resolved in this order: caller-supplied `typeEncoding`, then the
    /// matching method on `referenceClass`, then the matching method on each
    /// `referenceProtocols` entry (required → optional), then a fallback
    /// `v24@0:8@16` (which also logs a warning).
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

    /// Idempotently declare protocol conformance on `dynamicSubclass` so the
    /// runtime reports `[obj conformsToProtocol:]` for protocols whose methods
    /// the hook installed via `addOverrides`.
    public static func addProtocols(on dynamicSubclass: AnyClass, _ protocols: [Protocol]) {
        for proto in protocols {
            class_addProtocol(dynamicSubclass, proto)
        }
    }

    /// Atomically claim the right for `hookIdentifier` to install its override
    /// set on `dynamicSubclass`. Returns `true` on the first call for a given
    /// `(dynamicSubclass, hookIdentifier)` pair (caller should proceed with
    /// `addOverrides` / `addProtocols`) and `false` on every subsequent call
    /// (caller should skip — that hook's overrides are already installed).
    ///
    /// The key is per-(class, hook) rather than per-class so multiple hooks
    /// can compose against the same dynamic subclass when they share a suffix
    /// — each hook still registers exactly once, but they don't trample each
    /// other.
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

    /// Macro-callable failure logger so the generated `dynamicSubclass(for:)`
    /// doesn't have to depend on `import os` at the call site.
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

    /// Resolve the original class's IMP for `selector`. Macro-generated
    /// `callSuper(...)` thunks call this and `unsafeBitCast` the IMP to a
    /// `@convention(c)` function pointer with *concrete* argument and return
    /// types — the cast is kept at the expansion site because Swift refuses
    /// to form a `@convention(c)` type whose signature mentions a generic
    /// parameter (the importer can't prove representability for an unknown
    /// type). Hand-written call sites can use the same pattern.
    ///
    /// Traps when the original class does not implement `selector`. This is
    /// the typical mistake when hooking an `adopts:`-only informal protocol
    /// method that has no super implementation; switch to
    /// `resolveSuperImplementationIfAvailable(for:selector:)` (which the
    /// `callSuperIfImplemented(default:)` macro helper uses) for those.
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

    /// Non-trapping variant: returns `nil` when the original class doesn't
    /// implement `selector` (use case: protocol methods on classes that don't
    /// declare conformance).
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
