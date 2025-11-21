import SwiftSyntax

/// Source: https://github.com/ordo-one/equatable

extension VariableDeclSyntax {
    var isStatic: Bool {
        self.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.static)
        }
    }
}
