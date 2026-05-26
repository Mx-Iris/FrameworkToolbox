import CoreFoundation
import FrameworkToolbox

/// All CoreFoundation types that conform to ``CFType`` automatically gain
/// the `box` namespace via this macro-generated protocol extension.
@FrameworkToolboxExtension
extension CFType {}

// MARK: - CF Value Types

extension CFRange: FrameworkToolboxCompatible, FrameworkToolboxDynamicMemberLookup {}
