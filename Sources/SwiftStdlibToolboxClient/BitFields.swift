// `@BitField` compiled for real, in the shapes the expansion tests can only show
// as text: a public flag word whose properties keep their documentation,
// availability and `@inlinable`; a field of each kind of type; and a member
// named after the helper the expansion calls, which the module-qualified call
// must not resolve to. Building this target must produce no warnings.
import SwiftStdlibToolbox

public enum CompressionMethod: UInt8, Sendable {
    case none = 0
    case deflate = 1
    case lzfse = 2
}

public struct ArchiveEntryFlags: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Whether the entry is a directory.
    @BitField(bits: 0)
    public var isDirectory: Bool

    /// How the entry is compressed, or `nil` for a method this reader does
    /// not know.
    @inlinable
    @BitField(bits: 1..<4)
    public var compressionMethod: CompressionMethod?

    @available(*, deprecated, message: "Encryption is recorded in the entry header")
    @BitField(bits: 4)
    public var isEncrypted: Bool

    @available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
    @BitField(bits: 8..<16)
    public var formatVersion: UInt8

    @BitField(bits: 16..<20, default: CompressionMethod.none)
    public var fallbackMethod: CompressionMethod

    /// Named after the helper the expansion calls; the call must not find it.
    enum _BitFieldAccess {}
}

func describeArchiveEntryFlags() -> String {
    let flags = ArchiveEntryFlags(rawValue: 0x0002_0103)
    var description = "\(flags.isDirectory) \(String(describing: flags.compressionMethod)) \(flags.fallbackMethod)"
    if #available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *) {
        description += " \(flags.formatVersion)"
    }
    return description
}
