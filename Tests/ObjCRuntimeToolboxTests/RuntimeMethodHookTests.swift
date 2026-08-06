#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
import XCTest
@testable import ObjCRuntimeToolbox

// MARK: - Targets
//
// Every scenario gets its own Objective-C class. Replacements installed by
// `RuntimeMethodHook` are process-wide and permanent by design — there is no
// uninstall — so sharing a class between tests would make them order-dependent.

@objc(RuntimeHookGreeter)
final class RuntimeHookGreeter: NSObject {
    @objc dynamic func greet() -> String { "Hello" }
}

@objc(RuntimeHookCounter)
final class RuntimeHookCounter: NSObject {
    @objc dynamic var total: Int = 0
    @objc dynamic func add(_ amount: Int) { total += amount }
}

@objc(RuntimeHookGate)
final class RuntimeHookGate: NSObject {
    @objc dynamic var lastPayload: NSString?
    @objc dynamic var lastFlag: Bool = false

    @objc dynamic func accept(_ payload: NSString?, urgent: Bool) {
        lastPayload = payload
        lastFlag = urgent
    }
}

@objc(RuntimeHookMismatch)
final class RuntimeHookMismatch: NSObject {
    @objc dynamic func configure(_ level: Int) {}
}

@objc(RuntimeHookAtomicity)
final class RuntimeHookAtomicity: NSObject {
    @objc dynamic func good() -> String { "original" }
    @objc dynamic func alsoTakesAnInteger(_ value: Int) {}
}

@objc(RuntimeHookDuplicate)
final class RuntimeHookDuplicate: NSObject {
    @objc dynamic func touch() {}
}

/// Separate from `RuntimeHookDuplicate` on purpose: the duplicate-in-batch
/// check has to be reached before the already-installed one, and installing
/// into a shared class would let whichever test ran first decide which failure
/// the other one sees.
@objc(RuntimeHookBatchDuplicate)
final class RuntimeHookBatchDuplicate: NSObject {
    @objc dynamic func touch() {}
}

// MARK: - Hooks

@RuntimeClassHook("RuntimeHookGreeter")
struct RuntimeHookGreeterReplacements {
    @RuntimeMethodReplacement
    func greet() -> String {
        callOriginal().uppercased() + "!"
    }
}

@RuntimeClassHook("RuntimeHookCounter")
struct RuntimeHookCounterReplacements {
    @RuntimeMethodReplacement
    func add(_ amount: Int) {
        // Doubling proves both that the argument arrived intact and that
        // forwarding reaches the original implementation.
        callOriginal(amount * 2)
    }
}

@RuntimeClassHook("RuntimeHookGate")
struct RuntimeHookGateReplacements {
    @RuntimeMethodReplacement
    func accept(_ payload: NSString?, urgent: Bool) {
        guard urgent else { return }   // drop non-urgent payloads entirely
        callOriginal("[urgent] \(payload ?? "")" as NSString, urgent)
    }
}

/// Declares `Bool` where the real method takes `Int`. This is exactly the
/// mistake the derived encoding exists to catch: the replacement block would be
/// called with an argument shaped differently from what it expects.
@RuntimeClassHook("RuntimeHookMismatch")
struct RuntimeHookMismatchReplacements {
    @RuntimeMethodReplacement
    func configure(_ level: Bool) {
        callOriginal(level)
    }
}

@RuntimeClassHook("RuntimeHookAtomicity")
struct RuntimeHookAtomicityReplacements {
    @RuntimeMethodReplacement
    func good() -> String {
        callOriginal() + " (replaced)"
    }

    /// Same deliberate mismatch, sitting in the same batch as a valid
    /// descriptor. Neither may install.
    @RuntimeMethodReplacement
    func alsoTakesAnInteger(_ value: Bool) {
        callOriginal(value)
    }
}

@RuntimeClassHook("RuntimeHookDuplicate")
struct RuntimeHookDuplicateReplacements {
    @RuntimeMethodReplacement
    func touch() {
        callOriginal()
    }
}

@RuntimeClassHook("RuntimeHookBatchDuplicate")
struct RuntimeHookBatchDuplicateReplacements {
    @RuntimeMethodReplacement
    func touch() {
        callOriginal()
    }
}

// MARK: - Tests

final class RuntimeMethodHookTests: XCTestCase {

    // MARK: Encoding derivation

