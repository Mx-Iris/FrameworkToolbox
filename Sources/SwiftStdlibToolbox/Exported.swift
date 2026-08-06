// `OSToolbox` sits one layer below this target so that `ObjCRuntimeToolbox` can
// depend on `Mutex` / `@Loggable` / `#log` without pulling in the stdlib layer.
// Re-exporting it here keeps that split invisible to callers: code that has
// always written `import SwiftStdlibToolbox` and then used `@Mutex` still
// resolves the macro, its plugin, and `WeakBox` without a second import.
@_exported import OSToolbox
