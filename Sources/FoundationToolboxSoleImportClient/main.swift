import FoundationToolbox

// This whole target is the guard: **no file in it may import anything other
// than `FoundationToolbox`.**
//
// A macro must not expand to code naming a module the caller has not imported.
// `#URL` and `#Selector` both violated that rule until `Exported.swift` started
// re-exporting Foundation, and neither was caught, because every existing
// client target imports Foundation on its own for unrelated reasons. The guard
// is only a guard with a target to itself — the same lesson
// `OSToolboxNoFoundationClient` records, arrived at from the opposite
// direction: there the point is that Foundation must stay *out*, here that a
// single import must be *enough*.

let guardedURL = #URL("https://example.com/path")
print(guardedURL.absoluteString)

let guardedSelector = #Selector("description")
print(guardedSelector)

final class GuardedSettings {
    @UserDefault(key: "sole-import-guard.launchCount")
    var launchCount: Int = 0

    @Keychain(key: "sole-import-guard.token", service: "sole-import-guard")
    var token: String = ""
}

let guardedSettings = GuardedSettings()
print(guardedSettings.launchCount, guardedSettings.token.isEmpty)

// `@Loggable` / `#log` / `@Mutex` reach here across two re-export hops, which
// `FoundationToolboxClient` already covers; repeated once here so that a
// regression in the chain fails this target too, without its Foundation import
// masking the cause.
@Loggable
struct GuardedService {
    func run() { #log(.debug, "sole-import guard ran") }
}

GuardedService().run()
