// `OSToolbox` sits one layer below this target so that `ObjCRuntimeToolbox` can
// depend on `Mutex` / `@Loggable` / `#log` without pulling in the stdlib layer.
// Re-exporting it here keeps that split invisible to callers: code that has
// always written `import SwiftStdlibToolbox` and then used `@Mutex` still
// resolves the macro, its plugin, and `WeakBox` without a second import.
@_exported import OSToolbox

// dyld interposing lives in `DyldToolbox` so that a consumer wanting only the
// binary-level hooks does not have to link this whole layer of Swift extensions
// — and, the other way round, so that this layer no longer drags in the arm64e
// pointer-authentication C shim only those hooks need. Re-exporting it keeps
// that split invisible too: code that has always written
// `import SwiftStdlibToolbox` and then used `@DyldInterpose` still resolves the
// macro, its plugin, and the `DyldDynamicInterpose` runtime.
@_exported import DyldToolbox
