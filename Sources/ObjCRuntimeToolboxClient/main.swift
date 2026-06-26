import ObjCRuntimeToolbox

#if canImport(ObjectiveC)
import Foundation

@objc(GreeterRuntimeClient)
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

let greeter = Greeter()
print("Before install: ", greeter.greet())
LoudGreeterHook.install(on: greeter)
print("After install:  ", greeter.greet())
LoudGreeterHook.uninstall(from: greeter)
print("After uninstall:", greeter.greet())

#endif
