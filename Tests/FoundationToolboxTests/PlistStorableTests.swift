import Foundation
import Testing

@testable import FoundationToolbox

@Suite
struct PlistStorableTests {

    // MARK: - String / Data / Bool

    @Test func stringRoundTrip() {
        let original = "hello, plist 🌍"
        let encoded = original._encodeStorablePlist()
        #expect(encoded as? String == original)
        #expect(String._decodeStorablePlist(encoded) == original)
    }

    @Test func dataRoundTrip() {
        let original = Data([0x00, 0xFF, 0x42, 0x13])
        let encoded = original._encodeStorablePlist()
        #expect(encoded as? Data == original)
        #expect(Data._decodeStorablePlist(encoded) == original)
    }

    @Test func boolRoundTrip() {
        #expect(Bool._decodeStorablePlist(true._encodeStorablePlist()) == true)
        #expect(Bool._decodeStorablePlist(false._encodeStorablePlist()) == false)
        // NSNumber round-trip
        #expect(Bool._decodeStorablePlist(NSNumber(value: true)) == true)
        #expect(Bool._decodeStorablePlist(NSNumber(value: 0)) == false)
        // Non-bool / non-number input must fail.
        #expect(Bool._decodeStorablePlist("yes") == nil)
    }

    // MARK: - Integers

    @Test func intRoundTrip() {
        let value: Int = -123_456_789
        let encoded = value._encodeStorablePlist()
        #expect(Int._decodeStorablePlist(encoded) == value)
    }

    @Test func uintRoundTrip() {
        let value: UInt = 0xFFFF_FFFF
        let encoded = value._encodeStorablePlist()
        #expect(UInt._decodeStorablePlist(encoded) == value)
    }

    @Test func int64MaxRoundTrip() {
        let value: Int64 = .max
        let encoded = value._encodeStorablePlist()
        #expect(Int64._decodeStorablePlist(encoded) == value)
    }

    @Test func smallIntegerTypes() {
        #expect(Int8._decodeStorablePlist(Int8(-5)._encodeStorablePlist()) == -5)
        #expect(UInt8._decodeStorablePlist(UInt8(200)._encodeStorablePlist()) == 200)
        #expect(Int16._decodeStorablePlist(Int16(-1)._encodeStorablePlist()) == -1)
        #expect(UInt16._decodeStorablePlist(UInt16(0xABCD)._encodeStorablePlist()) == 0xABCD)
        #expect(Int32._decodeStorablePlist(Int32(0x0102_0304)._encodeStorablePlist()) == 0x0102_0304)
        #expect(UInt32._decodeStorablePlist(UInt32(0xDEAD_BEEF)._encodeStorablePlist()) == 0xDEAD_BEEF)
    }

    @Test func integerDecodeRejectsString() {
        #expect(Int._decodeStorablePlist("42") == nil)
        #expect(Int32._decodeStorablePlist(Date()) == nil)
    }

    // MARK: - Floats / Date / URL

    @Test func doubleRoundTrip() {
        let value = 3.14159265358979
        let encoded = value._encodeStorablePlist()
        #expect(Double._decodeStorablePlist(encoded) == value)
    }

    @Test func floatRoundTrip() {
        let value: Float = -1.5
        let encoded = value._encodeStorablePlist()
        #expect(Float._decodeStorablePlist(encoded) == value)
    }

    @Test func dateRoundTrip() {
        let value = Date(timeIntervalSinceReferenceDate: 1_234_567.89)
        let encoded = value._encodeStorablePlist()
        #expect(encoded as? Date == value)
        #expect(Date._decodeStorablePlist(encoded) == value)
    }

    @Test func urlRoundTripsThroughString() {
        let value = URL(string: "https://example.com/path?query=value")!
        let encoded = value._encodeStorablePlist()
        // The encoded form is the absolute string so plist editors stay
        // useful — readers via `UserDefaults.url(forKey:)` won't see it.
        #expect(encoded as? String == value.absoluteString)
        #expect(URL._decodeStorablePlist(encoded) == value)
    }

    @Test func urlDecodeRejectsNonString() {
        #expect(URL._decodeStorablePlist(Date()) == nil)
        #expect(URL._decodeStorablePlist(123) == nil)
    }

    // MARK: - Optional

    @Test func optionalWrappedRoundTrip() {
        let original: String? = "abc"
        let encoded = original._encodeStorablePlist()
        let decoded = String?._decodeStorablePlist(encoded)
        #expect(decoded == .some(.some("abc")))
    }

    @Test func optionalNilEncodesNSNull() {
        let original: String? = nil
        let encoded = original._encodeStorablePlist()
        #expect(encoded is NSNull)
    }

    // MARK: - Codable

    struct UserPreferences: PlistCodableStorable, Equatable {
        var theme: String
        var notificationsEnabled: Bool
    }

    @Test func codableRoundTrip() throws {
        let original = UserPreferences(theme: "dark", notificationsEnabled: true)
        let encoded = original._encodeStorablePlist()
        // The JSON-backed default impl stores Data.
        let data = try #require(encoded as? Data)
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("\"theme\":\"dark\""))
        #expect(text.contains("\"notificationsEnabled\":true"))
        #expect(UserPreferences._decodeStorablePlist(encoded) == original)
    }

    @Test func codableDecodeFailsOnGarbage() {
        let garbage = Data("not valid json".utf8)
        #expect(UserPreferences._decodeStorablePlist(garbage) == nil)
        #expect(UserPreferences._decodeStorablePlist("string-not-data") == nil)
    }
}
