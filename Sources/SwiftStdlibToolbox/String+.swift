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
        if #available(macOS 13.0, *) {
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
}

extension FrameworkToolbox where Base == Substring {
    @inlinable
    public var string: String {
        .init(base)
    }
}
