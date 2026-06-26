#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

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

    /// Descriptor for a single instance-method override.
    public struct Override {
        public let selector: Selector
        public let typeEncoding: String?
        /// The IMP block. Caller is responsible for casting their
        /// `@convention(block)` closure via `as AnyObject` to bridge it through
        /// to the Objective-C runtime.
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

    // MARK: - Subclass Lifecycle

    /// Get or create a cached dynamic subclass of `baseClass` named
    /// `_ObjCRuntimeToolbox_<suffix>_<baseClassName>`. The created subclass
    /// carries three baseline overrides:
    ///
    /// * `-class` returns the original `baseClass` — KVO pattern.
    /// * `-respondsToSelector:` and `-conformsToProtocol:` consult the real ISA
    ///   first so that any selectors / protocols layered onto the dynamic
    ///   subclass remain discoverable even though `-class` lies.
    public static func getOrCreate(of baseClass: AnyClass, suffix: String) -> AnyClass {
        sharedLock.lock()
        defer { sharedLock.unlock() }

        let baseClassName = String(cString: class_getName(baseClass))
        let dynamicClassName = "_ObjCRuntimeToolbox_\(suffix)_\(baseClassName)"

        if let cached = sharedSubclassCache[dynamicClassName] {
            return cached
        }

        let resolved: AnyClass
        if let existing = objc_getClass(dynamicClassName) as? AnyClass {
            resolved = existing
        } else {
            guard let created = objc_allocateClassPair(baseClass, dynamicClassName, 0) else {
                // Allocation failed — fall back to the base class itself so
                // the caller still has something usable.
                return baseClass
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
    public static func retain(_ object: AnyObject, dynamicSubclass: AnyClass) {
        sharedLock.lock()

        let objectKey = ObjectIdentifier(object)
        if var existing = sharedSideTable[objectKey] {
            existing.retainCount += 1
            sharedSideTable[objectKey] = existing
            sharedLock.unlock()
            return
        }

        let originalClassValue: AnyClass = object_getClass(object) ?? type(of: object)
        sharedSideTable[objectKey] = SideTableEntry(
            originalClass: originalClassValue,
            dynamicSubclass: dynamicSubclass,
            retainCount: 1
        )
        object_setClass(object, dynamicSubclass)

        sharedLock.unlock()

        // Attach sentinel outside the lock — associated-object setters take
        // their own locks internally and we don't want to nest.
        let sentinel = DynamicSubclassSentinel(trackedObjectIdentifier: objectKey)
        objc_setAssociatedObject(object, &sentinelAssociationKey, sentinel, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Decrement the per-object retain count; when it hits zero, restore the
    /// original isa (only if the current isa still matches the dynamic
    /// subclass — KVO/other layered swizzlers may have layered on top).
    public static func release(_ object: AnyObject) {
        sharedLock.lock()

        let objectKey = ObjectIdentifier(object)
        guard var entry = sharedSideTable[objectKey] else {
            sharedLock.unlock()
            return
        }

        entry.retainCount -= 1
        if entry.retainCount > 0 {
            sharedSideTable[objectKey] = entry
            sharedLock.unlock()
            return
        }

        let currentClass: AnyClass? = object_getClass(object)
        if currentClass === entry.dynamicSubclass {
            object_setClass(object, entry.originalClass)
        }
        sharedSideTable.removeValue(forKey: objectKey)
        sharedLock.unlock()

        objc_setAssociatedObject(object, &sentinelAssociationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    public static func isInstalled(on object: AnyObject) -> Bool {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        return sharedSideTable[ObjectIdentifier(object)] != nil
    }

    /// Returns the class the object had before any dynamic-subclass swizzling.
    /// Falls back to the current `object_getClass` reading when no entry is
    /// installed.
    public static func originalClass(of object: AnyObject) -> AnyClass {
        sharedLock.lock()
        if let entry = sharedSideTable[ObjectIdentifier(object)] {
            sharedLock.unlock()
            return entry.originalClass
        }
        sharedLock.unlock()
        return object_getClass(object) ?? type(of: object)
    }

    // MARK: - Override Registration

    /// Idempotently install instance-method overrides on the dynamic subclass.
    /// Already-installed selectors are left untouched (`class_addMethod`
    /// semantics). The type encoding is resolved in this order: caller-supplied
    /// `typeEncoding`, then the matching method on `referenceClass`, then the
    /// matching method on each `referenceProtocols` entry (required → optional),
    /// then a fallback `v24@0:8@16`.
    public static func addOverrides(
        on dynamicSubclass: AnyClass,
        referenceClass: AnyClass? = nil,
        referenceProtocols: [Protocol] = [],
        _ overrides: [Override]
    ) {
        for override in overrides {
            let encoding = resolveTypeEncoding(
                for: override.selector,
                explicitEncoding: override.typeEncoding,
                referenceClass: referenceClass,
                referenceProtocols: referenceProtocols
            )
            let imp = imp_implementationWithBlock(override.block)
            class_addMethod(dynamicSubclass, override.selector, imp, encoding)
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

    // MARK: - Super-Call Helpers

    /// Resolve the original class's IMP for `selector`. Macro-generated
    /// `callSuper(...)` thunks call this and `unsafeBitCast` the IMP to a
    /// `@convention(c)` function pointer with *concrete* argument and return
    /// types — the cast is kept at the expansion site because Swift refuses
    /// to form a `@convention(c)` type whose signature mentions a generic
    /// parameter (the importer can't prove representability for an unknown
    /// type). Hand-written call sites can use the same pattern.
    ///
    /// Crashes if the original class does not implement `selector`; for
    /// protocol methods that may not be implemented, use
    /// `resolveSuperImplementationIfAvailable(for:selector:)`.
    public static func resolveSuperImplementation(
        for instance: AnyObject,
        selector: Selector
    ) -> IMP {
        let originalClassValue: AnyClass = originalClass(of: instance)
        guard let method = class_getInstanceMethod(originalClassValue, selector) else {
            fatalError(
                "DynamicSubclass.resolveSuperImplementation: original class \(originalClassValue) does not implement \(selector); use resolveSuperImplementationIfAvailable for protocol methods that may not be implemented."
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
    }

    private static let sharedLock = NSLock()
    nonisolated(unsafe) private static var sharedSubclassCache: [String: AnyClass] = [:]
    nonisolated(unsafe) private static var sharedSideTable: [ObjectIdentifier: SideTableEntry] = [:]

    // MARK: - Internal Helpers

    /// Install `-class`, `-respondsToSelector:`, and `-conformsToProtocol:`
    /// overrides on a freshly-allocated dynamic subclass. The `-class` override
    /// powers the KVO illusion; the other two ensure introspection sees the
    /// real ISA's added members despite `-class` lying.
    private static func installBaselineOverrides(on dynamicSubclass: AnyClass) {
        let classOverride: @convention(block) (AnyObject) -> AnyClass = { instance in
            originalClass(of: instance)
        }
        let classImplementation = imp_implementationWithBlock(classOverride as AnyObject)
        class_addMethod(dynamicSubclass, NSSelectorFromString("class"), classImplementation, "#16@0:8")

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
        class_addMethod(dynamicSubclass, respondsSelector, respondsImplementation, "B24@0:8:16")

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
        class_addMethod(dynamicSubclass, conformsSelector, conformsImplementation, "B24@0:8@16")
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
        return "v24@0:8@16"
    }
}

// MARK: - Dealloc Sentinel

/// Associated-object sentinel: when the tracked object deallocates without an
/// explicit `release(_:)`, this sentinel cleans up its side-table entry.
private final class DynamicSubclassSentinel: NSObject {
    private let trackedObjectIdentifier: ObjectIdentifier
    init(trackedObjectIdentifier: ObjectIdentifier) {
        self.trackedObjectIdentifier = trackedObjectIdentifier
        super.init()
    }
    deinit {
        DynamicSubclass.cleanupSideTableEntry(for: trackedObjectIdentifier)
    }
}

private nonisolated(unsafe) var sentinelAssociationKey: UInt8 = 0

extension DynamicSubclass {
    fileprivate static func cleanupSideTableEntry(for trackedObjectIdentifier: ObjectIdentifier) {
        sharedLock.lock()
        sharedSideTable.removeValue(forKey: trackedObjectIdentifier)
        sharedLock.unlock()
    }
}

#endif
