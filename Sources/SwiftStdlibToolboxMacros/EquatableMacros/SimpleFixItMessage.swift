/// Source: https://github.com/ordo-one/equatable

import SwiftDiagnostics
import SwiftSyntax

struct SimpleFixItMessage: FixItMessage {
    let message: String
    let fixItID: MessageID
}
