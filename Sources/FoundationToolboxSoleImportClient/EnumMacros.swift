import FoundationToolbox

// Two guards in one file, neither of which any test can express.
//
// First: the five enum macros are declared in `SwiftStdlibToolbox`, and only
// reach here because `FoundationToolbox` re-exports it. Nothing fails when a
// re-export breaks — the old import path simply stops resolving in somebody
// else's module — so it has to be pinned by compiling against it.
//
// Second, and the reason this file lives in *this* target rather than a client
// that imports whatever it likes: nothing below may need an import the caller
// did not write. A macro that expands to code naming an unimported module
// produces an error pointing at generated source the caller never wrote, and
// this package has shipped that defect more than once.

enum SoleImportBijection {
    case first
    case second

    @Bijection var code: Int {
        switch self {
        case .first: 1
        case .second: 2
        }
    }
}

@CaseTag(backing: String.self) enum SoleImportTagged {
    case plain
    case carrying(Int?)
}

@MirroredCases enum SoleImportOuterTag {
    @CaseTag(by: SoleImportOuterTag.self) enum Variant {
        case text(String)
        case number(Int)
    }
}

@DefaultedCases enum SoleImportDefaulted {
    case configured(limit: Int = 10, note: String? = nil)
    case bare
}

@Projection enum SoleImportProjected {
    case named(String?)
    case counted(Int)
    case nothing

    @ProjectionFunction
    static func label(_ value: some CustomStringConvertible) -> String {
        value.description
    }
}

func exerciseEnumMacrosThroughSoleImport() {
    _ = SoleImportBijection(1)
    _ = SoleImportTagged.plain.tag
    _ = SoleImportOuterTag.Variant.number(1).tag
    let defaulted: SoleImportDefaulted = .configured
    _ = defaulted
    _ = SoleImportProjected.counted(1).label
}
