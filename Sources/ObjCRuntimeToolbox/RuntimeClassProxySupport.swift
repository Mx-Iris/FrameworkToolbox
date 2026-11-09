#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import os

/// Runtime half of ``RuntimeClassProxy(_:)``.
///
/// The generated proxy calls into this for the two things it must not
/// improvise: proving the host really has the methods with the signatures the
/// generated dispatch assumes, and resolving an implementation to call.
public enum RuntimeClassProxySupport {

    // MARK: Returning a type the macro could not classify

    /// Delivers the return value of a dispatch whose type the macro saw only as
    /// an unfamiliar name — a typealias, an imported enumeration, a class it
    /// has no entry for — and so could not tell an object from a scalar.
    ///
    /// The generated code passes both ways of reading the result, and the
    /// compiler picks this overload or the `AnyObject` one at the call site,
    /// where the type is concrete. Both closures are valid for every type
    /// Objective-C can return, and only the chosen one runs. This one reads
    /// the value straight out of the call.
    @inlinable
    public static func _returnValue<Value>(
        _ type: Value.Type,
        transfersOwnership: Bool,
        asObject: () -> Unmanaged<AnyObject>?,
        asValue: () -> Value
    ) -> Value? {
        asValue()
    }

    /// The object case: taken through `Unmanaged` so that a `nil` result and
    /// the `alloc` / `new` / `copy` / `mutableCopy` ownership rule are handled,
    /// exactly as for a type the macro recognizes as an object.
    @inlinable
    public static func _returnValue<Value: AnyObject>(
        _ type: Value.Type,
        transfersOwnership: Bool,
        asObject: () -> Unmanaged<AnyObject>?,
        asValue: () -> Value
    ) -> Value? {
        guard let unmanaged = asObject() else { return nil }
        let object = transfersOwnership ? unmanaged.takeRetainedValue() : unmanaged.takeUnretainedValue()
        return object as? Value
    }

    /// One method the proxy intends to call, with the signature it assumes.
    public struct MethodRequirement: Sendable {
        public let selector: Selector
        public let typeEncoding: String
        public let isInstanceMethod: Bool

        public init(selector: Selector, typeEncoding: String, isInstanceMethod: Bool = true) {
            self.selector = selector
            self.typeEncoding = typeEncoding
            self.isInstanceMethod = isInstanceMethod
        }
    }

    /// Whether the class exists in this process and every requirement matches.
    ///
    /// Checked once per proxy type, all or nothing: a proxy that works for some
    /// of its methods and silently misbehaves for the rest is worse than one
    /// that reports itself unusable. The first failing requirement is logged
    /// with both encodings, which is what turns "an operating-system update
    /// broke this" into a one-line diagnosis.
    public static func validate(
        className: String,
        requirements: [MethodRequirement],
        proxyTypeName: String
    ) -> Bool {
        guard let resolvedClass = objc_getClass(className) as? AnyClass else {
            os_log(
                .error,
                log: proxyLog,
                "%{public}@ disabled: class %{public}@ is not present in this process.",
                proxyTypeName,
                className
            )
            return false
        }
        return validate(resolvedClass, describedAs: className, requirements: requirements, proxyTypeName: proxyTypeName)
    }

    /// Whether the class of `host` has every requirement, for
    /// ``RuntimeObjectProxy()``: the same all-or-nothing check as
    /// ``validate(className:requirements:proxyTypeName:)``, made against each
    /// class a proxy is handed an instance of, once per class.
    ///
    /// The answer is kept per proxy type and class, so wrapping another
    /// instance of a class already seen costs a dictionary lookup, and a class
    /// that does not match is logged the first time only.
    public static func validate(
        classOf host: AnyObject,
        requirements: [MethodRequirement],
        proxyTypeName: String
    ) -> Bool {
        guard let hostClass = object_getClass(host) else { return false }
        let key = ValidatedClassKey(proxyTypeName: proxyTypeName, hostClass: ObjectIdentifier(hostClass))

        os_unfair_lock_lock(validationLock)
        let knownResult = validatedClasses[key]
        os_unfair_lock_unlock(validationLock)
        if let knownResult { return knownResult }

        // Checked outside the lock: looking a method up can run the class's
        // `+initialize`, which can run anything, this function included. Two
        // threads meeting a new class at once both check it, which costs no more
        // than a second log line.
        let isValid = validate(
            hostClass,
            describedAs: NSStringFromClass(hostClass),
            requirements: requirements,
            proxyTypeName: proxyTypeName
        )

        os_unfair_lock_lock(validationLock)
        validatedClasses[key] = isValid
        os_unfair_lock_unlock(validationLock)
        return isValid
    }

