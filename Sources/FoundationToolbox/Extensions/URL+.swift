import Foundation
import FrameworkToolbox

extension FrameworkToolbox<URL> {
    private struct DirectorySequence: Sequence {
        let enumerator: FileManager.DirectoryEnumerator?

        init(url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions = []) {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: mask)
            self.enumerator = enumerator
        }

        func makeIterator() -> AnyIterator<URL> {
            .init {
                enumerator?.nextObject() as? URL
            }
        }
    }

    public func enumerator(includingPropertiesForKeys keys: [URLResourceKey]? = nil, options mask: FileManager.DirectoryEnumerationOptions = []) -> some Sequence<URL> {
        return DirectorySequence(url: base, includingPropertiesForKeys: keys, options: mask)
    }
}
