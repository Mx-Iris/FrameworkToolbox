import Foundation
import Security

/// Accessibility classes for keychain items, mirroring the `kSecAttrAccessible*` constants.
///
/// Maps to the underlying `CFString` constants documented under
/// "Item Attribute Keys and Values" in the Keychain Services framework.
///
/// > Important: `.whenUnlockedThisDeviceOnly`, `.afterFirstUnlockThisDeviceOnly`,
/// > and `.whenPasscodeSetThisDeviceOnly` are incompatible with
/// > `synchronizable: true`. iCloud Keychain refuses to sync items that are
/// > bound to a single device.
public enum KeychainAccessibility: Sendable, Hashable {
    case whenUnlocked
    case whenUnlockedThisDeviceOnly
    case afterFirstUnlock
    case afterFirstUnlockThisDeviceOnly
    case whenPasscodeSetThisDeviceOnly

    public var rawValue: CFString {
        switch self {
        case .whenUnlocked:
            return kSecAttrAccessibleWhenUnlocked
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlock:
            return kSecAttrAccessibleAfterFirstUnlock
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly:
            return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
    }
}
