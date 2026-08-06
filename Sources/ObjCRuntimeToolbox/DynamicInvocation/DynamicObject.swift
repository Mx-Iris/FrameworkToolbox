//
//  Adapted from Dynamic by Mhd Hejazi (https://github.com/mhdhejazi/Dynamic),
//  distributed under the Apache License 2.0. See LICENSES/Dynamic-LICENSE.
//

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import OSToolbox

/// Shorthand for ``DynamicObject``, so class names read as if they were
/// namespaced: `ObjC.NSDateFormatter()`.
public typealias ObjC = DynamicObject

/// Calls Objective-C classes and methods that Swift cannot see.
///
/// The rest of this module hooks, replaces, and subclasses methods whose
/// signatures you already know. This is the other half: reaching a class or
/// method that has no header at all, by name, with no bridging declarations to
/// write.
///
/// ```swift
/// let formatter = ObjC.NSDateFormatter()
/// formatter.dateFormat = "yyyy-MM-dd"
/// let text: String? = formatter.stringFromDate(Date())
/// ```
///
/// ## How a call is assembled
///
/// `@dynamicMemberLookup` turns each member access into a wrapped receiver plus
/// a pending member name, and `@dynamicCallable` turns the call that follows
/// into a selector. Argument labels become selector components: the first label
/// is capitalised and appended, the rest are appended verbatim, each followed by
/// a colon. So all three of these send `stringFromDate:`:
///
/// ```swift
/// formatter.stringFromDate(date)
/// formatter.stringFrom(date: date)
/// formatter.string(fromDate: date)
/// ```
///
/// The message itself goes out through `NSInvocation`, because it is the only
/// mechanism that takes a method signature as *data* — see
/// ``RuntimeInvocation``.
///
/// ## Reading results
///
/// A call returns another ``DynamicObject``. Unwrap it either by annotating the
/// destination, which selects the generic `subscript`/`dynamicallyCall`
/// overload, or with one of the explicit accessors:
///
/// ```swift
/// let count: Int? = ObjC.NSProcessInfo.processInfo.processorCount
/// let same = ObjC.NSProcessInfo.processInfo.processorCount.asInt
/// ```
///
/// ## Errors do not throw, they propagate
///
/// An unrecognised selector is recorded on the wrapper and every subsequent
/// member access and call on it is a no-op returning the same wrapper, so a long
/// chain fails at its first bad link without trapping. Check ``isError`` — or
/// let the unwrapped value come back `nil`.
///
/// ## Limits worth knowing before you hit them
///
/// - **Arguments larger than three machine words must be wrapped in an
///   `NSValue`.** Swift stores a small value inline inside an `Any`, and this
///   code passes the address of that storage; a larger value is boxed on the
///   heap instead, so what the callee would receive is the box pointer rather
///   than the value. A three-`Int` struct is fine, a `CGRect` is not.
/// - **The members declared here shadow Objective-C ones of the same name.**
///   `isError`, `debugDescription`, and every `as…` accessor cannot be
///   forwarded. Reach those through `ObjC(object).perform…` style calls or a
///   different name.
/// - **Not thread-safe.** An instance accumulates state across a chain, and the
///   messages themselves are as thread-safe as the receiver is.
///
/// ## Tracing what actually got sent
///
/// Every wrap, member read, and message send logs at `debug` level, which the
/// system neither persists nor formats until asked. That replaces upstream's
/// `loggingEnabled` flag: rather than recompiling with tracing switched on,
/// stream it out of a running process.
///
/// ```console
/// log stream --predicate 'subsystem == "ObjCRuntimeToolbox"' --level debug
/// ```
///
/// ``RuntimeInvocation`` logs to the same subsystem and category, so one
/// predicate covers the whole path from member access to return value.
///
/// > Note: `@Loggable` emits its members `private`, and private members are
/// > excluded from the member lookup that `@dynamicMemberLookup` falls back
/// > from. So `logger`, `_osLog`, `subsystem`, and `category` stay forwardable
/// > to Objective-C from outside this type, while `#log` still resolves
/// > `Self.logger` inside it.
@Loggable(subsystem: "ObjCRuntimeToolbox", category: "DynamicInvocation")
@dynamicCallable
@dynamicMemberLookup
public class DynamicObject: CustomDebugStringConvertible {

