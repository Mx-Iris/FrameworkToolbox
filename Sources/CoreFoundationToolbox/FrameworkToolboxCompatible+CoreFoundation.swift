import CoreFoundation
import FrameworkToolbox

/// All CoreFoundation types that conform to ``CFType`` automatically gain
/// the `box` namespace via this macro-generated protocol extension.
///
/// `CFType` is class-bound, so the generated `box` setter must not assign
/// `self` — a class-bound protocol extension's setter cannot, and the compiler
/// crashes instead of saying so. The macro gets that right on its own: the
/// compiler picks the setter from `Self: AnyObject`.
@FrameworkToolboxExtension
extension CFType {}

// MARK: - CF Value Types

extension CFRange: FrameworkToolboxCompatible, FrameworkToolboxDynamicMemberLookup {}
