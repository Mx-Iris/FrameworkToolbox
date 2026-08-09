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


let array: [Int] = []

print(array[safe: 2] as Any)

// MARK: - `DyldToolbox` re-export

// dyld interposing was extracted into `DyldToolbox`, which this module
// re-exports. These two declarations are the compile-time proof that the split
// stayed invisible: a bare `import SwiftStdlibToolbox` must still resolve both
// macro declarations *and* their compiler plugin. Deleting them would let a
// broken re-export ship unnoticed, because nothing else here would fail.
//
// Neither one has any runtime effect: `@DyldInterpose`'s section is only
// consumed by dyld in a dylib, not in a main executable, and
// `@DyldDynamicInterpose` does nothing until `applyAll()` is called.
#if canImport(Darwin) && _pointerBitWidth(_64)

@DyldInterpose(getpgrp)
func reExportProbeInterposedGetProcessGroupIdentifier() -> pid_t {
    424_243
}

@DyldDynamicInterpose(getppid)
func reExportProbeInterposedGetParentProcessIdentifier() -> pid_t {
    424_242
}

#endif