    private static func validate(
        _ resolvedClass: AnyClass,
        describedAs className: String,
        requirements: [MethodRequirement],
        proxyTypeName: String
    ) -> Bool {
        for requirement in requirements {
            let liveTypeEncoding = RuntimeMethodInspector.typeEncoding(
                forClass: resolvedClass,
                selector: requirement.selector,
                isInstanceMethod: requirement.isInstanceMethod
            )
            let methodName = (requirement.isInstanceMethod ? "" : "+") + NSStringFromSelector(requirement.selector)

            guard let liveTypeEncoding else {
                os_log(
                    .error,
                    log: proxyLog,
                    "%{public}@ disabled: %{public}@ does not implement %{public}@.",
                    proxyTypeName,
                    className,
                    methodName
                )
                return false
            }

            guard ObjCTypeEncodingNormalization.matches(requirement.typeEncoding, liveTypeEncoding) else {
                os_log(
                    .error,
                    log: proxyLog,
                    "%{public}@ disabled: %{public}@ %{public}@ signature changed — expected %{public}@, found %{public}@.",
                    proxyTypeName,
                    className,
                    methodName,
                    requirement.typeEncoding,
                    liveTypeEncoding
                )
                return false
            }
        }

        return true
    }

    private struct ValidatedClassKey: Hashable {
        let proxyTypeName: String
        let hostClass: ObjectIdentifier
    }

    // A lock of its own, allocated once so its address never moves, rather than
    // `OSAllocatedUnfairLock`, to stay within this package's macOS 10.15 floor.
    nonisolated(unsafe) private static let validationLock: UnsafeMutablePointer<os_unfair_lock_s> = {
        let lock = UnsafeMutablePointer<os_unfair_lock_s>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
        return lock
    }()

    nonisolated(unsafe) private static var validatedClasses: [ValidatedClassKey: Bool] = [:]

    // MARK: Constructing

