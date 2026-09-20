//
//  Adapted from lexic by Ordo One (https://github.com/ordo-one/lexic),
//  distributed under the Apache License 2.0. See LICENSES/lexic-LICENSE.
//

import SwiftSyntax

extension TokenSyntax {
    /// The token's text with any leading and trailing backticks stripped, so
    /// that a case named `` `default` `` compares equal to `"default"`.
    public var unescaped: Substring {
        var text: Substring = self.text[...]
        text = text.drop { $0 == "`" }
        while text.last == "`" {
            text.removeLast()
        }
        return text
    }
}
