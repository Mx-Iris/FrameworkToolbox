import OSToolbox

// Compile-time guard: `@Loggable` must never expand to code that names a module
// the caller has not imported. An earlier default derived the subsystem from
// `Bundle.main.bundleIdentifier`, which failed with `cannot find 'Bundle' in
// scope` in any file lacking `import Foundation` — pointing at generated code
// the source never mentions. The default is now simply the type name, so this
// file has to keep compiling *without* an `import Foundation`.

@Loggable
struct ServiceWithoutFoundation {
    func emit() { #log(.debug, "struct default subsystem, no Foundation import") }
}

@Loggable
final class ClassWithoutFoundation {
    func emit() { #log(.debug, "class default subsystem, no Foundation import") }
}
