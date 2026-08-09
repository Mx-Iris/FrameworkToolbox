#if canImport(Darwin) && _pointerBitWidth(_64)

import Darwin
import DyldToolbox

// `getppid` is the target on purpose: nothing else in this process calls it, so
// redirecting it cannot disturb anything while the interpose is live.
private let interposedParentProcessIdentifier: pid_t = 424_242

@DyldDynamicInterpose(getppid)
func interposedGetParentProcessIdentifier() -> pid_t {
    interposedParentProcessIdentifier
}

// `@DyldInterpose` is only demonstrated by its expansion here, never by its
// effect: dyld consumes `__DATA,__interpose` in dylibs, not in a main
// executable. Compiling it is still worth something — it is what proves the
// macro and its plugin resolve from a bare `import DyldToolbox`.
@DyldInterpose(getpgrp)
func interposedGetProcessGroupIdentifier() -> pid_t {
    424_243
}

print("real getppid() -> \(getppid())")

let applyReport = DyldDynamicInterpose.applyAll(
    to: .image(#dsohandle),
    excludingDeclaringImage: false
)
print("rewrote \(applyReport.rewrittenSlots.count) slot(s), skipped \(applyReport.skippedSlots.count)")
print("interposed getppid() -> \(getppid())")

let revertReport = DyldDynamicInterpose.revertAll()
print("restored \(revertReport.rewrittenSlots.count) slot(s)")
print("reverted getppid() -> \(getppid())")

#else

print("dyld interposing is a Mach-O feature; nothing to demonstrate on this platform.")

#endif
