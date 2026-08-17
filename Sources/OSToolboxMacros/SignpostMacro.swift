import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - Shared expansion machinery

/// The OS versions `OSSignposter` and everything reachable through it require.
let signposterAvailabilityCondition = "#available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)"

/// The signpost log handle and message for one expansion.
///
/// Every generated branch resolves the log handle exactly once, into a local, and
/// builds its `OSSignposter` from that local rather than reaching for
/// `Self.signposter`. Two reasons, both correctness rather than style:
///
/// - A begin and its end are paired by log handle, so the handle a `.begin`
///   records in its ``SignpostInterval`` must be the same object it emitted
///   through. Resolving once makes that hold by construction instead of relying
///   on two accessors agreeing.
/// - `_signpostLog(for:)` takes a lock to consult a cache; naming it twice in one
///   branch would pay for it twice.
struct SignpostExpansionContext {
    /// Source text resolving the log handle, e.g. `Self._signpostLog` or
    /// `Self._signpostLog(for: .pointsOfInterest)`.
    let logExpression: String

    /// The message argument as written, or `nil` when the call has no message.
    let messageExpression: ExprSyntax?

    /// The legacy format derived from ``messageExpression``.
    var legacyFormat: LegacyOSLogFormat? {
        messageExpression.map { buildLegacyOSLogFormat(from: $0) }
    }

    /// The trailing `, message` for the modern API, or the empty string.
    var modernMessageArgument: String {
        messageExpression.map { ", \($0.trimmedDescription)" } ?? ""
    }

    /// Renders an `os_signpost` call, wrapped in `withCString` scopes when the
    /// message interpolates anything.
    func legacyCall(
        type: String,
        nameExpression: String,
        signpostIDExpression: String,
        continuationIndent: Int
    ) -> String {
        let call = "os_signpost(.\(type), log: signpostLog, name: \(nameExpression), signpostID: \(signpostIDExpression)"
        guard let legacyFormat else {
            return call + ")"
        }
        return legacyFormat.wrappingInCStringScopes(
            call + ", \(legacyFormat.formatLiteral)\(legacyFormat.argumentList))",
            continuationIndent: continuationIndent
        )
    }
}

// MARK: - #signpost

public struct SignpostMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = Array(node.arguments)
        guard let typeArgument = arguments.first?.expression,
              let memberAccess = typeArgument.as(MemberAccessExprSyntax.self) else {
            throw SignpostMacroError.missingType
        }

        let unlabeledArguments = arguments.filter { $0.label == nil }.dropFirst().map(\.expression)
        let categoryExpression = arguments.first { $0.label?.text == "category" }?.expression
        let identifierExpression = arguments.first { $0.label?.text == "id" }?.expression

        let logExpression: String = if let categoryExpression {
            // Transplanted verbatim, as `#log` does with its category: it
            // re-type-checks against the generated accessor's `LogCategory`
            // parameter, so leading-dot references keep working.
            "Self._signpostLog(for: \(categoryExpression.trimmedDescription))"
        } else {
            "Self._signpostLog"
        }

        switch memberAccess.declName.baseName.text {
        case "event":
            guard let nameExpression = unlabeledArguments.first else {
                throw SignpostMacroError.missingName
            }
            return expandEvent(
                nameExpression: nameExpression.trimmedDescription,
                identifierExpression: identifierExpression?.trimmedDescription ?? ".exclusive",
                expansionContext: SignpostExpansionContext(
                    logExpression: logExpression,
                    messageExpression: unlabeledArguments.dropFirst().first
                )
            )

        case "begin":
            guard let nameExpression = unlabeledArguments.first else {
                throw SignpostMacroError.missingName
            }
            return expandBegin(
                nameExpression: nameExpression.trimmedDescription,
                identifierExpression: identifierExpression?.trimmedDescription,
                expansionContext: SignpostExpansionContext(
                    logExpression: logExpression,
                    messageExpression: unlabeledArguments.dropFirst().first
                )
            )

        case "end":
            guard let intervalExpression = unlabeledArguments.first else {
                throw SignpostMacroError.missingInterval
            }
            return expandEnd(
                intervalExpression: intervalExpression.trimmedDescription,
                // A bare identifier can be read twice for free; anything else may
                // have side effects and has to be bound to a local first.
                isSimpleReference: intervalExpression.is(DeclReferenceExprSyntax.self),
                messageExpression: unlabeledArguments.dropFirst().first
            )

        default:
            throw SignpostMacroError.unknownType(memberAccess.declName.baseName.text)
        }
    }
}

// MARK: - .event

private func expandEvent(
    nameExpression: String,
    identifierExpression: String,
    expansionContext: SignpostExpansionContext
) -> ExprSyntax {
    let legacyCall = expansionContext.legacyCall(
        type: "event",
        nameExpression: nameExpression,
        signpostIDExpression: identifierExpression,
        continuationIndent: 8
    )
    return """
    {
        let signpostLog = \(raw: expansionContext.logExpression)
        if \(raw: signposterAvailabilityCondition) {
            os.OSSignposter(logHandle: signpostLog).emitEvent(\(raw: nameExpression), id: \(raw: identifierExpression)\(raw: expansionContext.modernMessageArgument))
        } else {
            \(raw: legacyCall)
        }
    }()
    """
}

// MARK: - .begin

