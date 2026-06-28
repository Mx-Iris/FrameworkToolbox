import Foundation

/// Errors surfaced by ``UserDefaultStorage`` when reading or writing the
/// underlying `UserDefaults` suite fails.
public enum UserDefaultError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The named suite could not be resolved into a `UserDefaults` instance.
    ///
    /// Typically caused by passing a `suiteName` that doesn't match an app
    /// group entitlement (or is one of the reserved names like `NSGlobalDomain`).
    case unresolvedSuite(String)
    /// A plist object was read from `UserDefaults` but the type could not be
    /// decoded into the declared `Value`.
    case decodingFailed

    public var description: String {
        switch self {
        case .unresolvedSuite(let name):
            return "UserDefaultError.unresolvedSuite(\(name))"
        case .decodingFailed:
            return "UserDefaultError.decodingFailed"
        }
    }
}
