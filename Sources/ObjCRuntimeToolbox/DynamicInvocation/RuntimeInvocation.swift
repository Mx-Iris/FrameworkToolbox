//
//  Adapted from Dynamic by Mhd Hejazi (https://github.com/mhdhejazi/Dynamic),
//  distributed under the Apache License 2.0. See LICENSES/Dynamic-LICENSE.
//

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import os

/// One message send, built through `NSInvocation`.
///
/// `NSInvocation` is the only general-purpose way to call a method whose
/// signature is unknown at compile time: `objc_msgSend` has to be cast to the
/// exact signature before it can be called, whereas `NSInvocation` takes the
/// signature as data. The cost is that `NSInvocation` itself is unavailable to
/// Swift, so reaching it goes through ``NSInvocationBridge``.
///
/// Instances are not thread-safe and are not meant to be — an `NSInvocation`
/// is single-use state that is configured, sent, and read on one thread.
///
/// Logs to the same subsystem and category as ``DynamicObject``, so one
/// `log stream` predicate covers member access through return value.
final class RuntimeInvocation {
    private let target: NSObject
    private let selector: Selector
    private let invocation: NSObject

    /// Total argument count, including the implicit `self` and `_cmd`.
    let numberOfArguments: Int

    /// Argument count excluding the implicit `self` and `_cmd`, i.e. how many
    /// values a caller is expected to supply.
    var numberOfDeclaredArguments: Int { max(numberOfArguments - 2, 0) }

    let returnLength: Int

    /// The return type's Objective-C encoding.
    ///
    /// Held as a `String` rather than the `UnsafePointer<CChar>` the runtime
    /// vends, because that pointer belongs to the `NSMethodSignature` object
    /// and stays valid only as long as it does. Owning the bytes removes the
    /// question entirely; the few places that need a C string produce one on
    /// demand via ``withReturnTypeCString(_:)``.
    let returnTypeEncoding: String

    /// `@` is the encoding for an object.
    var returnsObject: Bool { returnTypeEncoding == "@" }

    /// `v` is the encoding for `Void`.
    var returnsValue: Bool { returnTypeEncoding != "v" }

    private(set) var isInvoked = false

    private var cachedReturnedObject: AnyObject?
    private var hasResolvedReturnedObject = false

    init(target: NSObject, selector: Selector) throws(RuntimeInvocationError) {
        self.target = target
        self.selector = selector

        let className = String(describing: type(of: target))
        let selectorName = NSStringFromSelector(selector)

        // A nil signature is how an unrecognised selector shows up. Detecting
        // it here is what keeps a bad member name from becoming a
        // doesNotRecognizeSelector: crash later.
        guard let methodSignature = NSInvocationBridge.methodSignature(forSelector: selector, on: target) else {
            os_log(.error, log: dynamicInvocationLog, "'%{public}@' does not recognize selector '%{public}@'", className, selectorName)
            throw .unrecognizedSelector(className: className, selectorName: selectorName)
        }

        self.numberOfArguments = NSInvocationBridge.numberOfArguments(of: methodSignature)
        self.returnLength = NSInvocationBridge.returnLength(of: methodSignature)
        self.returnTypeEncoding = String(cString: NSInvocationBridge.returnType(of: methodSignature))

        guard let invocation = NSInvocationBridge.makeInvocation(withMethodSignature: methodSignature) else {
            throw .invocationCreationFailed(className: className, selectorName: selectorName)
        }
        self.invocation = invocation

        NSInvocationBridge.setSelector(selector, on: invocation)
        NSInvocationBridge.retainArguments(on: invocation)
    }

    /// Runs `body` with a C string of ``returnTypeEncoding``.
    ///
    /// The pointer is valid only for the duration of the call.
    func withReturnTypeCString<Result>(_ body: (UnsafePointer<CChar>) -> Result) -> Result {
        returnTypeEncoding.withCString(body)
    }

    /// What the declared return type occupies in memory, per its encoding.
    ///
    /// This is the encoding's own answer, which is not always ``returnLength``:
    /// the runtime rounds that up to the register width for small returns.
    var returnTypeLayout: (size: Int, alignment: Int) {
        withReturnTypeCString { returnTypeCString in
            var size = 0
            var alignment = 0
            NSGetSizeAndAlignment(returnTypeCString, &size, &alignment)
            return (size, alignment)
        }
    }

    // MARK: - Arguments