    func testDerivedEncodingsMatchTheLiveMethods() {
        // The whole design rests on this: what the macro derived from the Swift
        // signature is what the runtime actually reports.
        assertDerivedEncodingMatchesLiveMethod(RuntimeHookGreeterReplacements.descriptors())
        assertDerivedEncodingMatchesLiveMethod(RuntimeHookCounterReplacements.descriptors())
        assertDerivedEncodingMatchesLiveMethod(RuntimeHookGateReplacements.descriptors())
    }

    private func assertDerivedEncodingMatchesLiveMethod(
        _ descriptors: [RuntimeMethodHook.Descriptor],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for descriptor in descriptors {
            let liveEncoding = RuntimeMethodInspector.typeEncoding(
                forClassNamed: descriptor.className,
                selector: descriptor.selector
            )
            XCTAssertNotNil(liveEncoding, "\(descriptor) is missing from the runtime", file: file, line: line)
            guard let liveEncoding else { continue }
            XCTAssertTrue(
                ObjCTypeEncodingNormalization.matches(descriptor.expectedTypeEncoding, liveEncoding),
                "\(descriptor): derived \(descriptor.expectedTypeEncoding), runtime reports \(liveEncoding)",
                file: file,
                line: line
            )
        }
    }

    func testDerivedEncodingsHaveTheExpectedShape() {
        let greetDescriptor = RuntimeHookGreeterReplacements.descriptors()[0]
        XCTAssertEqual(greetDescriptor.expectedTypeEncoding, "@@:")
        XCTAssertEqual(NSStringFromSelector(greetDescriptor.selector), "greet")

        let addDescriptor = RuntimeHookCounterReplacements.descriptors()[0]
        XCTAssertEqual(addDescriptor.expectedTypeEncoding, "v@:q")
        XCTAssertEqual(NSStringFromSelector(addDescriptor.selector), "add:")

        let acceptDescriptor = RuntimeHookGateReplacements.descriptors()[0]
        XCTAssertEqual(acceptDescriptor.expectedTypeEncoding, "v@:@B")
        XCTAssertEqual(NSStringFromSelector(acceptDescriptor.selector), "accept:urgent:")
    }

    // MARK: Installing and forwarding

    func testReplacementRunsAndCallOriginalReachesTheHost() throws {
        let greeter = RuntimeHookGreeter()
        XCTAssertEqual(greeter.greet(), "Hello")

        try RuntimeHookGreeterReplacements.install()

        // "HELLO!" proves both halves: the replacement ran (uppercase + "!")
        // and `callOriginal` produced the host's own "Hello".
        XCTAssertEqual(greeter.greet(), "HELLO!")
        XCTAssertTrue(RuntimeMethodHook.isInstalled(
            className: "RuntimeHookGreeter",
            selector: NSSelectorFromString("greet")
        ))
    }

    func testArgumentsSurviveTheRoundTrip() throws {
        let counter = RuntimeHookCounter()
        counter.add(5)
        XCTAssertEqual(counter.total, 5)

        try RuntimeHookCounterReplacements.install()

        counter.add(5)
        XCTAssertEqual(counter.total, 15, "the replacement should have doubled 5 before forwarding")
    }

    func testObjectAndBooleanArgumentsAreMarshalledCorrectly() throws {
        let gate = RuntimeHookGate()
        try RuntimeHookGateReplacements.install()

        gate.accept("ignored", urgent: false)
        XCTAssertNil(gate.lastPayload, "a non-urgent payload should have been dropped by the replacement")

        gate.accept("ping", urgent: true)
        XCTAssertEqual(gate.lastPayload, "[urgent] ping")
        XCTAssertTrue(gate.lastFlag)
    }

    // MARK: Refusing to install

    func testSignatureMismatchIsRefusedAndNothingChanges() {
        let target = RuntimeHookMismatch()
        // Establish the pre-install behaviour so we can prove it survived.
        target.configure(1)

        let result = RuntimeMethodHook.validate(RuntimeHookMismatchReplacements.descriptors())

        switch result {
        case .success:
            XCTFail("a Bool parameter against an NSInteger method must not validate")
        case .failure(let failure):
            guard case .typeEncodingMismatch(let className, let selectorName, let expected, let actual) = failure else {
                return XCTFail("expected a typeEncodingMismatch, got \(failure)")
            }
            XCTAssertEqual(className, "RuntimeHookMismatch")
            XCTAssertEqual(selectorName, "configure:")
            XCTAssertEqual(expected, "v@:B")
            XCTAssertTrue(
                ObjCTypeEncodingNormalization.normalized(actual).hasSuffix("q"),
                "the live method takes an NSInteger, so its encoding should end in 'q'; got \(actual)"
            )
        }

        XCTAssertThrowsError(try RuntimeHookMismatchReplacements.install())
        XCTAssertFalse(RuntimeMethodHook.isInstalled(
            className: "RuntimeHookMismatch",
            selector: NSSelectorFromString("configure:")
        ))
    }

