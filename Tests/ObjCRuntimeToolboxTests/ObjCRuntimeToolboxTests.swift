#if canImport(ObjectiveC)
import Foundation
import XCTest
@testable import ObjCRuntimeToolbox

// MARK: - Scenario 1 — Greet with override + super (return value, 0 args)

@objc(GreeterScenario1)
final class Greeter: NSObject {
    @objc dynamic func greet() -> String { "Hello" }
}

@DynamicSubclassHook(of: Greeter.self, suffix: "Loud")
struct LoudGreeterHook {
    @DynamicSubclassOverride
    func greet() -> String {
        let originalGreeting = callSuper()
        return originalGreeting.uppercased() + "!"
    }
}

// MARK: - Scenario 2 — Multi-arity returning value (2 args + return)

@objc(FormatterScenario2)
final class Formatter: NSObject {
    @objc dynamic func format(_ name: String, age: Int) -> String {
        "\(name) is \(age)"
    }
}

@DynamicSubclassHook(of: Formatter.self, suffix: "Capitalized")
struct CapitalizedFormatterHook {
    @DynamicSubclassOverride
    func format(_ name: String, age: Int) -> String {
        let originalDescription = callSuper(name, age)
        return originalDescription.uppercased()
    }
}

// MARK: - Scenario 3 — Multi-arity void (2 args, side-effect)

@objc(NotificationLoggerScenario3)
final class NotificationLogger: NSObject {
    @objc dynamic var lastMessage: String = ""
    @objc dynamic var lastLevel: Int = 0

    @objc dynamic func log(_ message: String, level: Int) {
        lastMessage = message
        lastLevel = level
    }
}

@DynamicSubclassHook(of: NotificationLogger.self, suffix: "Prefixed")
struct PrefixedLoggerHook {
    @DynamicSubclassOverride
    func log(_ message: String, level: Int) {
        callSuper("[hooked] " + message, level)
    }
}

// MARK: - Scenario 4 — Protocol adoption + callSuperIfImplemented falling back to default

@objc(GreetableScenario4)
protocol Greetable {
    func greetingPrefix() -> String
}

@objc(BareSpeakerScenario4)
final class BareSpeaker: NSObject {
    // Intentionally does NOT declare Greetable conformance.
    @objc dynamic func speak() -> String { "hello" }
}

@DynamicSubclassHook(of: BareSpeaker.self, suffix: "Polite", adopts: [Greetable.self])
struct PoliteSpeakerHook {
    @DynamicSubclassOverride
    func greetingPrefix() -> String {
        // BareSpeaker has no greetingPrefix IMP — `callSuperIfImplemented`
        // takes the default branch.
        return callSuperIfImplemented(default: "Mx. ")
    }
}

// MARK: - Scenario 5 — callSuperIfImplemented dispatching through super

@DynamicSubclassHook(of: BareSpeaker.self, suffix: "Logging")
struct LoggingSpeakerHook {
    @DynamicSubclassOverride
    func speak() -> String {
        // `speak` exists on BareSpeaker — `callSuperIfImplemented` dispatches.
        let originalUtterance = callSuperIfImplemented(default: "<no impl>")
        return "[log] " + originalUtterance
    }
}

// MARK: - Scenario 6 — shared suffix composes overrides from two hooks

@objc(SharedSuffixHostScenario6)
final class SharedSuffixHost: NSObject {
    @objc dynamic func operationA() -> String { "A" }
    @objc dynamic func operationB() -> String { "B" }
}

@DynamicSubclassHook(of: SharedSuffixHost.self, suffix: "Composed")
struct ComposedAHook {
    @DynamicSubclassOverride
    func operationA() -> String { "[A] " + callSuper() }
}

@DynamicSubclassHook(of: SharedSuffixHost.self, suffix: "Composed")
struct ComposedBHook {
    @DynamicSubclassOverride
    func operationB() -> String { "[B] " + callSuper() }
}

// MARK: - Scenario 7 — untagged helper method must not be registered

@DynamicSubclassHook(of: Greeter.self, suffix: "WithHelper")
struct GreeterWithHelperHook {
    @DynamicSubclassOverride
    func greet() -> String { "tagged:" + callSuper() }

    // Intentionally NOT tagged — must remain a plain Swift helper that does
    // not register against the dynamic subclass.
    func helperWillNotBeRegistered() -> String { "helper" }
}

// MARK: - Scenario 8 — auto-cleanup via sentinel

