import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct LogMacro: ExpressionMacro {
    /// The parameter of the expansion's closure that a `category:` argument is
    /// bound to, so the handle and the message prefix read one value.
    ///
    /// A closure parameter rather than a `let` inside the closure: the category
    /// expression is then evaluated outside, so a caller's own variable of this
    /// name still works as the argument. A fixed name rather than a
    /// `makeUniqueName` one, as with `legacyArgument0`, to keep expansions
    /// readable; the message's interpolations could only be shadowed by naming
    /// an identifier exactly this.
    static let selectedCategoryName = "selectedLogCategory"

    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = node.arguments

        guard let levelArgument = arguments.first?.expression else {
            throw LogMacroError.missingLevel
        }

        // The level chooses the `Logger` method and the legacy `OSLogType`
        // right here, so it has to be readable as syntax. Anything else —
        // a variable, a ternary — used to fall through to `log` / `.default`
        // and log at the default level whatever it held.
        guard levelArgument.is(MemberAccessExprSyntax.self) else {
            context.diagnose(Diagnostic(node: levelArgument, message: LogMacroDiagnostic.levelMustBeLiteral))
            return "()"
        }

        let remainingArguments = arguments.dropFirst()
        let categoryArgument = remainingArguments.first { $0.label?.text == "category" }

        guard let messageArgument = remainingArguments.first(where: { $0.label == nil })?.expression else {
            throw LogMacroError.missingMessage
        }

        // The category expression is transplanted verbatim into the expansion,
        // as the argument of the closure the expansion is wrapped in. Its
        // parameter is typed `LogCategory`, so leading-dot references and
        // arbitrary `LogCategory` expressions both re-type-check there, and the
        // expression is still evaluated exactly once.
        //
        // A category may ask for its name in front of every message. Whether it
        // does is only known at runtime — the macro sees `.network`, not the
        // value behind it — so the message always gets a leading public
        // interpolation, which comes out empty for a category that does not.
        let closureParameterClause: String
        let closureArgument: String
        let loggerExpression: String
        let osLogExpression: String
        let modernMessage: ExprSyntax
        let legacyFormat: LegacyOSLogFormat
        if let categoryArgument {
            let categoryName = selectedCategoryName
            closureParameterClause = " (\(categoryName): OSToolbox.LogCategory) in"
            closureArgument = categoryArgument.expression.trimmedDescription
            loggerExpression = "Self.logger(for: \(categoryName))"
            osLogExpression = "Self._osLog(for: \(categoryName))"
            let prefixExpression = "OSToolbox.LoggableMacro._messagePrefix(for: \(categoryName))"
            modernMessage = prependingPublicInterpolation(of: prefixExpression, to: messageArgument)
            legacyFormat = buildLegacyOSLogFormat(from: messageArgument, leadingPublicSegment: prefixExpression)
        } else {
            closureParameterClause = ""
            closureArgument = ""
            loggerExpression = "Self.logger"
            osLogExpression = "Self._osLog"
            modernMessage = messageArgument
            legacyFormat = buildLegacyOSLogFormat(from: messageArgument)
        }

        let osMethodName = mapLevelToOSLogMethod(levelArgument)
        let osLogType = mapLevelToOSLogType(levelArgument)

        let legacyCall = legacyFormat.wrappingInCStringScopes(
            "os_log(.\(osLogType), log: \(osLogExpression), \(legacyFormat.formatLiteral)\(legacyFormat.argumentList))",
            // The `else` branch of the expansion below sits eight spaces in.
            continuationIndent: 8
        )

        return """
        {\(raw: closureParameterClause)
            if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                \(raw: loggerExpression).\(raw: osMethodName)(\(modernMessage))
            } else {
                \(raw: legacyCall)
            }
        }(\(raw: closureArgument))
        """
    }

    /// `message` with `\(prefixExpression, privacy: .public)` put ahead of its
    /// first character, or `message` unchanged when it is not a string literal —
    /// such a message does not type-check as an `OSLogMessage` anyway.
    ///
    /// The prefix has to be an interpolation: its text depends on the category
    /// value, which only exists at runtime. And it has to be `.public`, since
    /// `os` redacts an interpolated string as `<private>` by default once no
    /// debugger is attached.
    ///
    /// The segment is spliced into the literal's own segment list rather than
    /// the literal being rebuilt as text, so everything else — escapes, the
    /// raw-string delimiter, line breaks — stays as the caller wrote it. Two
    /// shapes need care:
    /// - A raw string interpolates with as many `#` as its delimiter, so the
    ///   segment carries the literal's own delimiter.
    /// - In a multi-line string the indentation of each line is trivia, and no
    ///   line may be indented less than the closing `"""`. The new segment
    ///   opens the first line, so it takes the closing delimiter's indentation
    ///   and the segment it displaces gives up its own.
    private static func prependingPublicInterpolation(
        of prefixExpression: String,
        to message: ExprSyntax
    ) -> ExprSyntax {
        guard let literal = message.as(StringLiteralExprSyntax.self) else {
            return message
        }

        // Built node by node rather than parsed out of a template literal: a
        // parsed `"\(x)"` brings empty string segments along on either side of
        // the interpolation, and taking the wrong one silently drops the prefix.
        var prefixSegment = ExpressionSegmentSyntax(
            pounds: literal.openingPounds.map { .rawStringPoundDelimiter($0.text) },
            expressions: LabeledExprListSyntax([
                LabeledExprSyntax(
                    expression: ExprSyntax("\(raw: prefixExpression)"),
                    trailingComma: .commaToken(trailingTrivia: .space)
                ),
                LabeledExprSyntax(
                    label: .identifier("privacy"),
                    colon: .colonToken(trailingTrivia: .space),
                    expression: ExprSyntax(".public")
                ),
            ])
        )

        var segments = Array(literal.segments)
        let hasContent = segments.contains { segment in
            if case .stringSegment(let text) = segment {
                return !text.content.text.isEmpty
            }
            return true
        }
        if literal.openingQuote.tokenKind == .multilineStringQuote {
            // An empty multi-line literal has no line to open: the prefix
            // alone, in a one-line literal, is the same string.
            guard hasContent else {
                return ExprSyntax(
                    literal
                        .with(\.openingQuote, .stringQuoteToken())
                        .with(\.segments, [.expressionSegment(prefixSegment)])
                        .with(\.closingQuote, .stringQuoteToken())
                )
            }
            prefixSegment.leadingTrivia = literal.closingQuote.leadingTrivia
            if !segments.isEmpty {
                segments[0].leadingTrivia = []
            }
        }
        segments.insert(.expressionSegment(prefixSegment), at: 0)
        return ExprSyntax(literal.with(\.segments, StringLiteralSegmentListSyntax(segments)))
    }

    /// Maps OSLogType member access expressions to os.Logger method names.
    private static func mapLevelToOSLogMethod(_ expression: ExprSyntax) -> String {
        guard let memberAccess = expression.as(MemberAccessExprSyntax.self) else {
            return "log"
        }
        let name = memberAccess.declName.baseName.text
        switch name {
        case "debug": return "debug"
        case "info": return "info"
        case "default": return "notice"
        case "error": return "error"
        case "fault": return "critical"
        default: return "log"
        }
    }

    /// Maps OSLogType member access expressions to OSLogType case names for the legacy os_log API.
    private static func mapLevelToOSLogType(_ expression: ExprSyntax) -> String {
        guard let memberAccess = expression.as(MemberAccessExprSyntax.self) else {
            return "default"
        }
        let name = memberAccess.declName.baseName.text
        switch name {
        case "debug": return "debug"
        case "info": return "info"
        case "default": return "default"
        case "error": return "error"
        case "fault": return "fault"
        default: return "default"
        }
    }
}

enum LogMacroError: Error, CustomStringConvertible {
    case missingLevel
    case missingMessage

    var description: String {
        switch self {
        case .missingLevel:
            return "#log requires a log level as the first argument (e.g., .debug, .info, .error)"
        case .missingMessage:
            return "#log requires a message as the second argument"
        }
    }
}

/// Diagnostics `#log` attaches to a specific argument rather than to the whole
/// call, which a thrown ``LogMacroError`` cannot do.
enum LogMacroDiagnostic: String, DiagnosticMessage {
    case levelMustBeLiteral

    var message: String {
        switch self {
        case .levelMustBeLiteral:
            return """
            #log reads its level when the macro expands, so it has to be written as a case \
            such as .debug or .error — a variable or other expression would be logged at the \
            default level whatever it held
            """
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "LogMacro", id: rawValue)
    }

    var severity: DiagnosticSeverity { .error }
}
