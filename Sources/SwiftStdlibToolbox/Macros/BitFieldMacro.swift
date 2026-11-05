/// Makes a property read its value out of some bits of the enclosing type's
/// `rawValue`.
///
/// A flag word often packs single-bit flags and multi-bit fields — a kind, a
/// count, a version — into one integer. Reading a field means shifting,
/// masking and converting, and a hand-written accessor that skips a step
/// still compiles. With the macro, an accessor states only the bits it
/// occupies; bit 0 is the least significant:
///
/// ```swift
/// public struct ProtocolContextDescriptorFlags: RawRepresentable, Hashable, Sendable {
///     public let rawValue: UInt16
///
///     public init(rawValue: UInt16) {
///         self.rawValue = rawValue
///     }
///
///     @BitField(bits: 1)
///     public var isResilient: Bool
///
///     /// The special protocol this descriptor stands for, or `nil` for a
///     /// value this reader does not know.
///     @BitField(bits: 2..<8)
///     public var specialProtocolKind: SpecialProtocolKind?
/// }
/// ```
///
/// The macro generates a getter and nothing else. The property's
/// documentation, attributes and access level stay where they are written.
/// Its type decides what the getter reads:
///
/// - `Bool`: whether the bit is set.
/// - An integer type — a typealias of one or a generic parameter too: the
///   bits, moved down to bit 0.
/// - An `OptionSet` whose raw value is an integer: the set the bits make up.
/// - `T?`, where `T` is `RawRepresentable` with an integer raw value: the
///   value the bits spell, or `nil` for bits `T` does not know.
/// - `T` with `default:`: the same, with the default in place of `nil`.
///
/// A non-optional `RawRepresentable` property without `default:` does not
/// compile: bits the type does not know would have nowhere to go but a crash,
/// and a flag word usually comes from outside the program — a file, another
/// process, a newer compiler. Write the default in full, as in
/// `default: ContextDescriptorKind.unknown`: the argument is type-checked
/// before the macro runs, against a declaration that does not know the
/// property's type, so `.unknown` alone does not compile.
///
/// The enclosing type needs a stored `rawValue` of a `FixedWidthInteger` type.
/// The macro cannot see it, so bits beyond its width stop the program at the
/// first read rather than failing to compile.
///
/// - Parameter position: The bit the property reads.
@attached(accessor)
public macro BitField(bits position: Int) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "BitFieldMacro"
)

/// Makes a property read its value out of some bits of the enclosing type's
/// `rawValue`.
///
/// What the property's type decides is described on the overload that
/// takes a single position.
///
/// - Parameter range: The bits the property reads, as a half-open range of
///   positions; bit 0 is the least significant.
@attached(accessor)
public macro BitField(bits range: Range<Int>) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "BitFieldMacro"
)

/// Makes a property read its value out of some bits of the enclosing type's
/// `rawValue`, falling back to `defaultValue` for bits the property's type
/// does not know.
///
/// What the property's type decides is described on the overload that
/// takes a single position.
///
/// - Parameters:
///   - position: The bit the property reads.
///   - defaultValue: What the property reads when its `RawRepresentable` type
///     has no value for the bit. Written in full — `Kind.unknown`, not
///     `.unknown`.
@attached(accessor)
public macro BitField<Value>(bits position: Int, default defaultValue: Value) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "BitFieldMacro"
)

/// Makes a property read its value out of some bits of the enclosing type's
/// `rawValue`, falling back to `defaultValue` for bits the property's type
/// does not know.
///
/// What the property's type decides is described on the overload that
/// takes a single position.
///
/// - Parameters:
///   - range: The bits the property reads, as a half-open range of
///     positions; bit 0 is the least significant.
///   - defaultValue: What the property reads when its `RawRepresentable` type
///     has no value for the bits. Written in full — `Kind.unknown`, not
///     `.unknown`.
@attached(accessor)
public macro BitField<Value>(bits range: Range<Int>, default defaultValue: Value) = #externalMacro(
    module: "SwiftStdlibToolboxMacros",
    type: "BitFieldMacro"
)