    /// The wrapped `nil`, on which every member access and call is a no-op that
    /// returns this same instance.
    ///
    /// Sharing one instance is safe precisely because it wraps `nil`: every
    /// path that would mutate a wrapper checks the wrapped object first and
    /// bails out, so this one is never written to.
    public nonisolated(unsafe) static let `nil` = DynamicObject(nil)

    // Readable across the module — the unwrapping accessors live in their own
    // file — but writable only here, where the invariants are maintained.
    // Module-internal visibility is safe for `@dynamicMemberLookup` shadowing
    // purposes because nothing inside this module looks members up dynamically.
    let object: AnyObject?
    let memberName: String?
    private(set) var invocation: RuntimeInvocation?
    private(set) var error: (any Error)?

    /// Whether this wrapper is carrying a failure, either its own or one
    /// handed to it by an earlier link in the chain.
    public var isError: Bool { error != nil || object is any Error }

    public var debugDescription: String { object?.debugDescription ?? "<nil>" }

    public init(_ object: Any?, memberName: String? = nil) {
        self.object = object as AnyObject?
        self.memberName = memberName

        #log(.debug, "wrap object \(String(describing: object ?? "<nil>")) member \(memberName ?? "<none>", privacy: .public)")
    }

    /// Wraps the class registered under `className`, or `nil` if the runtime
    /// has no such class in this process.
    public init(className: String) {
        self.object = NSClassFromString(className)
        self.memberName = nil

        #log(.debug, "wrap class \(className, privacy: .public)")
    }

    // MARK: - Member Lookup

    public static subscript(dynamicMember className: String) -> DynamicObject {
        DynamicObject(className: className)
    }

    public subscript(dynamicMember memberName: String) -> DynamicObject {
        get { property(named: memberName) }
        set { self[dynamicMember: memberName] = newValue.resolve() }
    }

    public subscript<Unwrapped>(dynamicMember memberName: String) -> Unwrapped? {
        get { self[dynamicMember: memberName].unwrap() }
        set { setProperty(named: memberName, to: newValue) }
    }

    // MARK: - Calling

    @discardableResult
    public func dynamicallyCall(
        withKeywordArguments keywordArguments: KeyValuePairs<String, Any?>
    ) -> DynamicObject {
        // Calling a bare class means constructing: `ObjC.NSUUID()` is
        // `[[NSUUID alloc] init]`, and `ObjC.NSUUID(UUIDString: text)` is
        // `[[NSUUID alloc] initWithUUIDString: text]`.
        if object is AnyClass, memberName == nil {
            if keywordArguments.isEmpty {
                return self.`init`.dynamicallyCall(withKeywordArguments: keywordArguments)
            } else {
                return self.initWith.dynamicallyCall(withKeywordArguments: keywordArguments)
            }
        }

        guard let memberName else { return self }

        // Argument labels rebuild the selector: the first is capitalised and
        // joined onto the member name, the rest are appended as written.
        let selectorName = memberName + keywordArguments.reduce("") { partialSelector, argument in
            if partialSelector.isEmpty {
                (argument.key.first?.uppercased() ?? "") + argument.key.dropFirst() + ":"
            } else {
                partialSelector + argument.key + ":"
            }
        }

        callMethod(named: selectorName, with: keywordArguments.map(\.value))
        return self
    }

    @discardableResult
    public func dynamicallyCall<Unwrapped>(
        withKeywordArguments keywordArguments: KeyValuePairs<String, Any?>
    ) -> Unwrapped? {
        let result: DynamicObject = dynamicallyCall(withKeywordArguments: keywordArguments)
        return result.unwrap()
    }

    // MARK: - Properties

    private func property(named propertyName: String) -> DynamicObject {
        #log(.debug, "get \(self.debugDescription).\(propertyName, privacy: .public)")

        let resolved = resolve()

        // A failed link swallows the rest of the chain rather than trapping.
        if resolved is any Error { return self }
        if resolved == nil { return Self.nil }

        return DynamicObject(resolved, memberName: propertyName)
    }

