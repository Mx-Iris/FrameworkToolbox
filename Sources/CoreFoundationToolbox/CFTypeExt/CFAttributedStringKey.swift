import Foundation
import CoreFoundation
import FrameworkToolbox

extension CFAttributedString {

    public struct Key: CFStringKey {

        public let rawValue: CFString

        public init(_ key: CFString) {
            rawValue = key
        }
    }
}

extension CFAttributedString.Key {

    public static func ns(_ key: NSAttributedString.Key) -> CFAttributedString.Key {
        .init(FrameworkToolbox<CFString>.from(key.rawValue))
    }
}

extension NSAttributedString.Key {

    public static func cf(_ key: CFAttributedString.Key) -> NSAttributedString.Key {
        .init(key.rawValue.box.asSwift())
    }
}
