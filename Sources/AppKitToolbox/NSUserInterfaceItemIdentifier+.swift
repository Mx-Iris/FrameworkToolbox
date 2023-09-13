#if canImport(AppKit)

import AppKit

extension NSUserInterfaceItemIdentifier: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}

#endif
