import Foundation
import FrameworkToolbox

extension FrameworkToolbox<String> {
    @inlinable
    public var url: URL? { .init(string: base) }

    @inlinable
    public var decodeByBase64: String? { Data(base64Encoded: base).flatMap { String(data: $0, encoding: .utf8) } }

    @inlinable
    public var filePathURL: URL {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            return .init(filePath: base)
        } else {
            return .init(fileURLWithPath: base)
        }
    }

    @inlinable
    public func firstLines(_ n: Int) -> String { base.components(separatedBy: "\n").prefix(n).joined(separator: "\n") }

    @inlinable
    public var nsString: NSString { base as NSString }

    @inlinable
    public var pathComponents: [String] { nsString.pathComponents }

    @inlinable
    public var isAbsolutePath: Bool { nsString.isAbsolutePath }

    @inlinable
    public var lastPathComponent: String { nsString.lastPathComponent }

    @inlinable
    public var deletingLastPathComponent: String { nsString.deletingLastPathComponent }

    @inlinable
    public var pathExtension: String { nsString.pathExtension }

    @inlinable
    public var deletingPathExtension: String { nsString.deletingPathExtension }

    @inlinable
    public var abbreviatingWithTildeInPath: String { nsString.abbreviatingWithTildeInPath }

    @inlinable
    public var expandingTildeInPath: String { nsString.expandingTildeInPath }

    @inlinable
    public var standardizingPath: String { nsString.standardizingPath }

    @inlinable
    public var resolvingSymlinksInPath: String { nsString.resolvingSymlinksInPath }

    @inlinable
    public func appendingPathComponent(_ str: String) -> String { nsString.appendingPathComponent(str) }

    @inlinable
    public func appendingPathExtension(_ str: String) -> String? { nsString.appendingPathExtension(str) }

    @inlinable
    public func strings(byAppendingPaths paths: [String]) -> [String] { nsString.strings(byAppendingPaths: paths) }

    @inlinable
    public static func path(withComponents components: [String]) -> String { NSString.path(withComponents: components) }
}

// MARK: - Case Transformation

extension FrameworkToolbox where Base: StringProtocol {
    @inlinable
    public var string: String { .init(base) }

    /// Returns a string with the first character lowercased.
    @inlinable
    public func lowercasedFirst() -> String {
        guard !base.isEmpty else { return String(base) }
        return base.prefix(1).lowercased() + base.dropFirst()
    }

    /// Returns a string with the first character uppercased.
    @inlinable
    public func uppercasedFirst() -> String {
        guard !base.isEmpty else { return String(base) }
        return base.prefix(1).uppercased() + base.dropFirst()
    }
}

// MARK: - Prefix / Suffix

extension FrameworkToolbox<String> {
    /// Returns the string with the specified prefix removed, if present.
    ///
    /// - Parameter prefix: The prefix to remove.
    @inlinable
    public func removingPrefix(_ prefix: String) -> String {
        guard base.hasPrefix(prefix) else { return base }
        return String(base.dropFirst(prefix.count))
    }

    /// Returns the string with the specified suffix removed, if present.
    ///
    /// - Parameter suffix: The suffix to remove.
    @inlinable
    public func removingSuffix(_ suffix: String) -> String {
        guard base.hasSuffix(suffix) else { return base }
        return String(base.dropLast(suffix.count))
    }

    /// Returns the individual words in the string.
    @inlinable
    public var words: [String] {
        base.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }

    /// Returns the lines of the string.
    @inlinable
    public var lines: [String] {
        base.components(separatedBy: .newlines)
    }
}

extension FrameworkToolbox where Base: NSString {
    @inlinable
    public var string: String { .init(base) }
}
