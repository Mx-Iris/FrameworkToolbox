import SwiftStdlibToolbox

// MARK: - Markers written with their module

// Each macro below finds a marker on one of its members by name, and a caller may
// write that marker with its module. Such a marker used to be skipped as if it
// were not there at all. These declarations only have to compile.

@MirroredCases
enum QualifiedTooltipKind {
    @SwiftStdlibToolbox.CaseTag(by: QualifiedTooltipKind.self)
    enum Variant {
        case text(String)
        case custom
    }
}

@Projection
enum QualifiedProjection {
    case first(String)

    @SwiftStdlibToolbox.ProjectionFunction
    static func label(_ value: some CustomStringConvertible) -> String {
        value.description
    }
}

@Equatable
struct QualifiedIgnoredMarkers {
    let identifier: Int
    // Neither of these can be compared, so the build fails if either marker is
    // overlooked.
    @SwiftStdlibToolbox.EquatableIgnored var cache: [String: Any] = [:]
    @SwiftStdlibToolbox.EquatableIgnoredUnsafeClosure var onTap: () -> Void = {}
}

// MARK: - Types that need parentheses to be made optional

// `any Error?` is rejected and `() -> Void?` is a function returning `Void?`, so
// a macro that makes the caller's type optional has to parenthesize these two
// shapes. These declarations only have to compile.

@AssociatedValue
enum AssociatedValueOptionalSpelling {
    case failed(any Error)
    case handler(() -> Void)
    case idle
}

@Projection
enum ProjectionOptionalSpelling {
    case first(String)
    case second(Int)

    @ProjectionFunction
    static func describe(_ value: some CustomStringConvertible) -> any CustomStringConvertible {
        value
    }
}
