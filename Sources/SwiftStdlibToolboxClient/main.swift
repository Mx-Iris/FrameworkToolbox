import Foundation
import SwiftStdlibToolbox

@Equatable
class A {
    let a: String
    let b: Int
    @EquatableIgnored let c: Double
    init(a: String, b: Int, c: Double) {
        self.a = a
        self.b = b
        self.c = c
    }
}

final class ClassDecl: Sendable {
    @Mutex
    private var property: String!

    @Mutex
    private weak var delegate: AnyObject!

    @Mutex
    private var array: [String?] = []

    @available(macOS 12, *)
    @AvailableMutating(isSendable: true)
    private var attributedString: AttributedString = ""
    
    
    init(property: String) {
        self.property = property
        array[safe: 2] = nil
    }
}

let _ = 8.bitPattern.uint
_ = ClassDecl(property: "")

@AssociatedValue(.public)
enum EnumAssociatedValue {
    case optional(String?)
}

// MARK: - @DyldInterpose example: swapping printf
//
// Goal: replace libc's `printf` with a Swift implementation that prepends a
// marker before delegating to the real call site.
//
// The trick with `printf` is that Swift imports it as `unavailable` (variadic
// functions cannot be referenced from Swift), so we need a bridging
// declaration. There are two ways to bridge, but only one of them produces a
// dyld-recognizable interpose entry:
//
//   ✘ `@_silgen_name("printf")` — Swift takes the address through a
//     reabstraction thunk, so the second tuple slot ends up as a local rebase
//     pointing at Swift code rather than a `bind libSystem/_printf`. dyld
//     refuses to apply the entry.
//
//   ✔ `@_extern(c, "printf")` — Swift binds the symbol directly to the C
//     entry point. Taking its address yields a true `_printf` reference, and
//     dyld matches it against the loaded image's import table.
//
// The `@_extern` attribute is gated behind the `Extern` experimental feature;
// see `swiftSettings` for `SwiftStdlibToolboxClient` in `Package.swift`.
@_extern(c, "printf")
func printfRef(_ format: UnsafePointer<CChar>) -> Int32

// The replacement: prefix a marker and forward through `vprintf`, which is
// non-variadic and not itself interposed, so we do not recurse.
@DyldInterpose(printfRef)
func myPrintf(_ format: UnsafePointer<CChar>) -> Int32 {
    fputs("[interposed] ", stdout)
    return withVaList([]) { args in
        vprintf(format, args)
    }
}

// dyld only honors `__DATA,__interpose` in dynamic libraries, not in the main
// executable, so running this client directly prints the un-tagged string —
// the interpose entry is in the binary but never applied to the binary
// itself.
//
// To see the macro actually take effect, build the same code as a dylib and
// inject it into another process:
//
//   swiftc -enable-experimental-feature Extern \
//          -emit-library MyInterposers.swift -o libinterpose.dylib
//   DYLD_INSERT_LIBRARIES=./libinterpose.dylib /path/to/victim
//
// dyld will rewrite the `_printf` slot in every loaded image — including the
// victim binary — to call `myPrintf`. Output then becomes:
//
//   [interposed] hello from victim
_ = myPrintf("hello from client\n")
