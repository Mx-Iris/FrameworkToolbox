//
//  Adapted from Dynamic by Mhd Hejazi (https://github.com/mhdhejazi/Dynamic),
//  distributed under the Apache License 2.0. See LICENSES/Dynamic-LICENSE.
//

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Reaches `NSInvocation` and `NSMethodSignature` from Swift.
///
/// Neither class is exposed to Swift — `NSInvocation` is outright unavailable
/// and `NSMethodSignature` has no usable Swift surface — so every call has to
/// be rebuilt by hand: look up the `IMP`, restate the signature as a
/// `@convention(c)` function type, and `unsafeBitCast` between them. Upstream
/// repeats that three-line dance at eight call sites. Collecting it here means
/// the `unsafeBitCast` calls, which are the only places a wrong signature turns
/// into memory corruption rather than a compile error, sit in one file and can
/// be reviewed against the headers as a set.
///
/// Every function assumes its receiver actually implements the selector, which
/// holds because each one is called on an object the runtime just handed back
/// for exactly this purpose.
enum NSInvocationBridge {

    // MARK: - Selectors

    private static let methodSignatureForSelectorSelector = NSSelectorFromString("methodSignatureForSelector:")
    private static let methodReturnTypeSelector = NSSelectorFromString("methodReturnType")
    private static let invocationWithMethodSignatureSelector = NSSelectorFromString("invocationWithMethodSignature:")
    private static let setSelectorSelector = NSSelectorFromString("setSelector:")
    private static let retainArgumentsSelector = NSSelectorFromString("retainArguments")
    private static let setArgumentAtIndexSelector = NSSelectorFromString("setArgument:atIndex:")
    private static let invokeWithTargetSelector = NSSelectorFromString("invokeWithTarget:")
    private static let getReturnValueSelector = NSSelectorFromString("getReturnValue:")

    // MARK: - Implementation Lookup

    /// Recovers a callable C function from a selector's implementation.
    ///
    /// - Warning: `signature` must match the method's real signature. A
    ///   mismatch is undefined behaviour, not a type error. In particular the
    ///   return type has to be C-compatible: an object return must be spelled
    ///   `AnyObject?`, which is a single `id`-sized pointer. `Any?` compiles
    ///   just as happily and is a 32-byte existential container, so the callee
    ///   returns a pointer where the caller reads a container — and the first
    ///   `objc_retain` of the garbage that lands there segfaults.
    @inline(__always)
    private static func implementation<CFunctionSignature>(
        of selector: Selector,
        on receiver: NSObject,
        as signature: CFunctionSignature.Type
    ) -> CFunctionSignature {
        unsafeBitCast(receiver.method(for: selector), to: signature)
    }

    // MARK: - NSMethodSignature

    /// `[target methodSignatureForSelector: selector]`
    ///
    /// - Returns: `nil` when the receiver does not implement the selector,
    ///   which is how an unrecognised selector is detected before sending it.
    static func methodSignature(forSelector selector: Selector, on target: NSObject) -> NSObject? {
        let call = implementation(
            of: methodSignatureForSelectorSelector,
            on: target,
            as: (@convention(c) (NSObject, Selector, Selector) -> AnyObject?).self
        )
        return call(target, methodSignatureForSelectorSelector, selector) as? NSObject
    }

    /// `methodSignature.numberOfArguments`
    ///
    /// Counts the two implicit arguments (`self` and `_cmd`) that precede the
    /// declared ones.
    static func numberOfArguments(of methodSignature: NSObject) -> Int {
        methodSignature.value(forKeyPath: "numberOfArguments") as? Int ?? 0
    }

    /// `methodSignature.methodReturnLength`
    static func returnLength(of methodSignature: NSObject) -> Int {
        methodSignature.value(forKeyPath: "methodReturnLength") as? Int ?? 0
    }

    /// `methodSignature.methodReturnType`
    ///
    /// The returned buffer is owned by the signature object, so it stays valid
    /// only as long as that object does.
    static func returnType(of methodSignature: NSObject) -> UnsafePointer<CChar> {
        let call = implementation(
            of: methodReturnTypeSelector,
            on: methodSignature,
            as: (@convention(c) (NSObject, Selector) -> UnsafePointer<CChar>).self
        )
        return call(methodSignature, methodReturnTypeSelector)
    }

    // MARK: - NSInvocation

    /// `[NSInvocation invocationWithMethodSignature: methodSignature]`
    ///
    /// This one is a *class* method, so its implementation comes from
    /// `class_getClassMethod` rather than from ``implementation(of:on:as:)`` —
    /// that helper takes an `NSObject` receiver, and getting a class object to
    /// pose as one means an `unsafeBitCast` whose result ARC then tries to
    /// retain. Asking the runtime directly skips the round trip entirely.
    static func makeInvocation(withMethodSignature methodSignature: NSObject) -> NSObject? {
        guard let invocationClass = NSClassFromString("NSInvocation"),
              let classMethod = class_getClassMethod(
                  invocationClass,
                  invocationWithMethodSignatureSelector
              )
        else {
            return nil
        }

        let call = unsafeBitCast(
            method_getImplementation(classMethod),
            to: (@convention(c) (AnyObject, Selector, NSObject) -> AnyObject?).self
        )
        return call(
            invocationClass as AnyObject,
            invocationWithMethodSignatureSelector,
            methodSignature
        ) as? NSObject
    }

    /// `invocation.selector = selector`
    static func setSelector(_ selector: Selector, on invocation: NSObject) {
        let call = implementation(
            of: setSelectorSelector,
            on: invocation,
            as: (@convention(c) (NSObject, Selector, Selector) -> Void).self
        )
        call(invocation, setSelectorSelector, selector)
    }

    /// `[invocation retainArguments]`
    ///
    /// Without this the invocation keeps unretained argument pointers, which
    /// outlive nothing: the temporaries holding them are gone by the time the
    /// message is actually sent.
    static func retainArguments(on invocation: NSObject) {
        let call = implementation(
            of: retainArgumentsSelector,
            on: invocation,
            as: (@convention(c) (NSObject, Selector) -> Void).self
        )
        call(invocation, retainArgumentsSelector)
    }

    /// `[invocation setArgument: pointer atIndex: index]`
    static func setArgument(
        _ pointer: UnsafeRawPointer,
        atIndex index: Int,
        on invocation: NSObject
    ) {
        let call = implementation(
            of: setArgumentAtIndexSelector,
            on: invocation,
            as: (@convention(c) (NSObject, Selector, UnsafeRawPointer, Int) -> Void).self
        )
        call(invocation, setArgumentAtIndexSelector, pointer, index)
    }

    /// `[invocation invokeWithTarget: target]`
    static func invoke(_ invocation: NSObject, withTarget target: NSObject) {
        let call = implementation(
            of: invokeWithTargetSelector,
            on: invocation,
            as: (@convention(c) (NSObject, Selector, NSObject) -> Void).self
        )
        call(invocation, invokeWithTargetSelector, target)
    }

    /// `[invocation getReturnValue: pointer]`
    ///
    /// - Warning: `pointer` must address at least `returnLength(of:)` bytes.
    static func getReturnValue(into pointer: UnsafeMutableRawPointer, from invocation: NSObject) {
        let call = implementation(
            of: getReturnValueSelector,
            on: invocation,
            as: (@convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Void).self
        )
        call(invocation, getReturnValueSelector, pointer)
    }
}

#endif
