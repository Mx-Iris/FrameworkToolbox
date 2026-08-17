import SwiftSyntax

// Shared by `#log` and `#signpost`: both fall back to a C-variadic API
// (`os_log` / `os_signpost`) on OS versions predating their modern counterpart,
// and both therefore need an interpolated Swift message turned into a printf
// format string plus arguments.

// MARK: - LegacyOSLogFormat

/// A printf-style format string and the interpolation segments feeding it,
/// ready to splice into an `os_log` / `os_signpost` call.
///
/// Every segment is passed as `UnsafePointer<CChar>` via `String.withCString`,
/// **not** as `String`. That is deliberate and load-bearing: `String: CVarArg`
/// is a conformance Foundation adds, the standard library has none. Expanding to
/// a `String` argument therefore made `#log` fail to compile in any module that
/// never imported Foundation — with the error landing on generated code the
/// source never mentions. `UnsafePointer<CChar>: CVarArg` and
/// `String.withCString` are both standard library, so this route has no such
/// dependency.
///
/// The catch worth remembering: conformance lookup is module-wide, so a single
/// `import Foundation` anywhere in a target hides the problem for every file in
/// it. `OSToolboxNoFoundationClient` exists as a target of its own for exactly
/// this reason.
struct LegacyOSLogFormat {
    /// The format string including its surrounding quotes, e.g. `"count=%{public}s"`.
    let formatLiteral: String

    /// The interpolated expressions, in order, as raw source text.
    let segmentExpressions: [String]

    /// The names bound to each segment's C string pointer.
    ///
    /// A fixed name rather than a `makeUniqueName` one, to keep expansions
    /// readable in snapshots. The shadowing risk is theoretical: an interpolated
    /// expression would have to reference an identifier by this exact name.
    var argumentNames: [String] {
        segmentExpressions.indices.map { "legacyArgument\($0)" }
    }

    /// The comma-prefixed argument list to append after the format string,
    /// or the empty string when the message has no interpolations.
    var argumentList: String {
        argumentNames.isEmpty ? "" : ", " + argumentNames.joined(separator: ", ")
    }

    /// Wraps `call` in one `withCString` scope per interpolation segment,
    /// returning `call` unchanged when there are none.
    ///
    /// - Parameter continuationIndent: Spaces to prepend to every line but the
    ///   first. A multi-line string spliced in through `\(raw:)` only has its
    ///   first line placed at the insertion point's indentation; the rest keep
    ///   whatever leading whitespace they were built with. Callers pass the
    ///   indentation of their insertion point so the closing braces line up.
    func wrappingInCStringScopes(_ call: String, continuationIndent: Int = 0) -> String {
        var source = call
        // Innermost scope last: build outward so segment 0 ends up outermost.
        for index in segmentExpressions.indices.reversed() {
            source = """
            "\\(\(segmentExpressions[index]))".withCString { \(argumentNames[index]) in
            \(indenting(source, by: 4))
            }
            """
        }
        return continuationIndent > 0 ? indenting(source, by: continuationIndent, skippingFirstLine: true) : source
    }

    private func indenting(_ source: String, by spaces: Int, skippingFirstLine: Bool = false) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { offset, line in
                if line.isEmpty { return String(line) }
                if skippingFirstLine, offset == 0 { return String(line) }
                return prefix + line
            }
            .joined(separator: "\n")
    }
}

// MARK: - Building

/// Builds an `os_log` / `os_signpost` format string from a string interpolation
/// expression.
///
/// Each interpolation segment becomes a `%{privacy}s` specifier. A message that
/// is not a string literal at all (a variable, a function call) is treated as a
/// single public segment.
func buildLegacyOSLogFormat(from expression: ExprSyntax) -> LegacyOSLogFormat {
    guard let stringLiteral = expression.as(StringLiteralExprSyntax.self) else {
        return LegacyOSLogFormat(
            formatLiteral: "\"%{public}s\"",
            segmentExpressions: [expression.trimmedDescription]
        )
    }

    var format = ""
    var segmentExpressions: [String] = []

    for segment in stringLiteral.segments {
        switch segment {
        case .stringSegment(let text):
            // Escape literal `%` as `%%` for printf-style format strings.
            format += text.content.text.replacingOccurrences(of: "%", with: "%%")
        case .expressionSegment(let expressionSegment):
            guard let valueExpression = expressionSegment.expressions.first?.expression else { continue }
            format += "%{\(extractOSLogPrivacy(from: expressionSegment.expressions))}s"
            segmentExpressions.append(valueExpression.trimmedDescription)
        }
    }

    return LegacyOSLogFormat(
        formatLiteral: "\"\(format)\"",
        segmentExpressions: segmentExpressions
    )
}

// MARK: - Privacy

/// Extracts the privacy annotation from an interpolation segment's labeled expressions.
///
/// Maps privacy values to printf format specifier qualifiers:
/// - `.public` → `"public"`
/// - `.private` / `.private(mask:)` → `"private"`
/// - `.sensitive` / `.sensitive(mask:)` → `"private"` (no `sensitive` in the legacy API)
/// - `.auto` / `.auto(mask:)` / absent → `"public"` (default to visible)
///
/// The last row differs from `os.Logger`, whose `auto` treats strings as private.
/// A `#log` call therefore redacts differently on OS versions old enough to take
/// this path. That is pre-existing behaviour, kept here so `#log` and `#signpost`
/// at least agree with each other; changing it would alter already-shipped logs.
private func extractOSLogPrivacy(from expressions: LabeledExprListSyntax) -> String {
    for expression in expressions {
        guard expression.label?.text == "privacy" else { continue }

        // Simple member access: .public, .private, .auto, .sensitive
        if let memberAccess = expression.expression.as(MemberAccessExprSyntax.self) {
            return mapPrivacyName(memberAccess.declName.baseName.text)
        }

        // Function call: .private(mask: .hash), .sensitive(mask: .hash), .auto(mask: .hash)
        if let functionCall = expression.expression.as(FunctionCallExprSyntax.self),
           let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self) {
            return mapPrivacyName(memberAccess.declName.baseName.text)
        }

        return "public"
    }

    // No privacy parameter — default to public for visibility.
    return "public"
}

private func mapPrivacyName(_ name: String) -> String {
    switch name {
    case "public": return "public"
    case "private": return "private"
    case "sensitive": return "private"
    default: return "public"
    }
}
