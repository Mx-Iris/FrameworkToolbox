import Foundation
import Security

/// Errors thrown by ``KeychainStorage`` when the underlying Keychain Services
/// call fails.
public enum KeychainError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The Security framework returned a non-success `OSStatus`.
    case unhandled(OSStatus)
    /// A value could not be decoded from the bytes stored in the Keychain.
    case decodingFailed

    public var description: String {
        switch self {
        case .unhandled(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "KeychainError.unhandled(status: \(status), message: \(message))"
        case .decodingFailed:
            return "KeychainError.decodingFailed"
        }
    }
}