@objc(AutoCleanupTargetScenario8)
final class AutoCleanupTarget: NSObject {
    @objc dynamic func ping() -> Int { 1 }
}

@DynamicSubclassHook(of: AutoCleanupTarget.self, suffix: "AutoCleanup")
struct AutoCleanupHook {
    @DynamicSubclassOverride
    func ping() -> Int { callSuper() + 100 }
}

// MARK: - Scenario 9 — concurrency stress target

@objc(ConcurrencyTargetScenario9)
final class ConcurrencyTarget: NSObject {
    @objc dynamic func value() -> Int { 0 }
}

@DynamicSubclassHook(of: ConcurrencyTarget.self, suffix: "ConcurrencyStress")
struct ConcurrencyStressHook {
    @DynamicSubclassOverride
    func value() -> Int { callSuper() + 1 }
}

// MARK: - Tests

final class ObjCRuntimeToolboxTests: XCTestCase {

    // MARK: Scenario 1

    func testGreeterIsNotHookedByDefault() {
        let greeter = Greeter()
        XCTAssertEqual(greeter.greet(), "Hello")
        XCTAssertFalse(DynamicSubclass.isInstalled(on: greeter))
    }

    func testGreeterHookReplacesPerInstance() {
        let hookedGreeter = Greeter()
        let untouchedGreeter = Greeter()

        LoudGreeterHook.install(on: hookedGreeter)

        XCTAssertEqual(hookedGreeter.greet(), "HELLO!")
        XCTAssertEqual(untouchedGreeter.greet(), "Hello")
    }

    func testGreeterUninstallRestoresOriginalBehavior() {
        let greeter = Greeter()
        LoudGreeterHook.install(on: greeter)
        LoudGreeterHook.uninstall(from: greeter)

        XCTAssertEqual(greeter.greet(), "Hello")
        XCTAssertFalse(DynamicSubclass.isInstalled(on: greeter))
    }

    func testGreeterClassOverrideHidesDynamicSubclass() {
        let greeter = Greeter()
        LoudGreeterHook.install(on: greeter)
        // `type(of:)` routes through `-class`, which our override redirects
        // to the original class.
        XCTAssertTrue(type(of: greeter) == Greeter.self)
        // Direct ISA read sees the dynamic subclass.
        XCTAssertFalse(object_getClass(greeter) === Greeter.self)
    }

    // MARK: Scenario 2 — multi-arg return

    func testFormatterMultiArgReturn() {
        let formatter = Formatter()
        XCTAssertEqual(formatter.format("Ada", age: 36), "Ada is 36")

        CapitalizedFormatterHook.install(on: formatter)
        XCTAssertEqual(formatter.format("Ada", age: 36), "ADA IS 36")

        CapitalizedFormatterHook.uninstall(from: formatter)
        XCTAssertEqual(formatter.format("Ada", age: 36), "Ada is 36")
    }

    // MARK: Scenario 3 — multi-arg void

    func testLoggerMultiArgVoid() {
        let logger = NotificationLogger()
        PrefixedLoggerHook.install(on: logger)

        logger.log("hello", level: 2)
        XCTAssertEqual(logger.lastMessage, "[hooked] hello")
        XCTAssertEqual(logger.lastLevel, 2)

        PrefixedLoggerHook.uninstall(from: logger)
        logger.log("world", level: 3)
        XCTAssertEqual(logger.lastMessage, "world")
        XCTAssertEqual(logger.lastLevel, 3)
    }

    // MARK: Scenario 4 — protocol adoption + ifImplemented fallback

    func testProtocolAdoptionExposesNewMethod() {
        let speaker = BareSpeaker()
        XCTAssertNil((speaker as AnyObject) as? Greetable)

        PoliteSpeakerHook.install(on: speaker)

        XCTAssertTrue(speaker.conforms(to: Greetable.self))
        let greetable = (speaker as AnyObject) as? Greetable
        XCTAssertNotNil(greetable)
        XCTAssertEqual(greetable?.greetingPrefix(), "Mx. ")
    }

