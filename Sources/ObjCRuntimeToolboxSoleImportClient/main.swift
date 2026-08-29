import ObjCRuntimeToolbox

// This whole target is the guard: **no file in it may import anything other
// than `ObjCRuntimeToolbox`.**
//
// Every macro here expands to `NSSelectorFromString(_:)`, which is Foundation,
// not ObjectiveC. Before `Exported.swift` re-exported Foundation, each of these
// declarations failed with `cannot find 'NSSelectorFromString' in scope` in the
// caller's own file. `ObjCRuntimeToolboxClient` could not catch that: it does
// `import Foundation` for `NSObject`, which is exactly what a guard target must
// not do.

#if canImport(ObjectiveC)

// `@RuntimeClassProxy` — reaches `NSSelectorFromString` from the generated
// requirement table and from each accessor.
@RuntimeClassProxy("NSProcessInfo")
protocol GuardedProcessInfoProxy {
    var processName: String? { get }
}

// `@DynamicSubclassHook` — reaches it from the generated override bodies. Also
// pins that `NSObject` itself is nameable through the re-export.
@objc(GuardedSpeakerSoleImportClient)
final class GuardedSpeaker: NSObject {
    @objc dynamic func speak() -> String { "hello" }
}

@DynamicSubclassHook(of: GuardedSpeaker.self, suffix: "Guarded")
struct GuardedSpeakerHook {
    @DynamicSubclassOverride
    func speak() -> String {
        callSuper() + " (guarded)"
    }
}

let guardedSpeaker = GuardedSpeaker()
GuardedSpeakerHook.install(on: guardedSpeaker)
print(guardedSpeaker.speak())
GuardedSpeakerHook.uninstall(from: guardedSpeaker)

// `DynamicObject` / `ObjC` — the header-less call path, which the re-export also
// has to keep reachable.
print(ObjC.NSProcessInfo.processInfo)

#endif
