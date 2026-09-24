import SwiftStdlibToolbox

// Example for selecting a comparison definition at the call site. Run
// `swift run SwiftStdlibToolboxClient` to see the output.
//
// One file listing, sorted every way Finder's "Sort By" menu offers — by name,
// size, kind and date last opened. Each order is a comparison definition
// declared on `FileItem` and picked at the call site by a key path to it.
// `\.bySizeLargestFirst` names a *static* property, so that key path is rooted
// at `FileItem.Type`, not at `FileItem`.
//
// The behavioural coverage lives in
// `Tests/SwiftStdlibToolboxTests/ComparisonSelectionTests.swift`; this target is
// where the same API is compiled against the public interface alone, without
// `@testable`. Caller-facing contract and traps:
// `Documentations/ComparisonSelection.md`.

/// One row of a Finder-style file listing.
///
/// `comparableDefinition` is the order `<` and `==` use: by name, the way a
/// listing starts out. Every other column a user can sort by is one more static
/// property carrying `@ComparableBuilder<Self>`, picked at the call site with
/// `sorted(using:)` — no closure per order, and the orders live next to the type
/// they describe.
///
/// They are `static var`, never `static let`. The step tree only folds into
/// direct member access while it is built where it is used; stored in a
/// `static let`, every comparison goes through a generic key path lookup
/// instead. Nothing warns about it — it just runs several times slower.
///
/// The `FrameworkToolboxCompatible` conformance is there for one thing only: the
/// two-value `compare(to:using:)` below, which goes through the element's *own*
/// `.box`. Sorting, `min`, `max` and `isSorted` need no such conformance,
/// because there the `.box` belongs to the array.
struct FileItem: ComparableBuildable, FrameworkToolboxCompatible {
    /// Declaration order is the sort order: an enumeration without raw or
    /// associated values gets `Comparable` synthesized that way (SE-0266).
    enum Kind: Comparable {
        case folder
        case document
        case image
        case archive
    }

    var name: String
    var kind: Kind
    var byteCount: Int
    /// Days since the file was last opened, or `nil` if it never has been.
    var daysSinceLastOpened: Int?

    static var comparableDefinition: some ComparisonStep<Self> {
        compare(\.name)
    }

    /// Largest first. Files of equal size fall back to their names, so the
    /// order is fully determined rather than left to the sort's stability.
    @ComparableBuilder<Self>
    static var bySizeLargestFirst: some ComparisonStep<Self> {
        compareDescending(\.byteCount)
        compare(\.name)
    }

    /// Folders, documents, images, archives — each group by name.
    @ComparableBuilder<Self>
    static var byKind: some ComparisonStep<Self> {
        compare(\.kind)
        compare(\.name)
    }

    /// Most recently opened first, never-opened files last.
    ///
    /// `compare(\.daysSinceLastOpened)` alone would put the never-opened files
    /// *first*: an optional step orders `nil` ahead of every value. Finder puts
    /// them at the end, so this definition spells its own rule out.
    @ComparableBuilder<Self>
    static var byLastOpened: some ComparisonStep<Self> {
        compareCustom(\.daysSinceLastOpened) { left, right in
            switch (left, right) {
            case (nil, nil): return .equal
            case (nil, _): return .descending
            case (_, nil): return .ascending
            case let (leftDays?, rightDays?):
                if leftDays < rightDays { return .ascending }
                if rightDays < leftDays { return .descending }
                return .equal
            }
        }
        compare(\.name)
    }
}

/// A window's position on screen.
///
/// Window frames have no single natural order — by area? by distance from the
/// origin? — so this type is deliberately neither `Comparable` nor
/// `ComparableBuildable`. It still has one order worth a name: reading order,
/// top to bottom and then left to right.
///
/// The steps are bare key paths. `compare(_:)` and its siblings belong to
/// `ComparableBuildable`, so they are out of reach here; the builder turns a key
/// path into a step on its own.
struct WindowFrame {
    var title: String
    var top: Int
    var left: Int

    @ComparableBuilder<Self>
    static var readingOrder: some ComparisonStep<Self> {
        \.top
        \.left
    }
}

