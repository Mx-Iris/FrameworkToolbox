import Foundation
import Testing

import FoundationToolbox

@Suite
struct CodingCodableTests {

    // MARK: - Round trips

    @Test("a class that adopts only NSCoding round-trips through JSON")
    func codingOnlyClassRoundTrips() throws {
        let encoded = try JSONEncoder().encode(Shelf(item: LegacyBookmark(title: "Swift")))
        let decoded = try JSONDecoder().decode(Shelf<LegacyBookmark>.self, from: encoded)
        #expect(decoded.item.title == "Swift")
    }

    @Test("a class that adopts NSSecureCoding round-trips through JSON")
    func secureCodingClassRoundTrips() throws {
        let encoded = try JSONEncoder().encode(Shelf(item: SecureBookmark(title: "Swift")))
        let decoded = try JSONDecoder().decode(Shelf<SecureBookmark>.self, from: encoded)
        #expect(decoded.item.title == "Swift")
    }

    @Test("a secure-coding class whose supportsSecureCoding is false round-trips through JSON")
    func classOptingOutOfSecureCodingRoundTrips() throws {
        let encoded = try JSONEncoder().encode(Shelf(item: OptedOutBookmark(title: "Swift")))
        let decoded = try JSONDecoder().decode(Shelf<OptedOutBookmark>.self, from: encoded)
        #expect(decoded.item.title == "Swift")
    }

    // MARK: - Errors

    @Test("an archiving failure is an invalidValue naming the type and Foundation's reason")
    func archivingFailureIsDescribed() throws {
        let folder = SecureFolder(bookmark: LegacyBookmark(title: "Swift"))
        let error = try #require(throws: EncodingError.self) {
            try JSONEncoder().encode(Shelf(item: folder))
        }
        guard case .invalidValue(_, let context) = error else {
            Issue.record("Expected EncodingError.invalidValue, got \(error)")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["item"])
        #expect(context.debugDescription.contains("SecureFolder"))
        #expect(
            context.debugDescription.contains("LegacyBookmark"),
            "Foundation's reason names the class that does not adopt NSSecureCoding"
        )
        #expect(context.underlyingError != nil)
    }

    @Test("a payload that is not Data is a typeMismatch saying the type is stored as an archive")
    func nonDataPayloadIsDescribed() throws {
        let encodedShelf = Data(#"{"item":{"title":"Swift"}}"#.utf8)
        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(Shelf<LegacyBookmark>.self, from: encodedShelf)
        }
        guard case .typeMismatch(_, let context) = error else {
            Issue.record("Expected DecodingError.typeMismatch, got \(error)")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["item"])
        #expect(context.debugDescription.contains("LegacyBookmark"))
        #expect(context.debugDescription.contains("NSKeyedArchiver"))
    }

    @Test("bytes that are not a keyed archive are dataCorrupted naming the type")
    func unreadableArchiveIsDescribed() throws {
        let encodedShelf = Data(#"{"item":"AAECAw=="}"#.utf8)
        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(Shelf<LegacyBookmark>.self, from: encodedShelf)
        }
        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected DecodingError.dataCorrupted, got \(error)")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["item"])
        #expect(context.debugDescription.contains("LegacyBookmark"))
        #expect(context.underlyingError != nil)
    }

    @Test("an archive of another class, read without secure coding, is a typeMismatch naming both classes")
    func rootObjectOfAnotherClassIsDescribed() throws {
        let encodedShelf = try JSONEncoder().encode(Shelf(item: SecureBookmark(title: "Swift")))
        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(Shelf<LegacyBookmark>.self, from: encodedShelf)
        }
        guard case .typeMismatch(let expectedType, let context) = error else {
            Issue.record("Expected DecodingError.typeMismatch, got \(error)")
            return
        }
        #expect(expectedType == LegacyBookmark.self)
        #expect(context.codingPath.map(\.stringValue) == ["item"])
        #expect(context.debugDescription.contains("SecureBookmark"))
    }

    @Test("an archive of another class, read with secure coding, is dataCorrupted carrying Foundation's reason")
    func secureDecodingOfAnotherClassIsDescribed() throws {
        let encodedShelf = try JSONEncoder().encode(Shelf(item: LegacyBookmark(title: "Swift")))
        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(Shelf<SecureBookmark>.self, from: encodedShelf)
        }
        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected DecodingError.dataCorrupted from the secure-coding path, got \(error)")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["item"])
        #expect(context.debugDescription.contains("SecureBookmark"))
        #expect(
            context.debugDescription.contains("LegacyBookmark"),
            "Foundation's reason names the class it found in the archive"
        )
        #expect(context.underlyingError != nil)
    }

    @Test("an archive without a root object is dataCorrupted mentioning the root key")
    func archiveWithoutRootObjectIsDescribed() throws {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode("Swift" as NSString, forKey: "notTheRoot")
        archiver.finishEncoding()
        let encodedShelf = try JSONEncoder().encode(Shelf(item: archiver.encodedData))
        let error = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(Shelf<LegacyBookmark>.self, from: encodedShelf)
        }
        guard case .dataCorrupted(let context) = error else {
            Issue.record("Expected DecodingError.dataCorrupted, got \(error)")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["item"])
        #expect(context.debugDescription.contains(NSKeyedArchiveRootObjectKey))
        #expect(context.debugDescription.contains("LegacyBookmark"))
    }
}

// MARK: - Fixtures

/// Puts the value under a key, so that a failure reports a non-empty coding path.
private struct Shelf<Item: Codable>: Codable {
    var item: Item
}

/// Adopts `NSCoding` only, so its archive can be read back only with secure coding off.
final class LegacyBookmark: NSObject, CodingCodable {
    let title: String

    init(title: String) {
        self.title = title
    }

    func encode(with coder: NSCoder) {
        coder.encode(title, forKey: "title")
    }

    init?(coder: NSCoder) {
        guard let title = coder.decodeObject(forKey: "title") as? String else { return nil }
        self.title = title
    }
}

final class SecureBookmark: NSObject, SecureCodingCodable {
    static var supportsSecureCoding: Bool { true }

    let title: String

    init(title: String) {
        self.title = title
    }

    func encode(with coder: NSCoder) {
        coder.encode(title, forKey: "title")
    }

    init?(coder: NSCoder) {
        guard let title = coder.decodeObject(of: NSString.self, forKey: "title") as String? else { return nil }
        self.title = title
    }
}

/// Adopts `NSSecureCoding` but holds an object that does not, so archiving it with secure coding fails.
final class SecureFolder: NSObject, SecureCodingCodable {
    static var supportsSecureCoding: Bool { true }

    let bookmark: LegacyBookmark

    init(bookmark: LegacyBookmark) {
        self.bookmark = bookmark
    }

    func encode(with coder: NSCoder) {
        coder.encode(bookmark, forKey: "bookmark")
    }

    init?(coder: NSCoder) {
        guard let bookmark = coder.decodeObject(of: LegacyBookmark.self, forKey: "bookmark") else { return nil }
        self.bookmark = bookmark
    }
}

/// Adopts `NSSecureCoding` yet reports that it does not support it, as a subclass whose
/// `init(coder:)` is not secure-coding compliant may.
final class OptedOutBookmark: NSObject, SecureCodingCodable {
    static var supportsSecureCoding: Bool { false }

    let title: String

    init(title: String) {
        self.title = title
    }

    func encode(with coder: NSCoder) {
        coder.encode(title, forKey: "title")
    }

    init?(coder: NSCoder) {
        guard let title = coder.decodeObject(forKey: "title") as? String else { return nil }
        self.title = title
    }
}
