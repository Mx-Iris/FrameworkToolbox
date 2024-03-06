import Foundation
import FrameworkToolbox

extension FrameworkToolbox where Base == String {
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
        if #available(macOS 13.0, iOS 16.0, *) {
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
    
    var nsString: NSString { base as NSString }

    var pathComponents: [String] { nsString.pathComponents }

    var isAbsolutePath: Bool { nsString.isAbsolutePath }

    var lastPathComponent: String { nsString.lastPathComponent }

    var deletingLastPathComponent: String { nsString.deletingLastPathComponent }

    var pathExtension: String { nsString.pathExtension }

    var deletingPathExtension: String { nsString.deletingPathExtension }

    var abbreviatingWithTildeInPath: String { nsString.abbreviatingWithTildeInPath }

    var expandingTildeInPath: String { nsString.expandingTildeInPath }

    var standardizingPath: String { nsString.standardizingPath }

    var resolvingSymlinksInPath: String { nsString.resolvingSymlinksInPath }

    func appendingPathComponent(_ str: String) -> String { nsString.appendingPathComponent(str) }

    func appendingPathExtension(_ str: String) -> String? { nsString.appendingPathExtension(str) }

    func strings(byAppendingPaths paths: [String]) -> [String] { nsString.strings(byAppendingPaths: paths) }

    static func path(withComponents components: [String]) -> String { NSString.path(withComponents: components) }
}

extension FrameworkToolbox where Base == Substring {
    @inlinable
    public var string: String {
        .init(base)
    }
}
