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
