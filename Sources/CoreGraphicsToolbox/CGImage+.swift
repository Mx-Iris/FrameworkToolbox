#if canImport(CoreGraphics)

import CoreGraphics
import FrameworkToolbox

#if canImport(AppKit)
import AppKit

public extension FrameworkToolbox where Base: CGImage {
    var nsImage: NSImage? {
        let size = CGSize(width: base.width, height: base.height)
        return NSImage(cgImage: base, size: size)
    }
}
#endif

#if canImport(UIKit)

import UIKit

public extension FrameworkToolbox where Base: CGImage {
    var uiImage: UIImage? {
        return .init(cgImage: base)
    }
}
#endif

#if canImport(CoreImage)

import CoreImage

public extension FrameworkToolbox where Base: CGImage {
    var ciImage: CIImage {
        return CIImage(cgImage: base)
    }
}

#endif

#endif
