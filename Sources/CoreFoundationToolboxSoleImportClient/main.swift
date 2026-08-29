import CoreFoundationToolbox

// This whole target is the guard: **no file in it may import anything other
// than `CoreFoundationToolbox`.**
//
// Two things have to hold for a single import to be enough here, and neither
// did before `Exported.swift` existed. The CoreFoundation types this target
// wraps must be nameable, and so must `FrameworkToolbox<…>` — which 59
// declarations spell out, including every `allocator:` default argument. The
// second one is easy to miss because `.box` keeps working without it: member
// lookup finds `.box` through the conformance declared in this target, so only
// code that names the box type fails.

let guardedString: CFString = CFString.box.from("world")
print(guardedString.box.length)

// Naming the box type directly — this is what failed with `cannot find
// 'FrameworkToolbox' in scope`.
let guardedAllocator: CFAllocator = FrameworkToolbox<CFAllocator>.default
let guardedCopy: CFString = guardedString.box.copy(allocator: guardedAllocator)
print(guardedCopy.box.length)

let guardedArray = CFMutableArray.box.create()
guardedArray.box.append(guardedString)
print(CFArrayGetCount(guardedArray))