func exerciseComparisonSelection() {
    let report = FileItem(name: "report.pdf", kind: .document, byteCount: 2_000_000, daysSinceLastOpened: 1)
    let notes = FileItem(name: "notes.txt", kind: .document, byteCount: 4_000, daysSinceLastOpened: 6)

    let files = [
        FileItem(name: "invoices", kind: .folder, byteCount: 0, daysSinceLastOpened: 3),
        report,
        FileItem(name: "avatar.png", kind: .image, byteCount: 180_000, daysSinceLastOpened: nil),
        FileItem(name: "backup.zip", kind: .archive, byteCount: 48_000_000, daysSinceLastOpened: 40),
        notes,
        FileItem(name: "screenshots", kind: .folder, byteCount: 0, daysSinceLastOpened: nil),
    ]

    // MARK: Selecting a definition

    printListing("as declared", files)
    printListing("sorted() — the default definition, by name", files.sorted())
    printListing("sorted(using: \\.bySizeLargestFirst)", files.box.sorted(using: \.bySizeLargestFirst))
    printListing("sorted(using: \\.byKind)", files.box.sorted(using: \.byKind))
    printListing("sorted(using: \\.byLastOpened)", files.box.sorted(using: \.byLastOpened))

    var mutableFiles = files
    mutableFiles.box.sort(using: \.byKind)
    printListing("sort(using: \\.byKind), in place", mutableFiles)

    // MARK: First, last, already sorted?

    print("\n--- min / max / isSorted ---")
    // `min` and `max` follow the definition, not a property: `min` is whatever
    // the definition puts first. Under a largest-first definition, that is the
    // largest file.
    print("min(using: \\.bySizeLargestFirst):", files.box.min(using: \.bySizeLargestFirst)?.name ?? "none")
    print("max(using: \\.bySizeLargestFirst):", files.box.max(using: \.bySizeLargestFirst)?.name ?? "none")
    print("min(using: \\.byLastOpened):", files.box.min(using: \.byLastOpened)?.name ?? "none")

    let bySize = files.box.sorted(using: \.bySizeLargestFirst)
    print("size-sorted list, isSorted(using: \\.bySizeLargestFirst):", bySize.box.isSorted(using: \.bySizeLargestFirst))
    // The protocol's own definition is just another static property, so it can
    // be selected the same way.
    print("size-sorted list, isSorted(using: \\.comparableDefinition):", bySize.box.isSorted(using: \.comparableDefinition))

    // MARK: Two values

    print("\n--- compare(to:using:) / isLess(than:using:) ---")
    print("report vs notes, by size:", report.box.compare(to: notes, using: \.bySizeLargestFirst))
    print("report vs notes, by name:", report.box.compare(to: notes, using: \.comparableDefinition))
    print("report before notes by last opened?", report.box.isLess(than: notes, using: \.byLastOpened))

    // MARK: Sorting by one property, no definition needed

    // `by:` takes a key path to a *property* — rooted at `FileItem` — and needs
    // no definition at all. Descending swaps the comparison rather than
    // reversing the result, so equal elements keep their order: both folders
    // are 0 bytes, and "invoices" stays ahead of "screenshots" in both
    // directions.
    printListing("sorted(by: \\.byteCount)", files.box.sorted(by: \.byteCount))
    printListing("sorted(by: \\.byteCount, .descending)", files.box.sorted(by: \.byteCount, .descending))

    // MARK: A type that is not Comparable at all

    let windows = [
        WindowFrame(title: "Inspector", top: 0, left: 900),
        WindowFrame(title: "Console", top: 600, left: 0),
        WindowFrame(title: "Editor", top: 0, left: 0),
    ]
    print("\n--- windows, sorted(using: \\.readingOrder) ---")
    for window in windows.box.sorted(using: \.readingOrder) {
        print(padded(window.title, to: 12), "top \(window.top), left \(window.left)")
    }
}

// MARK: - Output helpers

private func printListing(_ title: String, _ items: [FileItem]) {
    print("\n--- \(title) ---")
    for item in items {
        print(
            padded(item.name, to: 13),
            padded("\(item.kind)", to: 10),
            padded(formattedSize(item.byteCount), to: 8),
            formattedLastOpened(item.daysSinceLastOpened)
        )
    }
}

private func padded(_ text: String, to width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.count))
}

private func formattedSize(_ byteCount: Int) -> String {
    switch byteCount {
    case 0: return "--"
    case ..<1_000: return "\(byteCount) B"
    case ..<1_000_000: return "\(byteCount / 1_000) KB"
    default: return "\(byteCount / 1_000_000) MB"
    }
}

private func formattedLastOpened(_ days: Int?) -> String {
    switch days {
    case nil: return "never opened"
    case 1?: return "opened yesterday"
    case let days?: return "opened \(days) days ago"
    }
}
