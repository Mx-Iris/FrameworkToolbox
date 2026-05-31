import Darwin
import SwiftStdlibToolbox

// MARK: - Hook 1: puts
//
// `puts` is non-variadic, so Swift's C importer exposes it directly. No
// `@_extern` bridge is needed — the macro just consumes `puts` as the target.

@DyldInterpose(puts)
func interposedPuts(_ string: UnsafePointer<CChar>?) -> Int32 {
    fputs("[hooked puts] ", stdout)
    return puts(string)
}

// MARK: - Hook 2: printf
//
// `printf` is variadic; Swift imports it as `unavailable`. We re-declare it
// via `@_extern(c, "printf")` so taking the address yields a real
// `bind libSystem/_printf` reference that dyld can match. Calling `printfRef`
// from the replacement would recurse through the interposed slot, so we
// delegate to non-interposed `vprintf` with an empty va_list.

@_extern(c, "printf")
func printfRef(_ format: UnsafePointer<CChar>) -> Int32

@DyldInterpose(printfRef)
func interposedPrintf(_ format: UnsafePointer<CChar>) -> Int32 {
    fputs("[hooked printf] ", stdout)
    return withVaList([]) { args in
        vprintf(format, args)
    }
}

#if canImport(CoreFoundation)

import CoreFoundation

@DyldInterpose(CFArrayGetCount)
func interpoesdCFArrayGetCount(_ array: CFArray) -> CFIndex {
    return 5
}

#endif