    private func setProperty<Value>(named propertyName: String, to value: Value?) {
        let setterName = Self.setterName(forProperty: propertyName)
        #log(.debug, "set \(self.debugDescription).\(propertyName, privacy: .public) via \(setterName, privacy: .public)")

        let resolved = resolve()
        DynamicObject(resolved, memberName: setterName)(value)
    }

    /// The setter matching a property name, following Objective-C convention.
    ///
    /// A leading `is` on a Boolean getter is dropped, so `isSuspended` is
    /// written through `setSuspended:` rather than `setIsSuspended:`.
    private static func setterName(forProperty propertyName: String) -> String {
        if propertyName.count > 2,
           propertyName.hasPrefix("is"),
           propertyName[propertyName.index(propertyName.startIndex, offsetBy: 2)].isUppercase {
            "set" + propertyName.dropFirst(2)
        } else {
            "set" + (propertyName.first?.uppercased() ?? "") + propertyName.dropFirst()
        }
    }

    // MARK: - Message Sending

    private func callMethod(named selectorName: String, with arguments: [Any?] = []) {
        guard var target = object as? NSObject, !isError else { return }

        #log(.debug, "call [\(String(describing: type(of: target)), privacy: .public) \(selectorName, privacy: .public)]")

        // `init` has to be preceded by `alloc`, since the class object cannot
        // receive it directly.
        if target is AnyClass, selectorName.hasPrefix("init") {
            guard let allocatedInstance = allocateInstance(ofClass: target) else { return }
            target = allocatedInstance
        }

        let invocation: RuntimeInvocation
        do {
            invocation = try RuntimeInvocation(
                target: target,
                selector: NSSelectorFromString(selectorName)
            )
        } catch {
            self.error = error
            return
        }

        // The selector's colon count and the supplied argument count can
        // disagree — reading a property whose getter actually takes arguments
        // is the usual way in. Writing the arguments anyway would read past the
        // end of the array, so refuse the call instead.
        let expectedCount = invocation.numberOfDeclaredArguments
        guard arguments.count >= expectedCount else {
            #log(
                .error,
                "'\(selectorName, privacy: .public)' takes \(expectedCount) argument(s) but \(arguments.count) were provided"
            )
            self.error = RuntimeInvocationError.argumentCountMismatch(
                selectorName: selectorName,
                expectedCount: expectedCount,
                providedCount: arguments.count
            )
            return
        }

        self.invocation = invocation

        for argumentIndex in 0 ..< expectedCount {
            var argument = arguments[argumentIndex]

            // A wrapper passed as an argument stands for the object it holds.
            if let wrappedArgument = argument as? DynamicObject {
                argument = wrappedArgument.asObject
            }

            argument = FoundationTypeBridging.bridgedToObjectiveC(argument) ?? argument

            // Index 0 and 1 are the implicit `self` and `_cmd`.
            invocation.setArgument(argument, atIndex: argumentIndex + 2)
        }

        invocation.invoke()
    }

    private func allocateInstance(ofClass classObject: NSObject) -> NSObject? {
        do {
            let allocation = try RuntimeInvocation(
                target: classObject,
                selector: NSSelectorFromString("alloc")
            )
            allocation.invoke()
            return allocation.returnedObject as? NSObject
        } catch {
            self.error = error
            return nil
        }
    }

    /// Collapses this wrapper to the object it stands for, sending the pending
    /// member's message if one has not been sent yet.
    func resolve() -> AnyObject? {
        // A bare class stands for itself.
        if object is AnyClass, memberName == nil {
            return object
        }

        guard let object else { return nil }

        // A message already sent stands for its result.
        if let result = invocation?.returnedObject {
            return result
        }

        // A failure stands for itself, however it arrived.
        if object is any Error { return object }
        if let error { return error as AnyObject }

        // A plain wrapped object with nothing pending stands for itself.
        guard let memberName else { return object }

        // Otherwise the pending member still has to be read.
        if invocation?.isInvoked != true {
            callMethod(named: memberName)
        }

        return invocation?.returnedObject ?? error as AnyObject?
    }

    @available(*, unavailable, message: "Call init() directly from the class name.")
    public func alloc() {}
}

#endif
