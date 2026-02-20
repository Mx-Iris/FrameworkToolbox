import Testing
import Foundation
@testable import FoundationToolbox

@Suite("URL Box Extensions")
struct URLExtensionTests {

    // MARK: - Name

    @Test("name returns lastPathComponent")
    func name() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/file.txt")
        #expect(url.box.name == "file.txt")
    }

    @Test("nameExcludingExtension returns name without extension")
    func nameExcludingExtension() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/file.txt")
        #expect(url.box.nameExcludingExtension == "file")
    }

    @Test("nameExcludingExtension for file without extension")
    func nameExcludingExtensionNoExt() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/Makefile")
        #expect(url.box.nameExcludingExtension == "Makefile")
    }

    // MARK: - Parent

    @Test("parent returns parent directory")
    func parent() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/file.txt")
        #expect(url.box.parent?.path == "/Users/test/Documents")
    }

    @Test("parent of root returns nil")
    func parentRoot() {
        let url = URL(fileURLWithPath: "/")
        #expect(url.box.parent == nil)
    }

    // MARK: - Query Items

    @Test("queryItems returns items")
    func queryItems() {
        let url = URL(string: "https://example.com?key=value&foo=bar")!
        let items = url.box.queryItems
        #expect(items?.count == 2)
        #expect(items?.first?.name == "key")
        #expect(items?.first?.value == "value")
    }

    @Test("queryItems returns nil for URL without query")
    func queryItemsNone() {
        let url = URL(string: "https://example.com/path")!
        #expect(url.box.queryItems == nil)
    }

    // MARK: - Path Relationships

    @Test("isParent(of:) returns true for parent directory")
    func isParent() {
        let parent = URL(fileURLWithPath: "/Users/test")
        let child = URL(fileURLWithPath: "/Users/test/Documents/file.txt")
        #expect(parent.box.isParent(of: child))
    }

    @Test("isParent(of:) returns false for non-parent")
    func isParentFalse() {
        let notParent = URL(fileURLWithPath: "/Users/other")
        let child = URL(fileURLWithPath: "/Users/test/Documents/file.txt")
        #expect(!notParent.box.isParent(of: child))
    }

    @Test("isChild(of:) returns true for child path")
    func isChild() {
        let parent = URL(fileURLWithPath: "/Users/test")
        let child = URL(fileURLWithPath: "/Users/test/Documents/file.txt")
        #expect(child.box.isChild(of: parent))
    }

    @Test("isChild(of:) returns false for non-child")
    func isChildFalse() {
        let notParent = URL(fileURLWithPath: "/Users/other")
        let child = URL(fileURLWithPath: "/Users/test/Documents/file.txt")
        #expect(!child.box.isChild(of: notParent))
    }

    @Test("isParent(of:) is false for equal URLs")
    func isParentEqual() {
        let url = URL(fileURLWithPath: "/Users/test")
        #expect(!url.box.isParent(of: url))
    }

    // MARK: - File System Checks

    @Test("exists returns true for existing path")
    func existsTrue() {
        let url = URL(fileURLWithPath: "/")
        #expect(url.box.exists)
    }

    @Test("exists returns false for non-existing path")
    func existsFalse() {
        let url = URL(fileURLWithPath: "/this/path/does/not/exist_\(UUID().uuidString)")
        #expect(!url.box.exists)
    }

    @Test("isDirectory returns true for directory")
    func isDirectoryTrue() {
        let url = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        #expect(url.box.isDirectory)
    }

    @Test("isFile returns false for directory")
    func isFileFalseForDir() {
        let url = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        #expect(!url.box.isFile)
    }
}
