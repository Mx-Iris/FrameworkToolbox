import Darwin

// This executable links against `DyldInterposeDemoLib` as a real dynamic
// dependency (LC_LOAD_DYLIB), because the library lives in a different
// SwiftPM package. At launch dyld scans the dylib's `__DATA,__interpose`
// section and rewrites the corresponding symbol slots in *every* loaded
// image, including this main executable.
//
// Result: the calls below to `puts` / `printfRef` are redirected to the
// `interposedPuts` / `interposedPrintf` implementations in the dylib, and
// each line is prefixed with a hook marker.

@_extern(c, "printf")
func printfRef(_ format: UnsafePointer<CChar>) -> Int32

print("--- demo: puts ---")
puts("line A")
puts("line B")

print("--- demo: printf ---")
_ = printfRef("line C\n")
_ = printfRef("line D\n")
