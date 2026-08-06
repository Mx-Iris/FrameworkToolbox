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
        guard objc_getClass(className) != nil else {
            os_log(
                .error,
                log: proxyLog,
                "%{public}@ disabled: class %{public}@ is not present in this process.",
                proxyTypeName,
                className
            )
            return false
        }

        for requirement in requirements {
            let liveTypeEncoding = RuntimeMethodInspector.typeEncoding(
                forClassNamed: className,
                selector: requirement.selector,
                isInstanceMethod: requirement.isInstanceMethod
            )

            guard let liveTypeEncoding else {
                os_log(
                    .error,
                    log: proxyLog,
                    "%{public}@ disabled: %{public}@ does not implement %{public}@.",
                    proxyTypeName,
                    className,
                    NSStringFromSelector(requirement.selector)
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
                    NSStringFromSelector(requirement.selector),
                    requirement.typeEncoding,
                    liveTypeEncoding
                )
                return false
            }
        }

        return true
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
        guard let resolvedClass = objc_getClass(className) as? AnyClass else { return nil }
        guard let method = class_getClassMethod(resolvedClass, selector) else { return nil }
        return method_getImplementation(method)
    }

    static let proxyLog = OSLog(subsystem: "ObjCRuntimeToolbox", category: "RuntimeClassProxy")
}

#endif
