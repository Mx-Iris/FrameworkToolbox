import SwiftStdlibToolbox

// Manual expansion playground for the five enumeration macros. Right-click any
// attribute below and choose "Expand Macro" to read what it generates.
//
// The behavioural coverage lives in `Tests/SwiftStdlibToolboxTests/` and the
// pinned expansions in `Tests/SwiftStdlibToolboxMacroTests/`; this target is
// where the same code is compiled outside the test environment.

enum HypertextTransferProtocolStatus: CaseIterable {
    case ok
    case notFound
    case teapot

    @Bijection var code: Int {
        switch self {
        case .ok: 200
        case .notFound: 404
        case .teapot: 418
        }
    }
}

@CaseTag(backing: String.self) enum EditorAction {
    case insert(String)
    case delete(range: Range<Int>)
    case undo
}

@MirroredCases enum TooltipKind {
    @CaseTag(by: TooltipKind.self) enum Variant {
        case text(String)
        case icon(Int)
        case custom
    }
}

@DefaultedCases enum ScheduledTask: Equatable {
    case recurring(interval: Int = 60, tag: String? = nil)
    case immediate
}

@Projection enum NotificationTarget {
    case document(DocumentReference)
    case window(WindowReference?)
    case application

    @ProjectionFunction
    static func identifier(_ value: some CustomStringConvertible) -> String {
        value.description
    }
}

struct DocumentReference: CustomStringConvertible {
    let description: String
}

struct WindowReference: CustomStringConvertible {
    let description: String
}

/// Every case here is projectable and none carries an optional, so the
/// generated `switch` is exhaustive. Before `@Projection` learned to leave the
/// `default` out, this shape made the compiler warn `default will never be
/// executed` against code the source never mentions — a warning, not an error,
/// so nothing failed and nothing noticed. It sits in a target that really gets
/// compiled because that is the only place such a warning can show up at all.
@Projection enum FullyCoveredProjection {
    case named(String)
    case numbered(Int)

    @ProjectionFunction
    static func summary(_ value: some CustomStringConvertible) -> String {
        value.description
    }
}

func exerciseEnumMacros() {
    _ = HypertextTransferProtocolStatus(404)
    _ = EditorAction.undo.tag
    _ = TooltipKind.Variant.custom.tag
    // The generated constructor shares its name with the case it fills in, so
    // it needs an expected type to pick between them — which fluent dot syntax
    // supplies, and a bare `ScheduledTask.recurring` does not.
    let recurring: ScheduledTask = .recurring
    _ = recurring
    _ = NotificationTarget.application.identifier
    _ = FullyCoveredProjection.numbered(1).summary
}
