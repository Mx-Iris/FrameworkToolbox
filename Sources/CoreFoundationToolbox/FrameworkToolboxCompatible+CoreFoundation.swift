import CoreFoundation
import FrameworkToolbox

/// All CoreFoundation types that conform to ``CFType`` automatically gain
/// the `box` namespace via this macro-generated protocol extension.
///
/// `CFType` is class-bound, hence `referenceSemantics: true` — without it the
/// generated `box` setter assigns `self`, which a class-bound protocol
/// extension's setter cannot do, and the compiler crashes instead of saying so.
@FrameworkToolboxExtension(referenceSemantics: true)
extension CFType {}

// MARK: - CF Value Types

extension CFRange: FrameworkToolboxCompatible, FrameworkToolboxDynamicMemberLookup {}
