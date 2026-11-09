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

// Initialisers, class methods, block parameters and `@RuntimeObjectProxy`: each
// generated witness has to be `nonisolated` too, or it inherits the protocol's
// isolation and cannot be reached from the function below.

@objc(DefaultIsolationConstructible)
nonisolated final class DefaultIsolationConstructible: NSObject {
    @objc let level: Int

    @objc init(level: Int) {
        self.level = level
    }

    @objc class func make() -> DefaultIsolationConstructible {
        DefaultIsolationConstructible(level: 2)
    }

    @objc dynamic func deliver(_ handler: @escaping (Int) -> Void) {
        handler(level)
    }
}

@RuntimeClassProxy("DefaultIsolationConstructible")
protocol DefaultIsolationConstructibleSurface {
    init?(level: Int)
    static func make() -> DefaultIsolationConstructible?
    func deliver(_ handler: @escaping @convention(block) (Int) -> Void)
}

@RuntimeObjectProxy
protocol DefaultIsolationLevelled {
    func level() -> Int?
}

nonisolated func constructAndReadInBackground() -> Int? {
    let constructed = DefaultIsolationConstructibleSurfaceImplementation(level: 3)
    constructed?.deliver { _ in }
    _ = DefaultIsolationConstructibleSurfaceImplementation.make()
    return DefaultIsolationLevelledImplementation(DefaultIsolationHost())?.level()
}
