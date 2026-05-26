import CoreFoundation
import FrameworkToolbox

extension FrameworkToolbox<CFError> {

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        domain: CFError.Domain,
        code: CFIndex,
        userInfo: [CFError.UserInfoKey: Any] = [:]
    ) -> CFError {
        CFErrorCreate(allocator, domain.rawValue, code, FrameworkToolbox<CFDictionary>.from(userInfo))
    }

    @inlinable
    public var domain: CFError.Domain {
        CFError.Domain(CFErrorGetDomain(base))
    }

    @inlinable
    public var code: CFIndex {
        CFErrorGetCode(base)
    }

    @inlinable
    public func userInfo() -> [CFError.UserInfoKey: Any] {
        CFErrorCopyUserInfo(base)?.box.asSwift() ?? [:]
    }

    @inlinable
    public func description() -> CFString? {
        CFErrorCopyDescription(base)
    }

    @inlinable
    public func failureReason() -> CFString? {
        CFErrorCopyFailureReason(base)
    }

    @inlinable
    public func recoverySuggestion() -> CFString? {
        CFErrorCopyRecoverySuggestion(base)
    }
}

// MARK: - Domain

extension CFError {

    public struct Domain: CFStringKey {

        public let rawValue: CFString

        public init(_ key: CFString) {
            rawValue = key
        }
    }
}

extension CFError.Domain {
    public static let posix = CFError.Domain(kCFErrorDomainPOSIX)
    public static let osStatus = CFError.Domain(kCFErrorDomainOSStatus)
    public static let mach = CFError.Domain(kCFErrorDomainMach)
    public static let cocoa = CFError.Domain(kCFErrorDomainCocoa)
}

// MARK: - UserInfoKey

extension CFError {

    public struct UserInfoKey: CFStringKey {

        public let rawValue: CFString

        public init(_ key: CFString) {
            rawValue = key
        }
    }
}

extension CFError.UserInfoKey {
    public static let localizedDescription = CFError.UserInfoKey(kCFErrorLocalizedDescriptionKey)
    @available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    public static let localizedFailure = CFError.UserInfoKey(kCFErrorLocalizedFailureKey)
    public static let localizedFailureReason = CFError.UserInfoKey(kCFErrorLocalizedFailureReasonKey)
    public static let localizedRecoverySuggestion = CFError.UserInfoKey(kCFErrorLocalizedRecoverySuggestionKey)
    public static let description = CFError.UserInfoKey(kCFErrorDescriptionKey)
    public static let underlyingError = CFError.UserInfoKey(kCFErrorUnderlyingErrorKey)
    public static let url = CFError.UserInfoKey(kCFErrorURLKey)
    public static let filePath = CFError.UserInfoKey(kCFErrorFilePathKey)
}