    /// Writes one argument into the invocation.
    ///
    /// - Parameter index: The invocation-relative index, so the first declared
    ///   argument is `2`.
    func setArgument(_ argument: Any?, atIndex index: Int) {
        os_log(.debug, log: dynamicInvocationLog, "argument #%ld = %@", index - 1, String(describing: argument ?? "<nil>"))

        if let boxedValue = argument as? NSValue {
            // An NSValue carries its own payload and encoding, so the bytes it
            // wraps — not the box — are what the callee expects.
            var valueSize = 0
            var valueAlignment = 0
            NSGetSizeAndAlignment(boxedValue.objCType, &valueSize, &valueAlignment)

            withUnsafeTemporaryAllocation(
                byteCount: max(valueSize, 1),
                alignment: max(valueAlignment, 1)
            ) { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                boxedValue.getValue(baseAddress, size: valueSize)
                NSInvocationBridge.setArgument(baseAddress, atIndex: index, on: invocation)
            }
        } else {
            // For everything else the address of the `Any?` doubles as the
            // address of the payload: Swift stores a value of three words or
            // fewer inline at the front of the existential container, and both
            // object references and the primitive types are one word. Values
            // larger than that are boxed elsewhere, which is why callers must
            // wrap big structs in an `NSValue` — see the note on
            // ``DynamicObject``.
            withUnsafePointer(to: argument) { pointer in
                NSInvocationBridge.setArgument(pointer, atIndex: index, on: invocation)
            }
        }
    }

    // MARK: - Sending

    func invoke() {
        guard !isInvoked else { return }
        isInvoked = true
        NSInvocationBridge.invoke(invocation, withTarget: target)
    }

    /// Copies the raw return value into `result`.
    ///
    /// - Warning: `ReturnValue` must be layout-compatible with the method's
    ///   declared return type; the runtime copies ``returnLength`` bytes either
    ///   way.
    func getReturnValue<ReturnValue>(into result: inout ReturnValue) {
        withUnsafeMutablePointer(to: &result) { pointer in
            NSInvocationBridge.getReturnValue(into: pointer, from: invocation)
        }
    }

    /// Copies the raw return value into an untyped buffer.
    ///
    /// - Warning: `buffer` must address at least ``returnLength`` bytes.
    func getReturnValue(intoRawBuffer buffer: UnsafeMutableRawPointer) {
        NSInvocationBridge.getReturnValue(into: buffer, from: invocation)
    }

    /// The returned object, read once and cached.
    ///
    /// `nil` before the message is sent, and for methods that do not return an
    /// object.
    var returnedObject: AnyObject? {
        guard isInvoked else { return nil }
        if hasResolvedReturnedObject { return cachedReturnedObject }
        hasResolvedReturnedObject = true
        cachedReturnedObject = resolveReturnedObject()
        return cachedReturnedObject
    }

    private func resolveReturnedObject() -> AnyObject? {
        guard returnsObject, returnLength > 0 else { return nil }

        var result: AnyObject?
        getReturnValue(into: &result)

        guard let object = result else { return nil }

        // The ternary matters: `alloc` hands back memory that is not an
        // initialised object yet, so asking it to describe itself would send a
        // message it cannot answer. Only the chosen branch is evaluated.
        os_log(
            .debug,
            log: dynamicInvocationLog,
            "[%{public}@] returned %@",
            NSStringFromSelector(selector),
            isAllocating ? "<allocated instance>" : String(describing: object)
        )

        if isRetainingMethod {
            // The method already handed us a +1 reference; take ownership of it
            // so the object is released exactly once.
            return Unmanaged.passRetained(object).takeRetainedValue()
        }

        // `getReturnValue:` does not transfer ownership, but the compiler emits
        // a release for the value it just saw materialise. Retaining here
        // balances that release.
        return Unmanaged.passRetained(object).takeUnretainedValue()
    }

    /// Whether the selector returns a +1 reference under ARC's naming rules.
    ///
    /// See the Objective-C memory management conventions: methods in the
    /// `alloc` / `new` / `copy` / `mutableCopy` families return an owned
    /// reference, everything else returns an autoreleased one.
    private var isRetainingMethod: Bool {
        let selectorName = NSStringFromSelector(selector)
        return selectorName == "alloc"
            || selectorName.hasPrefix("new")
            || selectorName.hasPrefix("copy")
            || selectorName.hasPrefix("mutableCopy")
    }

    /// `alloc` returns an object that is not yet initialised, so describing it
    /// would send it a message it cannot answer.
    private var isAllocating: Bool {
        NSStringFromSelector(selector) == "alloc"
    }
}

#endif