private func expandBegin(
    nameExpression: String,
    identifierExpression: String?,
    expansionContext: SignpostExpansionContext
) -> ExprSyntax {
    // Default to an identifier derived from the very handle being emitted
    // through, so several intervals of one name can be in flight at once.
    let signpostIDBinding = identifierExpression ?? "os.OSSignpostID(log: signpostLog)"
    let legacyCall = expansionContext.legacyCall(
        type: "begin",
        nameExpression: nameExpression,
        signpostIDExpression: "signpostID",
        // The `else` branch below sits eight spaces in, same as the other forms.
        continuationIndent: 8
    )
    return """
    {
        let signpostLog = \(raw: expansionContext.logExpression)
        let signpostID = \(raw: signpostIDBinding)
        if \(raw: signposterAvailabilityCondition) {
            let intervalState = os.OSSignposter(logHandle: signpostLog).beginInterval(\(raw: nameExpression), id: signpostID\(raw: expansionContext.modernMessageArgument))
            return SignpostInterval(name: \(raw: nameExpression), signpostID: signpostID, log: signpostLog, intervalState: intervalState)
        } else {
            \(raw: legacyCall)
            return SignpostInterval(name: \(raw: nameExpression), signpostID: signpostID, log: signpostLog, intervalState: nil)
        }
    }()
    """
}

// MARK: - .end

/// Self-contained by design: everything comes off the interval token, so an
/// interval can be closed from a type that is not itself `@Signpostable`, and it
/// closes on the very handle it began on.
private func expandEnd(
    intervalExpression: String,
    isSimpleReference: Bool,
    messageExpression: ExprSyntax?
) -> ExprSyntax {
    // A bare identifier is read directly; anything else is bound once, so an
    // expression with side effects is not evaluated per member access.
    let intervalReference = isSimpleReference ? intervalExpression : "signpostInterval"
    let intervalBinding = isSimpleReference ? "" : "let signpostInterval = \(intervalExpression)\n    "

    let expansionContext = SignpostExpansionContext(
        logExpression: "\(intervalReference).log",
        messageExpression: messageExpression
    )
    let legacyCall = expansionContext.legacyCall(
        type: "end",
        nameExpression: "\(intervalReference).name",
        signpostIDExpression: "\(intervalReference).signpostID",
        continuationIndent: 8
    )
    return """
    {
        \(raw: intervalBinding)let signpostLog = \(raw: intervalReference).log
        if \(raw: signposterAvailabilityCondition) {
            os.OSSignposter(logHandle: signpostLog).endInterval(\(raw: intervalReference).name, \(raw: intervalReference).osSignpostIntervalState\(raw: expansionContext.modernMessageArgument))
        } else {
            \(raw: legacyCall)
        }
    }()
    """
}

// MARK: - #signpostInterval

public struct SignpostIntervalMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = Array(node.arguments)

        guard let nameExpression = arguments.first(where: { $0.label == nil })?.expression else {
            throw SignpostMacroError.missingName
        }
        let categoryExpression = arguments.first { $0.label?.text == "category" }?.expression
        let identifierExpression = arguments.first { $0.label?.text == "id" }?.expression

        // The body arrives either as a trailing closure or as `around:`.
        let bodyClosure = node.trailingClosure
            ?? arguments.first { $0.label?.text == "around" }?.expression.as(ClosureExprSyntax.self)
        guard let bodyClosure else {
            throw SignpostMacroError.missingBody
        }

        let logExpression: String = if let categoryExpression {
            "Self._signpostLog(for: \(categoryExpression.trimmedDescription))"
        } else {
            "Self._signpostLog"
        }
        let expansionContext = SignpostExpansionContext(
            logExpression: logExpression,
            messageExpression: nil
        )

        let beginExpansion = expandBegin(
            nameExpression: nameExpression.trimmedDescription,
            identifierExpression: identifierExpression?.trimmedDescription,
            expansionContext: expansionContext
        )
        let endExpansion = expandEnd(
            intervalExpression: "signpostInterval",
            isSimpleReference: true,
            messageExpression: nil
        )

        // The body is spliced in verbatim and exactly once — not once per
        // `#available` branch, which would compile the measured code twice. The
        // version branching lives inside the begin and end expansions instead.
        //
        // No `try` / `await` is inserted here either: whatever effects the body
        // has are in the text being spliced, so the compiler infers them for the
        // enclosing closure and the call site spells them as the body demands.
        return """
        {
            let signpostInterval = \(raw: indent(beginExpansion.trimmedDescription, by: 4).trimmingLeadingSpaces())
            defer {
        \(raw: indent(endExpansion.trimmedDescription, by: 8))
            }
        \(raw: indent(bodySource(of: bodyClosure), by: 4))
        }()
        """
    }
}

/// The body's statements, with `return` supplied for a single-expression closure
/// (which relies on the implicit return the closure form allows and the spliced
/// form does not).
private func bodySource(of closure: ClosureExprSyntax) -> String {
    let statements = closure.statements
    if statements.count == 1,
       let onlyStatement = statements.first,
       case .expr = onlyStatement.item {
        return "return \(onlyStatement.item.trimmedDescription)"
    }
    return statements
        .map { $0.trimmedDescription }
        .joined(separator: "\n")
}

private extension String {
    func trimmingLeadingSpaces() -> String {
        String(drop(while: { $0 == " " }))
    }
}

// MARK: - Errors

enum SignpostMacroError: Error, CustomStringConvertible {
    case missingType
    case missingName
    case missingInterval
    case missingBody
    case unknownType(String)

    var description: String {
        switch self {
        case .missingType:
            return "#signpost requires a signpost type as the first argument (.event, .begin, or .end)"
        case .missingName:
            return "#signpost requires a signpost name literal"
        case .missingInterval:
            return "#signpost(.end, …) requires the SignpostInterval returned by #signpost(.begin, …)"
        case .missingBody:
            return "#signpostInterval requires a body closure"
        case .unknownType(let name):
            return "#signpost does not support '.\(name)' — use .event, .begin, or .end"
        }
    }
}
