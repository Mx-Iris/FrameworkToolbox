#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// A class built at run time whose methods hand out exactly the references Objective-C's naming
/// conventions say they do.
///
/// Every block takes and returns raw pointers, so Swift's own reference counting never touches the
/// receiver or the result: what a test counts is the method's doing and the caller's, nothing else.
/// Give each test a class of its own — tests run in parallel, and a method added to a shared class
/// would leak into its neighbours.
struct ConventionalClass {
    enum InitializerOutcome {
        case returnsReceiver
        case returnsNil
        case returnsReplacement(NSObject)
    }

    let name: String
    let runtimeClass: NSObject.Type

    /// A class named `name` exactly, for a test that has to spell the name in a macro argument.
    /// Registering the same name twice traps, so keep one in a `static let`.
    init(name: String) {
        self.name = name
        guard let allocatedClass = objc_allocateClassPair(NSObject.self, name, 0) else {
            preconditionFailure("could not allocate class \(name)")
        }
        objc_registerClassPair(allocatedClass)
        runtimeClass = allocatedClass as! NSObject.Type
    }

    /// A class whose name starts with `uniqueName` and is made unique, for a test that only needs a
    /// class of its own.
    init(uniqueName: String) {
        self.init(name: "OwnershipTesting_\(uniqueName)_\(UUID().uuidString.filter { $0 != "-" })")
    }

    /// A fresh instance. Call before ``allocating(_:)``, which replaces `+alloc`.
    func makeInstance() -> NSObject {
        runtimeClass.init()
    }

    /// `+alloc` hands out `instance` with one reference for the caller, as the alloc family does.
    func allocating(_ instance: NSObject) {
        let unretainedInstance = Unmanaged.passUnretained(instance)
        let block: @convention(block) (UnsafeRawPointer) -> UnsafeMutableRawPointer = { _ in
            unretainedInstance.retain().toOpaque()
        }
        add(block as AnyObject, selectorName: "alloc", to: object_getClass(runtimeClass)!)
    }

    /// An instance method returning `result`: with one reference for the caller when `isRetained`, as
    /// the alloc, copy, mutableCopy and new families do, and none otherwise.
    func addMethod(_ selectorName: String, returning result: NSObject, isRetained: Bool) {
        let unretainedResult = Unmanaged.passUnretained(result)
        let block: @convention(block) (UnsafeRawPointer) -> UnsafeMutableRawPointer = { _ in
            isRetained ? unretainedResult.retain().toOpaque() : unretainedResult.toOpaque()
        }
        add(block as AnyObject, selectorName: selectorName, to: runtimeClass)
    }

    /// An init-family method: it consumes the reference to its receiver and returns one reference to
    /// what it hands back.
    func addInitializer(_ selectorName: String, outcome: InitializerOutcome) {
        let block: @convention(block) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
        switch outcome {
        case .returnsReceiver:
            // The reference it consumed is the one it hands back.
            block = { receiver in receiver }
        case .returnsNil:
            block = { receiver in
                Unmanaged<AnyObject>.fromOpaque(receiver).release()
                return nil
            }
        case .returnsReplacement(let replacement):
            let unretainedReplacement = Unmanaged.passUnretained(replacement)
            block = { receiver in
                Unmanaged<AnyObject>.fromOpaque(receiver).release()
                return unretainedReplacement.retain().toOpaque()
            }
        }
        add(block as AnyObject, selectorName: selectorName, to: runtimeClass)
    }

    private func add(_ block: AnyObject, selectorName: String, to targetClass: AnyClass) {
        let implementation = imp_implementationWithBlock(block)
        let isAdded = class_addMethod(targetClass, NSSelectorFromString(selectorName), implementation, "@@:")
        precondition(isAdded, "\(selectorName) already exists on \(NSStringFromClass(targetClass))")
    }
}

/// How each object's retain count moved across `call`, once whatever it autoreleased is gone: zero
/// when the call kept the conventions, negative for an over-release, positive for a leak.
///
/// Each object gets an extra reference for the duration, so that an over-release cannot deallocate it
/// out from under the test. That reference is given back only if the call did not already take it.
func retainCountChanges(of objects: [NSObject], across call: () -> Void) -> [Int] {
    let cushions = objects.map { Unmanaged.passRetained($0) }
    let countsBefore = objects.map { CFGetRetainCount($0) }
    autoreleasepool {
        call()
    }
    let countsAfter = objects.map { CFGetRetainCount($0) }
    for (index, cushion) in cushions.enumerated() where countsAfter[index] >= countsBefore[index] {
        cushion.release()
    }
    return zip(countsAfter, countsBefore).map { countAfter, countBefore in countAfter - countBefore }
}
#endif
