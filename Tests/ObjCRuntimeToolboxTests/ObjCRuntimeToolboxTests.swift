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
    func greetingPrefix() -> String {
        // BareSpeaker has no greetingPrefix IMP — `callSuperIfImplemented`
        // takes the default branch.
        return callSuperIfImplemented(default: "Mx. ")
    }
}

// MARK: - Scenario 5 — callSuperIfImplemented dispatching through super

@DynamicSubclassHook(of: BareSpeaker.self, suffix: "Logging")
struct LoggingSpeakerHook {
    func speak() -> String {
        // `speak` exists on BareSpeaker — `callSuperIfImplemented` dispatches.
        let originalUtterance = callSuperIfImplemented(default: "<no impl>")
        return "[log] " + originalUtterance
    }
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
}
#endif
