#if canImport(AppKit)

import AppKit
import FrameworkToolbox

public extension FrameworkToolbox where Base: NSObject {
    static var typeNameIdentifier: NSUserInterfaceItemIdentifier {
        .init(String(describing: self))
    }
}


#endif
