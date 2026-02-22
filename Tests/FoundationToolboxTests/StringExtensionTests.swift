import Testing
@testable import FoundationToolbox

@Suite("String Box Extensions")
struct StringExtensionTests {

    // MARK: - Case Transformation

    @Test("lowercasedFirst()")
    func lowercasedFirst() {
        #expect("Hello".box.lowercasedFirst() == "hello")
    }

    @Test("lowercasedFirst() with single character")
    func lowercasedFirstSingle() {
        #expect("A".box.lowercasedFirst() == "a")
    }

    @Test("lowercasedFirst() with empty string")
    func lowercasedFirstEmpty() {
        #expect("".box.lowercasedFirst() == "")
    }

    @Test("lowercasedFirst() already lowercase")
    func lowercasedFirstAlready() {
        #expect("hello".box.lowercasedFirst() == "hello")
    }

    @Test("uppercasedFirst()")
    func uppercasedFirst() {
        #expect("hello".box.uppercasedFirst() == "Hello")
    }

    @Test("uppercasedFirst() with single character")
    func uppercasedFirstSingle() {
        #expect("a".box.uppercasedFirst() == "A")
    }

    @Test("uppercasedFirst() with empty string")
    func uppercasedFirstEmpty() {
        #expect("".box.uppercasedFirst() == "")
    }

    // MARK: - Prefix / Suffix

    @Test("removingPrefix() removes matching prefix")
    func removingPrefix() {
        #expect("prefix_name".box.removingPrefix("prefix_") == "name")
    }

    @Test("removingPrefix() returns same string when no match")
    func removingPrefixNoMatch() {
        #expect("hello".box.removingPrefix("xyz") == "hello")
    }

    @Test("removingPrefix() with empty prefix")
    func removingPrefixEmpty() {
        #expect("hello".box.removingPrefix("") == "hello")
    }

    @Test("removingSuffix() removes matching suffix")
    func removingSuffix() {
        #expect("file.txt".box.removingSuffix(".txt") == "file")
    }

    @Test("removingSuffix() returns same string when no match")
    func removingSuffixNoMatch() {
        #expect("file.txt".box.removingSuffix(".md") == "file.txt")
    }

    @Test("removingSuffix() with empty suffix")
    func removingSuffixEmpty() {
        #expect("hello".box.removingSuffix("") == "hello")
    }

    // MARK: - Words

    @Test("words splits by whitespace")
    func words() {
        #expect("Hello World".box.words == ["Hello", "World"])
    }

    @Test("words handles multiple spaces")
    func wordsMultipleSpaces() {
        #expect("Hello   World".box.words == ["Hello", "World"])
    }

    @Test("words handles tabs and newlines")
    func wordsTabsNewlines() {
        #expect("Hello\tWorld\nFoo".box.words == ["Hello", "World", "Foo"])
    }

    @Test("words on empty string")
    func wordsEmpty() {
        #expect("".box.words.isEmpty)
    }

    // MARK: - Lines

    @Test("lines splits by newline")
    func lines() {
        #expect("line1\nline2\nline3".box.lines == ["line1", "line2", "line3"])
    }

    @Test("lines single line")
    func linesSingle() {
        #expect("hello".box.lines == ["hello"])
    }
}
