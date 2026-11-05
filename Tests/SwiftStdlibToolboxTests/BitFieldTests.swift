import SwiftStdlibToolbox
import Testing

/// Three of the eight values three bits can spell.
enum BitFieldShape: UInt8 {
    case circle = 0
    case square = 1
    case triangle = 2
}

enum BitFieldKind: UInt8 {
    case unknown = 0
    case first = 1
    case second = 2
}

struct BitFieldDirections: OptionSet {
    let rawValue: UInt8

    static let north = Self(rawValue: 1 << 0)
    static let east = Self(rawValue: 1 << 1)
    static let south = Self(rawValue: 1 << 2)
    static let west = Self(rawValue: 1 << 3)
}

/// A flag word holding every kind of field the macro reads. `wideShape`
/// overlaps `kind` on purpose: it is the field too wide for its raw value.
struct PackedWord: RawRepresentable, Hashable {
    typealias Count = UInt16

    let rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0)
    var isEnabled: Bool

    @BitField(bits: 1..<4)
    var shape: BitFieldShape?

    @BitField(bits: 4..<12)
    var count: Count

    @BitField(bits: 12..<16)
    var directions: BitFieldDirections

    @BitField(bits: 16..<19, default: BitFieldKind.unknown)
    var kind: BitFieldKind

    @BitField(bits: 16..<32)
    var wideShape: BitFieldShape?
}

/// Storage given as a generic parameter, read back as that same parameter.
struct GenericWord<Storage: FixedWidthInteger>: RawRepresentable {
    let rawValue: Storage

    init(rawValue: Storage) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0..<4)
    var lowNibble: Storage

    @BitField(bits: 4..<8)
    var highNibble: Storage
}

/// A signed word, whose right shift drags the sign bit along.
struct SignedWord: RawRepresentable {
    let rawValue: Int16

    init(rawValue: Int16) {
        self.rawValue = rawValue
    }

    @BitField(bits: 12..<16)
    var topNibble: UInt8

    @BitField(bits: 15)
    var isNegative: Bool

    @BitField(bits: 0..<16)
    var whole: Int16
}

/// A field that does not fit in its storage — a mistake the macro cannot see,
/// because it cannot see the type of `rawValue`.
struct OverflowingWord: RawRepresentable {
    let rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    @BitField(bits: 4..<12)
    var beyondTheStorage: UInt16
}

/// Behaviour of `@BitField` under the real compiler.
///
/// Every fixture above has to compile before an assertion runs, which is what
/// the expansion snapshots in `Tests/SwiftStdlibToolboxMacroTests/` cannot
/// show: that overload resolution picks the conversion each property's type
/// calls for, a typealias and a generic parameter included.
@Suite("@BitField")
struct BitFieldTests {

    @Test("a Bool reads its bit")
    func boolReadsItsBit() {
        #expect(PackedWord(rawValue: 0b1).isEnabled)
        #expect(!PackedWord(rawValue: 0b10).isEnabled)
    }

    @Test("an optional RawRepresentable reads the value the bits spell")
    func optionalRawRepresentableReadsTheValueTheBitsSpell() {
        #expect(PackedWord(rawValue: 0b0000).shape == .circle)
        #expect(PackedWord(rawValue: 0b0100).shape == .triangle)
    }

    @Test("an optional RawRepresentable reads bits it does not know as nil")
    func optionalRawRepresentableReadsUnknownBitsAsNil() {
        #expect(PackedWord(rawValue: 0b1010).shape == nil)
    }

    @Test("an integer reads its bits moved down to bit 0, through a typealias")
    func integerReadsItsBitsThroughATypealias() {
        let word = PackedWord(rawValue: 0xAB0)
        #expect(word.count == 0xAB)
        #expect(type(of: word.count) == UInt16.self)
    }

    @Test("an OptionSet reads the set its bits make up")
    func optionSetReadsTheSetItsBitsMakeUp() {
        #expect(PackedWord(rawValue: 0x5000).directions == [.north, .south])
        #expect(PackedWord(rawValue: 0).directions.isEmpty)
    }

    @Test("a default stands in for bits the type does not know")
    func defaultStandsInForUnknownBits() {
        #expect(PackedWord(rawValue: 0x2_0000).kind == .second)
        #expect(PackedWord(rawValue: 0x7_0000).kind == .unknown)
    }

    @Test("bits too wide for the raw value read as nil, not as a truncated case")
    func bitsTooWideForTheRawValueReadAsNil() {
        #expect(PackedWord(rawValue: 0x0001_0000).wideShape == .square)
        // Truncated to 8 bits, 0x0101 would be 0x01 — `.square`.
        #expect(PackedWord(rawValue: 0x0101_0000).wideShape == nil)
    }

    @Test("a generic storage reads back as itself")
    func genericStorageReadsBackAsItself() {
        let narrow = GenericWord<UInt8>(rawValue: 0xC5)
        #expect(narrow.lowNibble == 0x5)
        #expect(narrow.highNibble == 0xC)

        let wide = GenericWord<Int64>(rawValue: -1)
        #expect(wide.lowNibble == 0xF)
        #expect(wide.highNibble == 0xF)
    }

    @Test("a signed storage keeps its sign out of the field")
    func signedStorageKeepsItsSignOutOfTheField() {
        let word = SignedWord(rawValue: -0x1000)
        #expect(word.topNibble == 0xF)
        #expect(word.isNegative)
        #expect(word.whole == -0x1000)
        #expect(!SignedWord(rawValue: 0x7000).isNegative)
    }

    @Test("bits beyond the storage stop the program at the first read")
    func bitsBeyondTheStorageStopTheProgram() async {
        await #expect(processExitsWith: .failure) {
            _ = OverflowingWord(rawValue: 0xFF).beyondTheStorage
        }
    }
}
