import ObjCRuntimeToolbox

#if canImport(ObjectiveC)
import Foundation

// MARK: - Scenario 1 — return value + zero args, callSuper

@objc(GreeterRuntimeClient)
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

// MARK: - Scenario 2 — multi-arg returning value

@objc(FormatterRuntimeClient)
final class Formatter: NSObject {
    @objc dynamic func format(_ name: String, age: Int) -> String {
        "\(name) is \(age)"
    }
}

@DynamicSubclassHook(of: Formatter.self, suffix: "Capitalized")
struct CapitalizedFormatterHook {
    @DynamicSubclassOverride
    func format(_ name: String, age: Int) -> String {
        callSuper(name, age).uppercased()
    }
}

// MARK: - Scenario 3 — multi-arg void, side effect

@objc(NotificationLoggerRuntimeClient)
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

// MARK: - Scenarios 4 & 5 — adopts: protocol, callSuperIfImplemented

@objc(GreetableRuntimeClient)
protocol Greetable {
    func greetingPrefix() -> String
}

@objc(BareSpeakerRuntimeClient)
final class BareSpeaker: NSObject {
    @objc dynamic func speak() -> String { "hello" }
}

@DynamicSubclassHook(of: BareSpeaker.self, suffix: "Polite", adopts: [Greetable.self])
struct PoliteSpeakerHook {
    @DynamicSubclassOverride
    func greetingPrefix() -> String {
        callSuperIfImplemented(default: "Mx. ")
    }
}

@DynamicSubclassHook(of: BareSpeaker.self, suffix: "Logging")
struct LoggingSpeakerHook {
    @DynamicSubclassOverride
    func speak() -> String {
        let originalUtterance = callSuperIfImplemented(default: "<no impl>")
        return "[log] " + originalUtterance
    }
}

// MARK: - Driver

print("== Scenario 1 — Greeter / LoudGreeterHook ==")
let greeter = Greeter()
print("  before install:", greeter.greet())
LoudGreeterHook.install(on: greeter)
print("  after install :", greeter.greet())
LoudGreeterHook.uninstall(from: greeter)
print("  after uninstall:", greeter.greet())

print("== Scenario 2 — Formatter / CapitalizedFormatterHook ==")
let formatter = Formatter()
print("  before install:", formatter.format("Ada", age: 36))
CapitalizedFormatterHook.install(on: formatter)
print("  after install :", formatter.format("Ada", age: 36))
CapitalizedFormatterHook.uninstall(from: formatter)
print("  after uninstall:", formatter.format("Ada", age: 36))

print("== Scenario 3 — NotificationLogger / PrefixedLoggerHook ==")
let logger = NotificationLogger()
PrefixedLoggerHook.install(on: logger)
logger.log("ping", level: 2)
print("  after install : lastMessage=\(logger.lastMessage), lastLevel=\(logger.lastLevel)")
PrefixedLoggerHook.uninstall(from: logger)
logger.log("ping", level: 3)
print("  after uninstall: lastMessage=\(logger.lastMessage), lastLevel=\(logger.lastLevel)")

print("== Scenario 4 — BareSpeaker / PoliteSpeakerHook (adopts: Greetable) ==")
let politeSpeaker = BareSpeaker()
print("  before install: conforms=\(politeSpeaker.conforms(to: Greetable.self))")
PoliteSpeakerHook.install(on: politeSpeaker)
print(
    "  after install : conforms=\(politeSpeaker.conforms(to: Greetable.self)), prefix=",
    ((politeSpeaker as AnyObject) as? Greetable)?.greetingPrefix() ?? "<nil>"
)
PoliteSpeakerHook.uninstall(from: politeSpeaker)

print("== Scenario 5 — BareSpeaker / LoggingSpeakerHook (callSuperIfImplemented hits super) ==")
let loggingSpeaker = BareSpeaker()
print("  before install:", loggingSpeaker.speak())
LoggingSpeakerHook.install(on: loggingSpeaker)
print("  after install :", loggingSpeaker.speak())
LoggingSpeakerHook.uninstall(from: loggingSpeaker)
print("  after uninstall:", loggingSpeaker.speak())

#endif

// MARK: - Scenario 6 — @RuntimeClassHook: replacing a method on a class known only by name
//
// The target is reached by string, exactly as it would be inside an injected
// payload where the class has no header. The type encoding is derived from the
// Swift signature below and checked against the live class before anything is
// replaced.

@objc(IconTileRuntimeClient)
final class IconTile: NSObject {
    @objc dynamic var displayedIconName: NSString?

    @objc dynamic func setIcon(_ name: NSString?, animated: Bool) {
        displayedIconName = name
    }
}

@RuntimeClassHook("IconTileRuntimeClient")
struct IconTileHooks {
    @RuntimeMethodReplacement
    func setIcon(_ name: NSString?, animated: Bool) {
        // `host` is the receiver; `callOriginal` goes straight to the
        // implementation this replacement displaced, so it cannot re-enter.
        callOriginal("overridden:\(name ?? "")" as NSString, animated)
    }
}

// MARK: - Scenario 7 — @RuntimeClassProxy: calling into that same class

@RuntimeClassProxy("IconTileRuntimeClient")
protocol IconTileSurface {
    var displayedIconName: NSString? { get set }
    func setIcon(_ name: NSString?, animated: Bool)
}

// MARK: - Driver

print("== Scenario 6 — IconTile / IconTileHooks (@RuntimeClassHook) ==")
let iconTile = IconTile()
iconTile.setIcon("finder", animated: false)
print("  before install:", iconTile.displayedIconName ?? "<nil>")

do {
    try IconTileHooks.install()
    print("  install       : ok")
} catch {
    print("  install       : refused —", error)
}

iconTile.setIcon("finder", animated: false)
print("  after install :", iconTile.displayedIconName ?? "<nil>")

print("  derived descriptors:")
for descriptor in IconTileHooks.descriptors() {
    print("    \(descriptor) encoding=\(descriptor.expectedTypeEncoding)")
}

print("== Scenario 7 — IconTileSurface (@RuntimeClassProxy) ==")
print("  isSupported:", IconTileSurfaceImplementation.isSupported)
if let surface = IconTileSurfaceImplementation(iconTile) {
    print("  read via proxy :", surface.displayedIconName ?? "<nil>")
    surface.setIcon("mail", animated: true)
    print("  after proxy set:", surface.displayedIconName ?? "<nil>")
} else {
    print("  proxy unavailable")
}
print("  proxy refuses an unrelated object:", IconTileSurfaceImplementation(NSObject()) == nil)
