#if canImport(AppKit)

import AppKit

public extension NSNib {
    convenience init?<View: NSView>(nibClass: View.Type) {
        self.init(nibNamed: .init(describing: nibClass), bundle: .main)
    }
}

#endif
