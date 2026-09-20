//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import MacroToolbox
import SwiftSyntax
import SwiftSyntaxMacros

/// Marks the `static func` that `@Projection` should build a property from.
///
/// Generates nothing. It exists so that the function's own declaration names
/// the projection, instead of a string in the enumeration's attribute naming
/// it a second time.
public struct ProjectionFunctionMacro: PeerMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        // This macro owns every diagnostic about the function it is attached
        // to: it has the declaration in hand, so it can point at the exact
        // token. `@Projection` skips whatever fails these checks rather than
        // reporting the same mistake a second time.
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            context[.error, declaration] = """
            '@ProjectionFunction' must be applied to a function
            """
            return []
        }

        guard function.isStatic else {
            context[.error, function.name] = """
            '@ProjectionFunction' must be applied to a static function — \
            '@Projection' calls it as 'Self.\(function.name.text)(…)'
            """
            return []
        }

        guard function.signature.returnClause != nil else {
            context[.error, function.name] = """
            a projection function must have a return type
            """
            return []
        }

        return []
    }
}

extension ProjectionFunctionMacro {
    struct Configuration {
        let flatten: Bool
    }
}

extension ProjectionFunctionMacro.Configuration: ExpressionListDecodable {
    enum ArgumentKey: String, Sendable {
        case flatten
    }

    init(from arguments: inout ExpressionListDecoder<ArgumentKey>) throws {
        self.init(flatten: try arguments[.flatten]?.decode() ?? true)
    }
}

extension FunctionDeclSyntax {
    var isStatic: Bool {
        modifiers.contains { modifier in modifier.name.text == "static" }
    }
}
