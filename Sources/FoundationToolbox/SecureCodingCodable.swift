import Foundation

/// An `NSObject` subclass that is `Codable` through its `NSCoding` implementation.
///
/// The object is encoded as one `NSKeyedArchiver` archive stored as a single `Data` value, so the
/// surrounding format sees an opaque blob — a Base64 string in JSON.
///
/// - Important: Decoding turns secure coding off, which lets the archive instantiate any class it
///   names. Only decode data that you produced or otherwise trust, and adopt ``SecureCodingCodable``
///   whenever the class supports `NSSecureCoding`.
///
/// Failures are thrown as `EncodingError` / `DecodingError` carrying the coding path, with
/// Foundation's own error as the underlying error.
public protocol CodingCodable: NSObject, NSCoding, Codable {}

extension CodingCodable {
    public func encode(to encoder: any Encoder) throws {
        try encodeKeyedArchive(to: encoder, requiringSecureCoding: false)
    }
}

// The initializers are declared on `Decodable` rather than on the two protocols because only there
// may they assign to `self`: in an extension of a class-bound protocol, `self` is immutable.
extension Decodable where Self: CodingCodable {
    public init(from decoder: any Decoder) throws {
        self = try Self.decodeKeyedArchive(from: decoder, requiringSecureCoding: false)
    }
}

/// An `NSObject` subclass that is `Codable` through its `NSSecureCoding` implementation.
///
/// Stored the same way as ``CodingCodable``. Archiving and unarchiving both follow the class's
/// `supportsSecureCoding`, so whatever was archived can be unarchived; a class that reports `false`
/// is read without secure coding and carries the same caveat as ``CodingCodable``.
public protocol SecureCodingCodable: CodingCodable, NSSecureCoding {}

extension SecureCodingCodable {
    public func encode(to encoder: any Encoder) throws {
        try encodeKeyedArchive(to: encoder, requiringSecureCoding: Self.supportsSecureCoding)
    }
}

extension Decodable where Self: SecureCodingCodable {
    public init(from decoder: any Decoder) throws {
        self = try Self.decodeKeyedArchive(from: decoder, requiringSecureCoding: Self.supportsSecureCoding)
    }
}

extension CodingCodable {
    fileprivate func encodeKeyedArchive(to encoder: any Encoder, requiringSecureCoding: Bool) throws {
        let archive: Data
        do {
            archive = try NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: requiringSecureCoding)
        } catch {
            throw EncodingError.invalidValue(self, EncodingError.Context(
                codingPath: encoder.codingPath,
                debugDescription: "NSKeyedArchiver could not archive \(String(reflecting: Self.self)) (requiringSecureCoding: \(requiringSecureCoding)): \(foundationReason(for: error))",
                underlyingError: error
            ))
        }
        var container = encoder.singleValueContainer()
        try container.encode(archive)
    }

    /// Reads the archive with an unarchiver rather than `NSKeyedUnarchiver.unarchivedObject(ofClass:from:)`:
    /// that method compiles for any `NSCoding` class but always turns secure coding on, so it rejects
    /// every class this protocol exists for.
    fileprivate static func decodeKeyedArchive(from decoder: any Decoder, requiringSecureCoding: Bool) throws -> Self {
        let typeName = String(reflecting: Self.self)
        let container = try decoder.singleValueContainer()
        let archive: Data
        do {
            archive = try container.decode(Data.self)
        } catch DecodingError.typeMismatch(let expectedType, let context) {
            throw DecodingError.typeMismatch(expectedType, DecodingError.Context(
                codingPath: context.codingPath,
                debugDescription: "\(typeName) is stored as a single NSKeyedArchiver archive (Data). \(context.debugDescription)",
                underlyingError: context.underlyingError
            ))
        }

        let rootObject: Any?
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archive)
            unarchiver.requiresSecureCoding = requiringSecureCoding
            defer { unarchiver.finishDecoding() }
            rootObject = try unarchiver.decodeTopLevelObject(of: [Self.self], forKey: NSKeyedArchiveRootObjectKey)
        } catch {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "NSKeyedUnarchiver could not unarchive \(typeName) from \(archive.count) bytes (requiresSecureCoding: \(requiringSecureCoding)): \(foundationReason(for: error))",
                underlyingError: error
            ))
        }

        guard let rootObject else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "The NSKeyedArchiver archive has no root object under the key \"\(NSKeyedArchiveRootObjectKey)\"; expected \(typeName)."
            ))
        }
        // With secure coding off, Foundation ignores the class list, so the class is checked here.
        guard let decodedObject = rootObject as? Self else {
            throw DecodingError.typeMismatch(Self.self, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected the archive's root object to be \(typeName), but found \(String(reflecting: type(of: rootObject)))."
            ))
        }
        return decodedObject
    }
}

/// The reason Foundation gives for an archiving failure.
///
/// The `localizedDescription` of these errors is often a generic "isn't in the correct format"; the
/// actual reason is the `NSDebugDescription` of the error itself or of an error underneath it.
private func foundationReason(for error: any Error) -> String {
    var currentError: NSError? = error as NSError
    while let foundationError = currentError {
        if let debugDescription = foundationError.userInfo[NSDebugDescriptionErrorKey] as? String {
            return debugDescription
        }
        currentError = foundationError.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return error.localizedDescription
}
