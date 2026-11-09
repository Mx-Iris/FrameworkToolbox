#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Generates a typed, signature-checked caller for objects whose class is not
/// known up front, checked against the class of each object it wraps.
///
/// ## Overview
///
/// ``RuntimeClassProxy(_:)`` names one class and checks it once. Some objects
/// are only ever reached through other objects, and their class is whatever
/// the host decided — it differs between versions of the host, or between the
/// several classes that conform to one of its protocols. Attach
/// `@RuntimeObjectProxy` to a `protocol` describing the methods to call on
/// them:
///
/// ```swift
/// @RuntimeObjectProxy
/// protocol ApplicationUninstalling {
///     func uninstallabilityOfFileAtURL(_ url: NSURL) -> Int32?
///     func uninstallBundleAtURL(_ url: NSURL, handler: @escaping @convention(block) (ObjCBool) -> Void)
/// }
///
/// guard let uninstaller = ApplicationUninstallingImplementation(someObject) else { return }
/// uninstaller.uninstallBundleAtURL(bundleURL as NSURL) { hasUninstalled in }
/// ```
///
/// The peer `struct` generated, `<ProtocolName>Implementation`, derives each
/// selector and type encoding from the Swift declaration exactly as
/// ``RuntimeClassProxy(_:)`` does, and follows the same rules for optional
/// returns, ownership and blocks. Its `init?(_:)` checks every requirement
/// against the class of the object it is handed, the first time it meets that
/// class, and fails when one is missing or changed; the answer is kept per
/// class, so a class that does not match is logged once.
///
/// There is no class to send `+alloc` or a class method to, so `init?` and
/// `static` requirements are rejected at compile time — declare those in a
/// ``RuntimeClassProxy(_:)`` protocol. There is also no `isSupported` and no
/// `runtimeClassName`; `methodRequirements` lists what is checked.
@attached(peer, names: suffixed(Implementation))
public macro RuntimeObjectProxy() = #externalMacro(
    module: "ObjCRuntimeToolboxMacros",
    type: "RuntimeObjectProxyMacro"
)

#endif
