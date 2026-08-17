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

        guard let levelArgument = arguments.first?.expression else {
            throw LogMacroError.missingLevel
        }

        let remainingArguments = arguments.dropFirst()
        let categoryArgument = remainingArguments.first { $0.label?.text == "category" }

        guard let messageArgument = remainingArguments.first(where: { $0.label == nil })?.expression else {
            throw LogMacroError.missingMessage
        }

        // The category expression is transplanted verbatim into the expansion:
        // it re-type-checks there against the LogCategory parameter of the
        // generated logger(for:) / _osLog(for:) accessors, so leading-dot
        // references and arbitrary LogCategory expressions both work.
        let loggerExpression: String
        let osLogExpression: String
        if let categoryArgument {
            let categoryExpression = categoryArgument.expression.trimmedDescription
            loggerExpression = "Self.logger(for: \(categoryExpression))"
            osLogExpression = "Self._osLog(for: \(categoryExpression))"
        } else {
            loggerExpression = "Self.logger"
            osLogExpression = "Self._osLog"
        }

        let osMethodName = mapLevelToOSLogMethod(levelArgument)
        let osLogType = mapLevelToOSLogType(levelArgument)

        let legacyFormat = buildLegacyOSLogFormat(from: messageArgument)
        let legacyCall = legacyFormat.wrappingInCStringScopes(
            "os_log(.\(osLogType), log: \(osLogExpression), \(legacyFormat.formatLiteral)\(legacyFormat.argumentList))",
            // The `else` branch of the expansion below sits eight spaces in.
            continuationIndent: 8
        )

        return """
        {
            if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                \(raw: loggerExpression).\(raw: osMethodName)(\(messageArgument))
            } else {
                \(raw: legacyCall)
            }
        }()
        """
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
