//
//  Adapted from Dynamic by Mhd Hejazi (https://github.com/mhdhejazi/Dynamic),
//  distributed under the Apache License 2.0. See LICENSES/Dynamic-LICENSE.
//

#if canImport(ObjectiveC)
import Foundation

/// Converts between Foundation's paired Swift and Objective-C value types.
///
/// A Swift `String`, `Date`, or `URL` cannot be handed to a method expecting
/// `id`: the callee wants a real object, and the Swift value types are structs
/// that only *bridge* to one. The compiler inserts that bridge automatically
/// when it can see both sides of the call, which is exactly what does not
/// happen here — the signature is discovered at runtime, so the conversion has
/// to be performed explicitly before the argument is written.
///
/// The pairings are Foundation's own; see
/// [Working with Foundation Types](https://developer.apple.com/documentation/swift/imported_c_and_objective-c_apis/working_with_foundation_types).
///
/// > Note: `NSMeasurement` is deliberately absent. `Measurement` is generic
/// > over its unit, and nothing in a type-erased `Any` says which unit to
/// > reconstruct, so there is no correct answer to give.
public enum FoundationTypeBridging {

    private static let typePairs: [(swiftType: Any.Type, objectiveCType: AnyObject.Type)] = [
        ([Any].self, NSArray.self),
        (Calendar.self, NSCalendar.self),
        (CharacterSet.self, NSCharacterSet.self),
        (Data.self, NSData.self),
        (DateComponents.self, NSDateComponents.self),
        (DateInterval.self, NSDateInterval.self),
        (Date.self, NSDate.self),
        (Decimal.self, NSDecimalNumber.self),
        ([AnyHashable: Any].self, NSDictionary.self),
        (IndexPath.self, NSIndexPath.self),
        (IndexSet.self, NSIndexSet.self),
        (Locale.self, NSLocale.self),
        (Notification.self, NSNotification.self),
        (PersonNameComponents.self, NSPersonNameComponents.self),
        (Set<AnyHashable>.self, NSSet.self),
        (String.self, NSString.self),
        (TimeZone.self, NSTimeZone.self),
        (URL.self, NSURL.self),
        (URLComponents.self, NSURLComponents.self),
        (URLQueryItem.self, NSURLQueryItem.self),
        (URLRequest.self, NSURLRequest.self),
        (UUID.self, NSUUID.self),
    ]

    private static let objectiveCTypesBySwiftType: [ObjectIdentifier: AnyObject.Type] = {
        Dictionary(
            uniqueKeysWithValues: typePairs.map { (ObjectIdentifier($0.swiftType), $0.objectiveCType) }
        )
    }()

    private static let swiftTypesByObjectiveCType: [ObjectIdentifier: Any.Type] = {
        Dictionary(
            uniqueKeysWithValues: typePairs.map { (ObjectIdentifier($0.objectiveCType), $0.swiftType) }
        )
    }()

    // MARK: - Type Lookup

    /// The Swift type paired with an Objective-C class, if there is one.
    public static func swiftType(forObjectiveCType objectiveCType: Any.Type) -> Any.Type? {
        swiftTypesByObjectiveCType[ObjectIdentifier(objectiveCType)]
    }

    /// The Objective-C class paired with a Swift type, if there is one.
    public static func objectiveCType(forSwiftType swiftType: Any.Type) -> Any.Type? {
        objectiveCTypesBySwiftType[ObjectIdentifier(swiftType)]
    }

    /// The other half of the pair, whichever half was passed in.
    public static func counterpartType(of type: Any.Type) -> Any.Type? {
        swiftType(forObjectiveCType: type) ?? objectiveCType(forSwiftType: type)
    }

    // MARK: - Value Conversion

    /// Bridges a Swift value to its Objective-C object form.
    ///
    /// - Returns: `nil` when the value is not one of the paired Swift types,
    ///   which callers should read as "leave it alone", not as failure.
    public static func bridgedToObjectiveC(_ value: Any?) -> Any? {
        switch value {
        case is [Any]: value as? NSArray
        case is Calendar: value as? NSCalendar
        case is CharacterSet: value as? NSCharacterSet
        case is Data: value as? NSData
        case is DateComponents: value as? NSDateComponents
        case is DateInterval: value as? NSDateInterval
        case is Date: value as? NSDate
        case is Decimal: value as? NSDecimalNumber
        case is [AnyHashable: Any]: value as? NSDictionary
        case is IndexPath: value as? NSIndexPath
        case is IndexSet: value as? NSIndexSet
        case is Locale: value as? NSLocale
        case is Notification: value as? NSNotification
        case is PersonNameComponents: value as? NSPersonNameComponents
        case is Set<AnyHashable>: value as? NSSet
        case is String: value as? NSString
        case is TimeZone: value as? NSTimeZone
        case is URL: value as? NSURL
        case is URLComponents: value as? NSURLComponents
        case is URLQueryItem: value as? NSURLQueryItem
        case is URLRequest: value as? NSURLRequest
        case is UUID: value as? NSUUID
        default: nil
        }
    }

    /// Bridges an Objective-C object to its Swift value form.
    ///
    /// - Returns: `nil` when the object is not one of the paired classes.
    public static func bridgedToSwift(_ value: Any?) -> Any? {
        switch value {
        case is NSArray: value as? [Any]
        case is NSCalendar: value as? Calendar
        case is NSCharacterSet: value as? CharacterSet
        case is NSData: value as? Data
        case is NSDateComponents: value as? DateComponents
        case is NSDateInterval: value as? DateInterval
        case is NSDate: value as? Date
        case is NSDecimalNumber: value as? Decimal
        case is NSDictionary: value as? [AnyHashable: Any]
        case is NSIndexPath: value as? IndexPath
        case is NSIndexSet: value as? IndexSet
        case is NSLocale: value as? Locale
        case is NSNotification: value as? Notification
        case is NSPersonNameComponents: value as? PersonNameComponents
        case is NSSet: value as? Set<AnyHashable>
        case is NSString: value as? String
        case is NSTimeZone: value as? TimeZone
        case is NSURL: value as? URL
        case is NSURLComponents: value as? URLComponents
        case is NSURLQueryItem: value as? URLQueryItem
        case is NSURLRequest: value as? URLRequest
        case is NSUUID: value as? UUID
        default: nil
        }
    }

    /// Bridges to whichever side the value is not already on.
    public static func bridgedCounterpart(of value: Any?) -> Any? {
        bridgedToObjectiveC(value) ?? bridgedToSwift(value)
    }
}

#endif
