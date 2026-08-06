import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DyldInterposeMacro: PeerMacro {
    private static let configuration = DyldInterposeExpansionConfiguration(
        attributeName: "@DyldInterpose",
        sectionName: "__DATA,__interpose",
        constantNamePrefix: "_dyldInterpose_"
    )

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try DyldInterposeSupport.makeInterposeTupleDeclarations(
            of: node,
            providingPeersOf: declaration,
            configuration: configuration
        )
    }
}
