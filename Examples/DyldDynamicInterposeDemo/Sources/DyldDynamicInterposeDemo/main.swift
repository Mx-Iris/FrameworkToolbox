import Darwin
import SwiftStdlibToolbox

// `dyld_dynamic_interpose` has been an empty function since dyld4 (see
// `libdyld/libdyldGlue.cpp`, tagged `rdar://74287303`). This demo does what it
// used to do: rewrite the symbol pointer slots of a loaded image so calls land
// on a replacement, then put them back.

// Capture the real `puts` before anything is rewritten — see Interposers.swift.
originalPuts = puts

print("--- before applying ---")
puts("line A")
print("getpid() = \(getpid())")

print("\n--- applying ---")
// `excludingDeclaringImage: false` because the image being interposed *is* the
// image declaring the hooks. The default (`true`) is what you want when the
// hooks live in a dylib and should not disturb that dylib's own calls.
let applyReport = DyldDynamicInterpose.applyAll(
    to: .mainExecutable,
    excludingDeclaringImage: false
)
print(applyReport)

print("\n--- after applying ---")
puts("line B")
print("getpid() = \(getpid())")

print("\n--- reverting ---")
let revertReport = DyldDynamicInterpose.revertAll()
print("restored \(revertReport.rewrittenSlots.count) slot(s)")

print("\n--- after reverting ---")
puts("line C")
print("getpid() = \(getpid())")
