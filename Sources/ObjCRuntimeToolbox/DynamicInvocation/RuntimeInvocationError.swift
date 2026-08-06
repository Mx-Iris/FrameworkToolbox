//
//  Adapted from Dynamic by Mhd Hejazi (https://github.com/mhdhejazi/Dynamic),
//  distributed under the Apache License 2.0. See LICENSES/Dynamic-LICENSE.
//

#if canImport(ObjectiveC)
import Foundation

/// Why a dynamic message could not be sent.
///
/// Conforms to `CustomNSError` so the value survives the trip through
/// `AnyObject`: ``DynamicObject`` propagates a failure by carrying it as the
/// wrapped object, and bridging to `NSError` is what lets `asObject is Error`
/// and ``DynamicObject/isError`` still recognise it on the far side.
public enum RuntimeInvocationError: Error, CustomNSError, CustomStringConvertible {
    /// The receiver has no method for this selector.
    case unrecognizedSelector(className: String, selectorName: String)

    /// `+[NSInvocation invocationWithMethodSignature:]` returned nothing for a
    /// signature the receiver itself had just vended.
    case invocationCreationFailed(className: String, selectorName: String)

    /// The selector expects a different number of arguments than were supplied.
    ///
    /// Sending anyway would read past the end of the argument list, so the call
    /// is refused instead.
    case argumentCountMismatch(selectorName: String, expectedCount: Int, providedCount: Int)

    public static var errorDomain: String { "ObjCRuntimeToolbox.RuntimeInvocation" }

    public var errorCode: Int {
        switch self {
        case .unrecognizedSelector: 404
        case .invocationCreationFailed: 500
        case .argumentCountMismatch: 400
        }
    }

    public var description: String {
        switch self {
        case let .unrecognizedSelector(className, selectorName):
            "'\(className)' doesn't recognize selector '\(selectorName)'"
        case let .invocationCreationFailed(className, selectorName):
            "Could not build an NSInvocation for '[\(className) \(selectorName)]'"
        case let .argumentCountMismatch(selectorName, expectedCount, providedCount):
            """
            '\(selectorName)' takes \(expectedCount) argument(s) \
            but \(providedCount) were provided
            """
        }
    }

    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: description]
    }
}

#endif
