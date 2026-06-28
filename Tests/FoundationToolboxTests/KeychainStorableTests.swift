import Foundation
import Testing

@testable import FoundationToolbox

@Suite
struct KeychainStorableTests {

    // MARK: - String / Data / Bool

    @Test func stringRoundTrip() {
        let original = "hello, world 🌍"
        let data = original._encodeStorableData()
        #expect(data == Data(original.utf8))
        #expect(String._decodeStorableData(from: data) == original)
    }

    @Test func emptyStringRoundTrip() {
        let original = ""
        let data = original._encodeStorableData()
        #expect(data.isEmpty)
        #expect(String._decodeStorableData(from: data) == original)
    }

    @Test func dataRoundTrip() {
        let original = Data([0x00, 0xFF, 0x42, 0x13])
        let data = original._encodeStorableData()
        #expect(data == original)
        #expect(Data._decodeStorableData(from: data) == original)
    }

    @Test func boolRoundTrip() {
        #expect(true._encodeStorableData() == Data([0x01]))
        #expect(false._encodeStorableData() == Data([0x00]))
        #expect(Bool._decodeStorableData(from: Data([0x01])) == true)
        #expect(Bool._decodeStorableData(from: Data([0x00])) == false)
        #expect(Bool._decodeStorableData(from: Data([0xFF])) == true)
        #expect(Bool._decodeStorableData(from: Data()) == nil)
    }

    // MARK: - Integers

    @Test func int64LittleEndianEncoding() {
        let value: Int64 = 0x0102030405060708
        let data = value._encodeStorableData()
        // Little-endian: least significant byte first
        #expect(Array(data) == [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
        #expect(Int64._decodeStorableData(from: data) == value)
    }

    @Test func int32LittleEndianEncoding() {
        let value: Int32 = 0x01020304
        let data = value._encodeStorableData()
        #expect(Array(data) == [0x04, 0x03, 0x02, 0x01])
        #expect(Int32._decodeStorableData(from: data) == value)
    }

    @Test func intIsEncodedAsInt64() {
        // Int's encoded form must be 8 bytes regardless of host word size,
        // so values written on one device are readable on another via
        // iCloud Keychain sync.
        let data = Int(42)._encodeStorableData()
        #expect(data.count == 8)
        #expect(Int._decodeStorableData(from: data) == 42)
    }

    @Test func negativeIntRoundTrip() {
        let value: Int = -123_456_789
        let data = value._encodeStorableData()
        #expect(Int._decodeStorableData(from: data) == value)
    }

    @Test func intDecodeRejectsWrongSize() {
        #expect(Int._decodeStorableData(from: Data([0x01, 0x02])) == nil)
        #expect(Int32._decodeStorableData(from: Data([0x01])) == nil)
        #expect(Int64._decodeStorableData(from: Data()) == nil)
    }

    @Test func unsignedIntRoundTrip() {
        let value: UInt64 = .max
        let data = value._encodeStorableData()
        #expect(Array(data) == [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        #expect(UInt64._decodeStorableData(from: data) == value)
    }

    @Test func smallIntegerTypes() {
        #expect(Int16._decodeStorableData(from: Int16(-1)._encodeStorableData()) == -1)
        #expect(UInt16._decodeStorableData(from: UInt16(0xABCD)._encodeStorableData()) == 0xABCD)
        #expect(Int8._decodeStorableData(from: Int8(-5)._encodeStorableData()) == -5)
        #expect(UInt8._decodeStorableData(from: UInt8(200)._encodeStorableData()) == 200)
    }

    // MARK: - Floats / Date / URL

    @Test func doubleRoundTrip() {
        let value = 3.14159265358979
        let data = value._encodeStorableData()
        #expect(data.count == 8)
        #expect(Double._decodeStorableData(from: data) == value)
    }

    @Test func doubleNaNAndInfinity() {
        let nanData = Double.nan._encodeStorableData()
        #expect(Double._decodeStorableData(from: nanData)?.isNaN == true)
        let infData = Double.infinity._encodeStorableData()
        #expect(Double._decodeStorableData(from: infData) == .infinity)
    }

    @Test func floatRoundTrip() {
        let value: Float = -1.5
        let data = value._encodeStorableData()
        #expect(data.count == 4)
        #expect(Float._decodeStorableData(from: data) == value)
    }

    @Test func dateRoundTrip() {
        let value = Date(timeIntervalSinceReferenceDate: 1_234_567.89)
        let data = value._encodeStorableData()
        #expect(Date._decodeStorableData(from: data) == value)
    }

    @Test func urlRoundTrip() {
        let value = URL(string: "https://example.com/path?query=value")!
        let data = value._encodeStorableData()
        #expect(URL._decodeStorableData(from: data) == value)
    }

    @Test func urlDecodeRejectsEmptyData() {
        // Empty data decodes to "" which is not a valid URL.
        #expect(URL._decodeStorableData(from: Data()) == nil)
    }

    // MARK: - Optional

    @Test func optionalWrappedRoundTrip() {
        let original: String? = "abc"
        let data = original._encodeStorableData()
        #expect(data == Data("abc".utf8))
        let decoded = String?._decodeStorableData(from: data)
        // Outer is "did decoding succeed", inner is the value.
        #expect(decoded == .some(.some("abc")))
    }

    @Test func optionalNilEncodesEmpty() {
        // The encode path for `.none` returns empty Data; KeychainStorage
        // short-circuits before reaching it, but the encoding must still be
        // well-defined.
        let original: String? = nil
        let data = original._encodeStorableData()
        #expect(data.isEmpty)
    }

    // MARK: - Codable

    struct UserPreferences: KeychainCodableStorable, Equatable {
        var theme: String
        var notificationsEnabled: Bool
    }

    @Test func codableRoundTrip() {
        let original = UserPreferences(theme: "dark", notificationsEnabled: true)
        let data = original._encodeStorableData()
        // Encoded form is JSON, so we should be able to find the keys.
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("\"theme\":\"dark\""))
        #expect(text.contains("\"notificationsEnabled\":true"))
        #expect(UserPreferences._decodeStorableData(from: data) == original)
    }

    @Test func codableDecodeFailsOnGarbage() {
        let garbage = Data("not valid json".utf8)
        #expect(UserPreferences._decodeStorableData(from: garbage) == nil)
    }
}