    /// Allocates an instance of the named class and initialises it, for an
    /// `init?` requirement of ``RuntimeClassProxy(_:)``.
    ///
    /// `+alloc` hands out one reference; the initialiser takes that one over
    /// and hands back one of its own — to the same object, another one, or
    /// none when it returns nil, having released the receiver itself. Both
    /// change hands as raw pointers, so Swift's reference counting cannot add a
    /// retain or a release of its own in between; the result is taken over
    /// with `takeRetainedValue()`.
    ///
    /// The initialiser is looked up on the class of the object `+alloc`
    /// returned, as a message send would: a class cluster's `+alloc` can hand
    /// out an instance of another class. When it does, the initialiser's
    /// signature is checked again on that class.
    ///
    /// - Parameters:
    ///   - typeEncoding: The initialiser's encoding, as the macro derived it.
    ///   - initialising: Calls the initialiser's implementation with the
    ///     allocated receiver, and returns what it returned.
    /// - Returns: The initialised object, or `nil` when the class or the
    ///   initialiser is missing, the initialiser returned nil, or it returned an
    ///   object that is not an instance of the named class.
    public static func construct(
        className: String,
        initialiser selector: Selector,
        typeEncoding: String,
        proxyTypeName: String,
        initialising: (_ implementation: IMP, _ receiver: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    ) -> AnyObject? {
        guard let proxiedClass = runtimeClass(named: className),
              let allocatedInstance = allocate(proxiedClass)
        else {
            os_log(.error, log: proxyLog, "%{public}@ could not allocate an instance of %{public}@.", proxyTypeName, className)
            return nil
        }

        let allocatedReference = Unmanaged<AnyObject>.fromOpaque(allocatedInstance)
        let allocatedClass: AnyClass? = object_getClass(allocatedReference.takeUnretainedValue())
        guard let allocatedClass, let method = class_getInstanceMethod(allocatedClass, selector) else {
            allocatedReference.release()
            os_log(
                .error,
                log: proxyLog,
                "%{public}@ could not construct %{public}@: the instance +alloc returned does not implement %{public}@.",
                proxyTypeName,
                className,
                NSStringFromSelector(selector)
            )
            return nil
        }

        if ObjectIdentifier(allocatedClass) != ObjectIdentifier(proxiedClass) {
            let liveTypeEncoding = method_getTypeEncoding(method).map { String(cString: $0) }
            guard let liveTypeEncoding, ObjCTypeEncodingNormalization.matches(typeEncoding, liveTypeEncoding) else {
                allocatedReference.release()
                os_log(
                    .error,
                    log: proxyLog,
                    "%{public}@ could not construct %{public}@: +alloc returned an instance of %{public}@, whose %{public}@ is %{public}@, not %{public}@.",
                    proxyTypeName,
                    className,
                    NSStringFromClass(allocatedClass),
                    NSStringFromSelector(selector),
                    liveTypeEncoding ?? "missing",
                    typeEncoding
                )
                return nil
            }
        }

        guard let initialisedInstance = initialising(method_getImplementation(method), allocatedInstance) else {
            return nil
        }
        let constructed = Unmanaged<AnyObject>.fromOpaque(initialisedInstance).takeRetainedValue()

        // The proxy's methods were checked against the named class; an
        // initialiser that returned something else gets no proxy.
        guard isInstance(constructed, ofClassNamed: className) else {
            os_log(
                .error,
                log: proxyLog,
                "%{public}@ could not construct %{public}@: %{public}@ returned an instance of %{public}@.",
                proxyTypeName,
                className,
                NSStringFromSelector(selector),
                NSStringFromClass(type(of: constructed))
            )
            return nil
        }
        return constructed
    }

    /// `+alloc`, sent the way a message send would: through the class's own
    /// implementation, so a class that replaces it hands out what it chooses.
    private static func allocate(_ proxiedClass: AnyClass) -> UnsafeMutableRawPointer? {
        let allocSelector = NSSelectorFromString("alloc")
        guard let method = class_getClassMethod(proxiedClass, allocSelector) else { return nil }
        let allocateFunction = unsafeBitCast(
            method_getImplementation(method),
            to: (@convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?).self
        )
        return allocateFunction(proxiedClass, allocSelector)
    }

    /// Whether an object is an instance of the named class or a descendant.
    ///
    /// Guards the proxy's initialiser: the signature check proves the *class*
    /// matches, and this proves the object belongs to it. Without the second
    /// half, handing the proxy an unrelated object would marshal arguments into
    /// whatever that object's method table happens to point at.
    public static func isInstance(_ object: AnyObject, ofClassNamed className: String) -> Bool {
        guard let expectedClass = objc_getClass(className) as? AnyClass else { return false }
        var cursor: AnyClass? = object_getClass(object)
        while let current = cursor {
            if current === expectedClass { return true }
            cursor = class_getSuperclass(current)
        }
        return false
    }

    /// The implementation an object's real class provides for a selector.
    ///
    /// Resolved against `object_getClass` rather than the declared class so a
    /// subclass's override is the one that runs — which is what a normal
    /// message send would do. The signature contract still comes from the
    /// declared class, because an override that changed the signature would
    /// break Objective-C dispatch generally, not just this proxy.
    public static func implementation(of selector: Selector, on host: AnyObject) -> IMP? {
        guard let hostClass = object_getClass(host) else { return nil }
        guard let method = class_getInstanceMethod(hostClass, selector) else { return nil }
        return method_getImplementation(method)
    }

    /// The implementation a class provides for a class-method selector.
    public static func classMethodImplementation(of selector: Selector, onClassNamed className: String) -> IMP? {
        guard let resolvedClass = runtimeClass(named: className) else { return nil }
        return classMethodImplementation(of: selector, on: resolvedClass)
    }

    /// The implementation a class provides for a class-method selector, for a
    /// `static` requirement of ``RuntimeClassProxy(_:)``.
    public static func classMethodImplementation(of selector: Selector, on resolvedClass: AnyClass) -> IMP? {
        guard let method = class_getClassMethod(resolvedClass, selector) else { return nil }
        return method_getImplementation(method)
    }

    /// The class registered under `className` in this process, if any.
    public static func runtimeClass(named className: String) -> AnyClass? {
        objc_getClass(className) as? AnyClass
    }

    static let proxyLog = OSLog(subsystem: "ObjCRuntimeToolbox", category: "RuntimeClassProxy")
}

#endif
