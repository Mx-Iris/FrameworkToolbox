//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

/// An error that already knows which piece of syntax it should be reported
/// against, so a macro can turn it into a diagnostic without having to
/// remember where it came from.
public protocol MacroExpansionError<Node>: Error {
    associatedtype Node: SyntaxProtocol

    var node: Node { get }
}
