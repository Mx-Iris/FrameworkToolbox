import Darwin
import SwiftStdlibToolbox

// The interposers deliberately live outside `main.swift`. A `let` declared at
// the top level of `main.swift` is sequenced with the surrounding statements
// rather than being a statically initialized global, and `@section` needs the
// latter.

// MARK: - Hook 1: puts
//
// This demo interposes the image that declares the hooks — the main executable
// itself — so `puts` inside the replacement would go through the very slot
// being rewritten and recurse forever. Capturing the original address *before*
// applying sidesteps that: the value below is the real libc address, not an
// indirection through this image's symbol pointer section.
//
// (When the hooks live in a dylib and the program leaves
// `excludingDeclaringImage` at its default, this dance is unnecessary — the
// declaring image keeps its own slots and can just call `puts` directly.)

nonisolated(unsafe) var originalPuts: (@convention(c) (UnsafePointer<CChar>?) -> Int32)?

@DyldDynamicInterpose(puts)
func interposedPuts(_ string: UnsafePointer<CChar>?) -> Int32 {
    fputs("[hooked puts] ", stdout)
    return originalPuts?(string) ?? 0
}

// MARK: - Hook 2: getpid
//
// Returning a constant needs no access to the original at all.

let fakeProcessIdentifier: pid_t = 12345

@DyldDynamicInterpose(getpid)
func interposedGetProcessIdentifier() -> pid_t {
    fakeProcessIdentifier
}
