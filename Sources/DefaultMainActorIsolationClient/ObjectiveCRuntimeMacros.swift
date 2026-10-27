import Foundation
import ObjCRuntimeToolbox

// The Objective-C runtime macros under a `MainActor` default isolation. A hook
// container must be `nonisolated` — the runtime calls replacements on any
// thread, and the macros report an isolated container — so the one below says
// so, and this pins that a container which does compiles cleanly. A proxy is
// called from wherever its caller runs, so it has to be usable from a
// `nonisolated` function too. Both only have to compile.

@objc(DefaultIsolationHost)
nonisolated final class DefaultIsolationHost: NSObject {
    @objc dynamic func level() -> Int { 1 }
}

@RuntimeClassHook("DefaultIsolationHost")
nonisolated struct DefaultIsolationHostHooks {
    @RuntimeMethodReplacement
    func level() -> Int {
        callOriginal() + 1
    }
}

@RuntimeClassProxy("DefaultIsolationHost")
protocol DefaultIsolationHostSurface {
    func level() -> Int?
}

nonisolated func installAndReadInBackground(_ host: DefaultIsolationHost) -> Int? {
    try? DefaultIsolationHostHooks.install()
    return DefaultIsolationHostSurfaceImplementation(host)?.level()
}
