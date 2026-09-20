//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// A `DiagnosticMessage` assembled on the spot from a severity and a string,
/// so that emitting one does not require declaring an error type first.
struct MacroExpansionDiagnosticMessage: DiagnosticMessage {
    let severity: DiagnosticSeverity
    let message: String

    var diagnosticID: MessageID {
        MessageID(domain: "\(Self.self)", id: "\(severity)")
    }
}

extension MacroExpansionContext {
    /// Emits a diagnostic against `node`, or does nothing when assigned `nil`.
    ///
    /// Written as a subscript so that a diagnostic derived from an optional —
    /// `context[.warning, type] = type.unsugaredOptionalDiagnostic` — needs no
    /// surrounding `if let`. Reading it always yields `nil`; there is nothing
    /// to read back.
    public subscript(
        severity: DiagnosticSeverity,
        node: some SyntaxProtocol
    ) -> String? {
        get {
            nil
        }
        set(message) {
            guard let message else { return }

            diagnose(
                Diagnostic(
                    node: node,
                    message: MacroExpansionDiagnosticMessage(
                        severity: severity,
                        message: message
                    )
                )
            )
        }
    }
}