    func testRespondsToSelectorReportsHookedMethods() {
        let speaker = BareSpeaker()
        XCTAssertFalse(speaker.responds(to: #selector(Greetable.greetingPrefix)))

        PoliteSpeakerHook.install(on: speaker)
        XCTAssertTrue(speaker.responds(to: #selector(Greetable.greetingPrefix)))
    }

    // MARK: Scenario 5 — ifImplemented dispatching through super

    func testCallSuperIfImplementedDispatchesWhenSuperExists() {
        let speaker = BareSpeaker()
        LoggingSpeakerHook.install(on: speaker)
        XCTAssertEqual(speaker.speak(), "[log] hello")
        LoggingSpeakerHook.uninstall(from: speaker)
        XCTAssertEqual(speaker.speak(), "hello")
    }

    // MARK: Scenario 6 — shared suffix composes overrides

    func testSharedSuffixComposesOverridesAcrossHooks() {
        let host = SharedSuffixHost()
        // Installing both hooks on the same instance bumps retainCount, and
        // each hook's installOverridesIfNeeded lands a distinct selector on
        // the shared dynamic subclass.
        ComposedAHook.install(on: host)
        ComposedBHook.install(on: host)

        XCTAssertEqual(host.operationA(), "[A] A")
        XCTAssertEqual(host.operationB(), "[B] B")

        // Both hooks share one side-table entry — uninstall once each to
        // fully release.
        ComposedBHook.uninstall(from: host)
        XCTAssertEqual(host.operationA(), "[A] A", "operationA stays hooked while retainCount > 0")
        ComposedAHook.uninstall(from: host)
        XCTAssertEqual(host.operationA(), "A")
        XCTAssertEqual(host.operationB(), "B")
        XCTAssertFalse(DynamicSubclass.isInstalled(on: host))
    }

    // MARK: Scenario 7 — untagged method not registered as override

    func testUntaggedHookMethodIsNotRegistered() {
        let greeter = Greeter()
        GreeterWithHelperHook.install(on: greeter)

        // The tagged @DynamicSubclassOverride method is reachable.
        XCTAssertEqual(greeter.greet(), "tagged:Hello")
        // The untagged helper must NOT have been registered on the dynamic
        // subclass — `responds(to:)` should be false.
        XCTAssertFalse(greeter.responds(to: NSSelectorFromString("helperWillNotBeRegistered")))

        GreeterWithHelperHook.uninstall(from: greeter)
    }

    // MARK: Ref-counted install

    func testInstallIsRefCounted() {
        let greeter = Greeter()
        LoudGreeterHook.install(on: greeter)
        LoudGreeterHook.install(on: greeter)

        XCTAssertEqual(greeter.greet(), "HELLO!")

        LoudGreeterHook.uninstall(from: greeter)
        // Still hooked after one uninstall — retainCount is 1.
        XCTAssertEqual(greeter.greet(), "HELLO!")

        LoudGreeterHook.uninstall(from: greeter)
        // Fully restored after second uninstall.
        XCTAssertEqual(greeter.greet(), "Hello")
        XCTAssertFalse(DynamicSubclass.isInstalled(on: greeter))
    }

    // MARK: Auto-cleanup via sentinel

    func testSentinelClearsSideTableOnDealloc() {
        var target: AutoCleanupTarget? = AutoCleanupTarget()
        let identityCaptured: ObjectIdentifier
        do {
            let target = target!
            AutoCleanupHook.install(on: target)
            XCTAssertEqual(target.ping(), 101)
            XCTAssertTrue(DynamicSubclass.isInstalled(on: target))
            identityCaptured = ObjectIdentifier(target)
        }
        // Drop the only strong reference. ObjC sentinel's deinit should fire
        // and remove the side-table entry. Wrap in an autoreleasepool to flush
        // any deferred releases that ARC might be holding from the test
        // framework's bookkeeping.
        autoreleasepool {
            target = nil
        }

        // Test that a fresh AutoCleanupTarget is not reported as installed
        // even if its address happens to overlap the dead one. We can't
        // directly observe identityCaptured because it dangles; we infer
        // through behavior instead.
        let fresh = AutoCleanupTarget()
        XCTAssertEqual(fresh.ping(), 1)
        XCTAssertFalse(DynamicSubclass.isInstalled(on: fresh))
        _ = identityCaptured  // keep the captured value alive to avoid warnings
    }

    // MARK: Concurrent install / uninstall stress

    func testConcurrentInstallUninstallOnDistinctInstances() {
        let iterationCount = 200
        DispatchQueue.concurrentPerform(iterations: iterationCount) { _ in
            let target = ConcurrencyTarget()
            ConcurrencyStressHook.install(on: target)
            XCTAssertEqual(target.value(), 1)
            ConcurrencyStressHook.uninstall(from: target)
            XCTAssertEqual(target.value(), 0)
        }
    }
}
#endif
