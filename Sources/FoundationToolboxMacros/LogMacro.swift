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
        let osLogType = mapLevelToOSLogType(levelArg)

        let osMessage = messageArg
        let (formatString, formatArgs) = buildLegacyOSLogFormat(from: messageArg)

        return """
        {
            if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                Self.logger.\(raw: osMethodName)(\(osMessage))
            } else {
                os_log(.\(raw: osLogType), log: Self._osLog, \(raw: formatString)\(raw: formatArgs))
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

    /// Maps OSLogType member access expressions to OSLogType case names for the legacy os_log API.
    private static func mapLevelToOSLogType(_ expr: ExprSyntax) -> String {
        guard let memberAccess = expr.as(MemberAccessExprSyntax.self) else {
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

    /// Builds an `os_log` format string and argument list from a string interpolation expression.
    ///
    /// Each interpolation segment becomes a `%{privacy}@` format specifier with its value
    /// wrapped in `"\(expr)"` to convert to `String` (which conforms to `CVarArg`).
    ///
    /// - Returns: A tuple of (format string literal, comma-prefixed argument list) as raw source text.
    private static func buildLegacyOSLogFormat(from expr: ExprSyntax) -> (format: String, args: String) {
        guard let stringLiteral = expr.as(StringLiteralExprSyntax.self) else {
            return ("\"%{public}@\"", ", \"\\(\(expr.trimmedDescription))\"")
        }

        var format = ""
        var args: [String] = []

        for segment in stringLiteral.segments {
            switch segment {
            case .stringSegment(let text):
                // Escape literal `%` as `%%` for os_log format strings
                format += text.content.text.replacingOccurrences(of: "%", with: "%%")
            case .expressionSegment(let exprSegment):
                guard let valueExpr = exprSegment.expressions.first?.expression else { continue }
                let privacy = extractOSLogPrivacy(from: exprSegment.expressions)
                format += "%{\(privacy)}@"
                args.append("\"\\(\(valueExpr.trimmedDescription))\"")
            }
        }

        let formatStr = "\"\(format)\""
        let argsStr = args.isEmpty ? "" : ", " + args.joined(separator: ", ")
        return (formatStr, argsStr)
    }

    /// Extracts the privacy annotation from an interpolation segment's labeled expressions.
    ///
    /// Maps `LogPrivacy` values to `os_log` format specifier privacy qualifiers:
    /// - `.public` → `"public"`
    /// - `.private` / `.private(mask:)` → `"private"`
    /// - `.sensitive` / `.sensitive(mask:)` → `"private"` (no `sensitive` in legacy API)
    /// - `.auto` / `.auto(mask:)` / absent → `"public"` (default to visible)
    private static func extractOSLogPrivacy(from expressions: LabeledExprListSyntax) -> String {
        for expr in expressions {
            guard expr.label?.text == "privacy" else { continue }

            // Handle simple member access: .public, .private, .auto, .sensitive
            if let memberAccess = expr.expression.as(MemberAccessExprSyntax.self) {
                return mapPrivacyName(memberAccess.declName.baseName.text)
            }

            // Handle function call: .private(mask: .hash), .sensitive(mask: .hash), .auto(mask: .hash)
            if let funcCall = expr.expression.as(FunctionCallExprSyntax.self),
               let memberAccess = funcCall.calledExpression.as(MemberAccessExprSyntax.self) {
                return mapPrivacyName(memberAccess.declName.baseName.text)
            }

            return "public"
        }

        // No privacy parameter — default to public for visibility
        return "public"
    }

    private static func mapPrivacyName(_ name: String) -> String {
        switch name {
        case "public": return "public"
        case "private": return "private"
        case "sensitive": return "private"
        default: return "public"
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
