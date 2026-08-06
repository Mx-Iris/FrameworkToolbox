import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DyldDynamicInterposeMacro: PeerMacro {
    /// `__dyn_interpose` deliberately differs from dyld's own `__interpose`:
    /// dyld must not pick these tuples up at load time, because the whole
    /// point of the dynamic variant is that the program decides when they
    /// take effect.
    private static let configuration = DyldInterposeExpansionConfiguration(
        attributeName: "@DyldDynamicInterpose",
        sectionName: "__DATA,__dyn_interpose",
        constantNamePrefix: "_dyldDynamicInterpose_"
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
