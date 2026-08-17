import OSToolbox

// Compile-time guard: `@Loggable` must never expand to code that names a module
// the caller has not imported. An earlier default derived the subsystem from
// `Bundle.main.bundleIdentifier`, which failed with `cannot find 'Bundle' in
// scope` in any file lacking `import Foundation` — pointing at generated code
// the source never mentions. The default is now simply the type name, so this
// file has to keep compiling *without* an `import Foundation`.
//
// See `main.swift` for why this guard needs a target of its own.

extension LogCategory {
    static let startup = LogCategory("startup")
}

@Loggable
struct ServiceWithoutFoundation {
    func emit() { #log(.debug, "struct default subsystem, no Foundation import") }
}

@Loggable
final class ClassWithoutFoundation {
    func emit() { #log(.debug, "class default subsystem, no Foundation import") }
}

// The guard above only ever used messages *without* interpolation, which is why
// it missed a second Foundation dependency for years: the legacy `os_log` branch
// of `#log` used to expand to `os_log(…, "%{public}@", "\(value)")`, and
// `String: CVarArg` is a conformance Foundation adds — the standard library has
// none. Any interpolated message therefore failed to compile here with
// `argument type 'String' does not conform to expected type 'CVarArg'`, again
// pointing at generated code the source never mentions.
//
// The legacy branch now formats through `"%{public}s"` + `String.withCString`,
// both of which are standard library only. These cases are the regression test:
// they exercise one segment, several segments, mixed privacy levels, and a
// literal `%` needing escaping.

@Loggable
struct InterpolatingServiceWithoutFoundation {
    func emitSingleSegment(count: Int) {
        #log(.debug, "count=\(count)")
    }

    func emitSeveralSegments(name: String, count: Int, ratio: Double) {
        #log(.info, "name=\(name, privacy: .public) count=\(count) ratio=\(ratio)")
    }

    func emitMixedPrivacy(token: String, identifier: Int) {
        #log(.error, "token=\(token, privacy: .private) id=\(identifier, privacy: .public)")
    }

    func emitEscapedPercent(percentage: Int) {
        #log(.default, "progress \(percentage)%% complete")
    }

    func emitUnderACategory(count: Int) {
        #log(.debug, category: .startup, "count=\(count, privacy: .public)")
    }
}

// MARK: - @Signpostable, applied alongside @Loggable

// Pins two things at compile time:
//   1. `@Signpostable`'s members never collide with `@Loggable`'s — two member
//      macros emitting one name is an `invalid redeclaration`, and applying both
//      to one type is the expected usage.
//   2. Neither macro's expansion needs Foundation.

@Loggable
@Signpostable
struct DualAnnotatedService {
    func emit() {
        #log(.debug, "logging from a dual-annotated type")
    }
}
