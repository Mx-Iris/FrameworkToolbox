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

    // MARK: - File System Checks

    /// A Boolean value indicating whether the resource is a directory.
    public var isDirectory: Bool {
        (try? base.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// A Boolean value indicating whether the resource is a regular file.
    public var isFile: Bool {
        (try? base.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    /// A Boolean value indicating whether the file exists at this URL.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: base.path)
    }

    // MARK: - Path Convenience

    /// The name of the URL (`lastPathComponent`).
    @inlinable
    public var name: String {
        base.lastPathComponent
    }

    /// The name excluding the path extension.
    @inlinable
    public var nameExcludingExtension: String {
        base.deletingPathExtension().lastPathComponent
    }

    /// The parent directory URL, or `nil` if there is no parent.
    @inlinable
    public var parent: URL? {
        let parent = base.deletingLastPathComponent()
        guard parent.path != base.path else { return nil }
        return parent
    }

    /// The query items of the URL.
    @inlinable
    public var queryItems: [URLQueryItem]? {
        URLComponents(url: base, resolvingAgainstBaseURL: false)?.queryItems
    }

    // MARK: - Path Relationships

    /// Returns `true` if this file URL is a parent of the given URL.
    ///
    /// - Parameter url: The URL to check.
    public func isParent(of url: URL) -> Bool {
        guard base.isFileURL, url.isFileURL else { return false }
        let selfPath = base.standardizedFileURL.path
        let otherPath = url.standardizedFileURL.path
        let normalizedSelfPath = selfPath.hasSuffix("/") ? selfPath : selfPath + "/"
        return otherPath.hasPrefix(normalizedSelfPath)
    }

    /// Returns `true` if this file URL is a child of the given URL.
    ///
    /// - Parameter url: The URL to check.
    public func isChild(of url: URL) -> Bool {
        FrameworkToolbox<URL>(url).isParent(of: base)
    }
}
