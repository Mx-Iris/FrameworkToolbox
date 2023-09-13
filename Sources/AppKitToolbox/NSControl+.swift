#if canImport(AppKit)

import AppKit
import FrameworkToolbox
import CoreGraphicsToolbox

public extension FrameworkToolbox where Base: NSControl {
    func heightForWidth(_ width: CGFloat) -> CGFloat {
        base.sizeThatFits(NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
    }

    var bestHeight: CGFloat {
        base.sizeThatFits(NSSize.box.max).height
    }

    var bestWidth: CGFloat {
        base.sizeThatFits(NSSize.box.max).width
    }

    var bestSize: NSSize {
        base.sizeThatFits(NSSize.box.max)
    }
}

#endif
