import Foundation
import FrameworkToolbox

extension FrameworkToolbox<String> {
    @inlinable
    public var url: URL? {
        .init(string: base)
    }

    public var decodeByBase64: String? {
        guard let data = Data(base64Encoded: base) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @inlinable
    public var filePathURL: URL {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            return .init(filePath: base)
        } else {
            return .init(fileURLWithPath: base)
        }
    }

    public func firstLines(_ n: Int) -> String {
        let lines = base.components(separatedBy: "\n")
        let firstNLines = lines.prefix(n)
        return firstNLines.joined(separator: "\n")
    }

    public var nsString: NSString { base as NSString }

    public var pathComponents: [String] { nsString.pathComponents }

    public var isAbsolutePath: Bool { nsString.isAbsolutePath }

    public var lastPathComponent: String { nsString.lastPathComponent }

    public var deletingLastPathComponent: String { nsString.deletingLastPathComponent }

    public var pathExtension: String { nsString.pathExtension }

    public var deletingPathExtension: String { nsString.deletingPathExtension }

    public var abbreviatingWithTildeInPath: String { nsString.abbreviatingWithTildeInPath }

    public var expandingTildeInPath: String { nsString.expandingTildeInPath }

    public var standardizingPath: String { nsString.standardizingPath }

    public var resolvingSymlinksInPath: String { nsString.resolvingSymlinksInPath }

    public func appendingPathComponent(_ str: String) -> String { nsString.appendingPathComponent(str) }

    public func appendingPathExtension(_ str: String) -> String? { nsString.appendingPathExtension(str) }

    public func strings(byAppendingPaths paths: [String]) -> [String] { nsString.strings(byAppendingPaths: paths) }

    public static func path(withComponents components: [String]) -> String { NSString.path(withComponents: components) }
}

extension FrameworkToolbox where Base: StringProtocol {
    @inlinable
    public var string: String {
        .init(base)
    }
}

extension FrameworkToolbox where Base: NSString {
    @inlinable
    public var string: String {
        .init(base)
    }
}