    func testABadDescriptorPreventsTheWholeBatchFromInstalling() {
        let target = RuntimeHookAtomicity()
        XCTAssertEqual(target.good(), "original")

        XCTAssertThrowsError(try RuntimeHookAtomicityReplacements.install())

        // The valid descriptor sat in the same batch as the mismatched one.
        // A half-installed batch is the failure this design exists to prevent.
        XCTAssertEqual(target.good(), "original", "the valid descriptor must not have installed either")
        XCTAssertFalse(RuntimeMethodHook.isInstalled(
            className: "RuntimeHookAtomicity",
            selector: NSSelectorFromString("good")
        ))
    }

    func testMissingClassIsReported() {
        let descriptor = RuntimeMethodHook.Descriptor(
            className: "NoSuchClassExistsAnywhere",
            selector: NSSelectorFromString("whatever"),
            expectedTypeEncoding: "v@:",
            makeReplacement: { $0 }
        )

        guard case .failure(let failure) = RuntimeMethodHook.validate([descriptor]) else {
            return XCTFail("a missing class must not validate")
        }
        XCTAssertEqual(failure, .classNotFound(className: "NoSuchClassExistsAnywhere"))
    }

    func testMissingMethodIsReported() {
        let descriptor = RuntimeMethodHook.Descriptor(
            className: "RuntimeHookGreeter",
            selector: NSSelectorFromString("noSuchSelector"),
            expectedTypeEncoding: "v@:",
            makeReplacement: { $0 }
        )

        guard case .failure(let failure) = RuntimeMethodHook.validate([descriptor]) else {
            return XCTFail("a missing method must not validate")
        }
        XCTAssertEqual(
            failure,
            .methodNotFound(className: "RuntimeHookGreeter", selectorName: "noSuchSelector")
        )
    }

    func testTheSameMethodTwiceInOneBatchIsReported() {
        let descriptors = RuntimeHookBatchDuplicateReplacements.descriptors()
            + RuntimeHookBatchDuplicateReplacements.descriptors()

        guard case .failure(let failure) = RuntimeMethodHook.validate(descriptors) else {
            return XCTFail("a duplicated method must not validate")
        }
        XCTAssertEqual(
            failure,
            .duplicateInBatch(className: "RuntimeHookBatchDuplicate", selectorName: "touch")
        )
    }

    func testInstallingTwiceIsRefused() throws {
        try RuntimeHookDuplicateReplacements.install()

        // Installing again would chain the replacements: the second one's
        // "original" would be the first one's replacement.
        XCTAssertThrowsError(try RuntimeHookDuplicateReplacements.install()) { error in
            XCTAssertEqual(
                error as? RuntimeMethodHook.InstallationFailure,
                .alreadyInstalled(className: "RuntimeHookDuplicate", selectorName: "touch")
            )
        }
    }
}

// MARK: - Encoding Normalisation

final class ObjCTypeEncodingNormalizationTests: XCTestCase {

    func testFrameOffsetsAreIgnored() {
        XCTAssertTrue(ObjCTypeEncodingNormalization.matches("v@:@B", "v28@0:8@16B24"))
        XCTAssertTrue(ObjCTypeEncodingNormalization.matches("@@:", "@16@0:8"))
        XCTAssertTrue(ObjCTypeEncodingNormalization.matches("v@:@q", "v32@0:8@16q24"))
    }

    func testTheTwoSpellingsOfBoolAreEquivalent() {
        // arm64 reports `B`, x86_64 reports `c`, for the same `BOOL` parameter.
        XCTAssertTrue(ObjCTypeEncodingNormalization.matches("v@:B", "v@:c"))
        XCTAssertTrue(ObjCTypeEncodingNormalization.matches("B@:", "c@:"))
    }

    func testGenuinelyDifferentSignaturesDoNotMatch() {
        XCTAssertFalse(ObjCTypeEncodingNormalization.matches("v@:B", "v@:q"))
        XCTAssertFalse(ObjCTypeEncodingNormalization.matches("v@:", "v@:@"))
        XCTAssertFalse(ObjCTypeEncodingNormalization.matches("@@:", "v@:"))
        XCTAssertFalse(ObjCTypeEncodingNormalization.matches("v@:@@", "v@:@"))
    }
}

#endif
