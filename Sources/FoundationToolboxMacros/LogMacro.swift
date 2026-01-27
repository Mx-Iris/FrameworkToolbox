import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct LogMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = node.arguments

        guard let levelArg = arguments.first?.expression else {
            throw LogMacroError.missingLevel
        }

        guard arguments.count >= 2,
              let messageArg = arguments.dropFirst().first?.expression
        else {
            throw LogMacroError.missingMessage
        }

        let osMethodName = mapLevelToOSLogMethod(levelArg)
        let swiftLogMethodName = mapLevelToSwiftLogMethod(levelArg)

        let osMessage = messageArg
        let swiftLogMessage = stripOSLogParameters(from: messageArg)

        return """
        {
            if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                Self.logger.\(raw: osMethodName)(\(osMessage))
            } else {
                Self._loggableSwiftLogger.\(raw: swiftLogMethodName)(\(swiftLogMessage))
            }
        }()
        """
    }

    /// Maps OSLogType member access expressions to os.Logger method names.
    private static func mapLevelToOSLogMethod(_ expr: ExprSyntax) -> String {
        guard let memberAccess = expr.as(MemberAccessExprSyntax.self) else {
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

    /// Maps OSLogType member access expressions to swift-log Logger method names.
    private static func mapLevelToSwiftLogMethod(_ expr: ExprSyntax) -> String {
        guard let memberAccess = expr.as(MemberAccessExprSyntax.self) else {
            return "info"
        }
        let name = memberAccess.declName.baseName.text
        switch name {
        case "debug": return "debug"
        case "info": return "info"
        case "default": return "notice"
        case "error": return "error"
        case "fault": return "critical"
        default: return "info"
        }
    }

    /// Strips OS log-specific parameters (privacy:, align:, format:) from string interpolation segments.
    private static func stripOSLogParameters(from expr: ExprSyntax) -> ExprSyntax {
        guard let stringLiteral = expr.as(StringLiteralExprSyntax.self) else {
            return expr
        }

        let newSegments = stringLiteral.segments.map { segment -> StringLiteralSegmentListSyntax.Element in
            guard case .expressionSegment(let exprSegment) = segment else {
                return segment
            }

            let filteredExpressions = exprSegment.expressions.filter { labeled in
                let label = labeled.label?.text ?? ""
                // Remove OS log-specific parameters
                return !["privacy", "align", "format"].contains(label)
            }

            // Re-index trailing commas
            let reindexed = LabeledExprListSyntax(
                filteredExpressions.enumerated().map { index, element in
                    if index < filteredExpressions.count - 1 {
                        return element.with(\.trailingComma, .commaToken(trailingTrivia: .space))
                    } else {
                        return element.with(\.trailingComma, nil)
                    }
                }
            )

            let newSegment = exprSegment.with(\.expressions, reindexed)
            return .expressionSegment(newSegment)
        }

        let newLiteral = stringLiteral.with(
            \.segments,
            StringLiteralSegmentListSyntax(newSegments)
        )
        return ExprSyntax(newLiteral)
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
