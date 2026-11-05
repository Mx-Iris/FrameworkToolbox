/// The conversions `@BitField` expands to. Not meant to be called directly.
///
/// A macro sees spelling, not types: `typealias RawValue = UInt32`, a generic
/// parameter and an enumeration look alike to it. So the getter it generates
/// does not decide how to read the bits. It passes the property's type to
/// `value(of:bits:as:)`, and overload resolution picks the conversion. The
/// unavailable overloads exist only to turn a type no conversion fits into an
/// error that says what to write instead.
@_documentation(visibility: private)
public enum _BitFieldAccess {
    /// The bits of `storage` in `range`, moved down so that the first of them
    /// is bit 0.
    ///
    /// A range that does not fit in `Storage` is a mistake in the declaration,
    /// not in the data: the macro cannot see the type of `rawValue`, so this
    /// is where it is caught.
    @inlinable
    public static func bits<Storage: FixedWidthInteger>(
        of storage: Storage,
        in range: Range<Int>
    ) -> Storage {
        precondition(
            range.lowerBound >= 0 && range.upperBound <= Storage.bitWidth,
            "bits \(range.lowerBound)..<\(range.upperBound) do not fit in a \(Storage.bitWidth)-bit 'rawValue'"
        )
        let shiftedStorage = storage >> range.lowerBound
        guard range.count < Storage.bitWidth else {
            return shiftedStorage
        }
        return shiftedStorage & ((1 << range.count) &- 1)
    }

    // MARK: - Conversions

    /// Whether any of the bits is set.
    @inlinable
    public static func value<Storage: FixedWidthInteger>(
        of storage: Storage,
        bits range: Range<Int>,
        as _: Bool.Type
    ) -> Bool {
        bits(of: storage, in: range) != 0
    }

    /// The bits as an integer.
    @inlinable
    public static func value<Storage: FixedWidthInteger, Value: FixedWidthInteger>(
        of storage: Storage,
        bits range: Range<Int>,
        as _: Value.Type
    ) -> Value {
        precondition(
            range.count <= Value.bitWidth,
            "bits \(range.lowerBound)..<\(range.upperBound) are \(range.count) bits wide, more than '\(Value.self)' holds"
        )
        return Value(truncatingIfNeeded: bits(of: storage, in: range))
    }

    /// The set the bits make up.
    @inlinable
    public static func value<Storage: FixedWidthInteger, Value: OptionSet>(
        of storage: Storage,
        bits range: Range<Int>,
        as _: Value.Type
    ) -> Value where Value.RawValue: FixedWidthInteger {
        precondition(
            range.count <= Value.RawValue.bitWidth,
            "bits \(range.lowerBound)..<\(range.upperBound) are \(range.count) bits wide, more than the raw value of '\(Value.self)' holds"
        )
        return Value(rawValue: Value.RawValue(truncatingIfNeeded: bits(of: storage, in: range)))
    }

    /// The value the bits spell, or `nil` for bits `Value` does not know.
    ///
    /// The bits are converted to the raw value exactly: truncating them would
    /// let a wide field holding `0x0101` read as the case whose raw value is
    /// `0x01`.
    @inlinable
    public static func value<Storage: FixedWidthInteger, Value: RawRepresentable>(
        of storage: Storage,
        bits range: Range<Int>,
        as _: Value?.Type
    ) -> Value? where Value.RawValue: FixedWidthInteger {
        guard let rawValue = Value.RawValue(exactly: bits(of: storage, in: range)) else {
            return nil
        }
        return Value(rawValue: rawValue)
    }

    /// The value the bits spell, or `defaultValue` for bits `Value` does not
    /// know.
    @inlinable
    public static func value<Storage: FixedWidthInteger, Value: RawRepresentable>(
        of storage: Storage,
        bits range: Range<Int>,
        as _: Value.Type,
        default defaultValue: Value
    ) -> Value where Value.RawValue: FixedWidthInteger {
        value(of: storage, bits: range, as: Value?.self) ?? defaultValue
    }

    // MARK: - Types no conversion fits

    @available(
        *,
        unavailable,
        message: "a bit field of a RawRepresentable type needs a way to read bits the type does not know: declare the property optional, or pass 'default:'"
    )
    public static func value<Storage: FixedWidthInteger, Value: RawRepresentable>(
        of storage: Storage,
        bits range: Range<Int>,
        as _: Value.Type
    ) -> Value where Value.RawValue: FixedWidthInteger {
        fatalError("unavailable")
    }

    @available(
        *,
        unavailable,
        message: "a bit field reads a Bool, an integer, an OptionSet, or a RawRepresentable type whose raw value is an integer"
    )
    public static func value<Storage: FixedWidthInteger, Value>(
        of storage: Storage,
        bits range: Range<Int>,
        as _: Value.Type
    ) -> Value {
        fatalError("unavailable")
    }

    @available(
        *,
        unavailable,
        message: "'default:' is what a non-optional RawRepresentable property reads for bits its type does not know; this property's type is not one"
    )
    public static func value<Storage: FixedWidthInteger, Value>(
        of storage: Storage,
        bits range: Range<Int>,
        as _: Value.Type,
        default defaultValue: Value
    ) -> Value {
        fatalError("unavailable")
    }
}
