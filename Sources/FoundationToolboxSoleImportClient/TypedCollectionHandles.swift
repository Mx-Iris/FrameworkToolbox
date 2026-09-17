import FoundationToolbox

// Part of this target's guard — see the comment at the top of `main.swift`. **No file in
// this target may import anything other than `FoundationToolbox`.**
//
// What it pins here: the typed collection handles name `NSArray`, `NSMutableDictionary`
// and friends right in their public signatures, so a caller who writes only
// `import FoundationToolbox` must still be able to spell those types. That works solely
// because `Exported.swift` re-exports Foundation — and nothing fails loudly when a
// re-export breaks, which is why the guard has to be a compiled call site rather than a
// note in a document.
internal func exerciseTypedCollectionHandles() {
    let names: NSMutableArrayOf<String> = ["Ada"]
    names.append("Grace")

    // Naming `NSArray` in the caller's own source, not just receiving it.
    let storage: NSArray = names.rawValue.copy() as! NSArray
    let verifiedNames = NSArrayOf<String>(validating: storage)

    let tempos: NSMutableDictionaryOf<String, Int> = ["Blue in Green": 120]
    tempos["So What"] = 136

    let tags: NSMutableSetOf<String> = ["bebop"]
    tags.insert("modal")

    print(names.count, verifiedNames?.count ?? 0, tempos.count, tags.count)
}

// The macro half of the same guard. `@ObjectiveCBridgeable` expands to code naming
// `_ObjectiveCBridgeable` and whatever class the caller wrote on `rawValue` — so this pins
// that a caller with only `import FoundationToolbox` can both apply the macro and compile
// what it produces. The expansion reaching for a module the caller never imported is the
// defect class CLAUDE.md records, and it has bitten this package more than once.
@ObjectiveCBridgeable
struct GuardedCollectionHandle: ObjectiveCCollectionHandle {
    // Spelled out rather than inferred. The conversion members come from
    // `ObjectiveCCollectionHandle`'s extension, and a generic default implementation carries
    // no concrete type for the compiler to infer the associated type from.
    typealias ObjectiveCRepresentation = NSArray

    let rawValue: NSArray

    init(rawValue: NSArray) { self.rawValue = rawValue }

    init() { self.init(rawValue: NSArray()) }

    static func containsOnlyExpectedElementTypes(in rawValue: NSArray) -> Bool {
        rawValue.allSatisfy { $0 is NSString }
    }
}
