import Foundation
import FrameworkToolbox

extension URL: FrameworkToolboxCompatible, FrameworkToolboxDynamicMemberLookup {}
extension Date: FrameworkToolboxCompatible, FrameworkToolboxDynamicMemberLookup {}
extension Data: FrameworkToolboxDynamicMemberLookup {}

extension NSRange: FrameworkToolboxDynamicMemberLookup {}
