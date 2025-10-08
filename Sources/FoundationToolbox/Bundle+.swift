import Foundation
import FrameworkToolbox

extension FrameworkToolbox where Base: Bundle {
    public var name: String {
        object(for: .name, defaultValue: "")
    }

    public var shortVersionString: String {
        object(for: .shortVersionString, defaultValue: "")
    }

    public var version: String {
        object(for: .version, defaultValue: "")
    }

    public var identifier: String {
        object(for: .identifier, defaultValue: "")
    }

    public var iconFile: String {
        object(for: .iconFile, defaultValue: "")
    }

    public func object<T>(for infoDictionaryKey: BundleInfoDictionaryKey, defaultValue: T) -> T {
        base.infoDictionary?[infoDictionaryKey.rawValue] as? T ?? defaultValue
    }
}

public enum BundleInfoDictionaryKey: String {
    case name = "CFBundleName"
    case shortVersionString = "CFBundleShortVersionString"
    case version = "CFBundleVersion"
    case identifier = "CFBundleIdentifier"
    case iconFile = "CFBundleIconFile"
}
