#if canImport(Darwin)

import CoreFoundation
import FrameworkToolbox

extension CFStringTokenizer {

    public enum Attribute: CFOptionFlags {

        /// `kCFStringTokenizerAttributeLatinTranscription`
        case latinTranscription = 0b1_0000_0000_0000_0000

        /// `kCFStringTokenizerAttributeLanguage`
        case language = 0b10_0000_0000_0000_0000
    }

    public enum Unit: CFOptionFlags {

        /// `kCFStringTokenizerUnitWord`
        case word = 0

        /// `kCFStringTokenizerUnitSentence`
        case sentence = 1

        /// `kCFStringTokenizerUnitParagraph`
        case paragraph = 2

        /// `kCFStringTokenizerUnitLineBreak`
        case lineBreak = 3

        /// `kCFStringTokenizerUnitWordBoundary`
        case wordBoundary = 4
    }
}

extension FrameworkToolbox<CFStringTokenizer> {

    @inlinable
    public static func create(
        allocator: CFAllocator = FrameworkToolbox<CFAllocator>.default,
        string: CFString,
        range: CFRange? = nil,
        unit: CFStringTokenizer.Unit = .wordBoundary,
        locale: CFLocale? = nil
    ) -> CFStringTokenizer {
        CFStringTokenizerCreate(allocator, string, range ?? string.box.fullRange, unit.rawValue, locale)
    }

    @inlinable
    public func setString(_ string: CFString, range: CFRange? = nil) {
        CFStringTokenizerSetString(base, string, range ?? string.box.fullRange)
    }

    @inlinable
    public func goToToken(at index: CFIndex) -> CFStringTokenizerTokenType? {
        let token = CFStringTokenizerGoToTokenAtIndex(base, index)
        if token.isEmpty { return nil }
        return token
    }

    @inlinable
    public func advanceToNextToken() -> CFStringTokenizerTokenType? {
        let token = CFStringTokenizerAdvanceToNextToken(base)
        if token.isEmpty { return nil }
        return token
    }

    @inlinable
    public func currentTokenRange() -> CFRange {
        CFStringTokenizerGetCurrentTokenRange(base)
    }

    @inlinable
    public func currentTokenAttribute(_ attribute: CFStringTokenizer.Attribute) -> CFString? {
        CFStringTokenizerCopyCurrentTokenAttribute(base, attribute.rawValue).map {
            cfCast($0, to: CFString.self)!
        }
    }

    @inlinable
    public func currentSubTokens(maxRangeLength: CFIndex = 0) -> [CFStringTokenizerTokenType] {
        let array = FrameworkToolbox<CFMutableArray>.create()
        CFStringTokenizerGetCurrentSubTokens(base, nil, maxRangeLength, array)
        return array as! [CFStringTokenizerTokenType]
    }

    @inlinable
    public static func bestLanguage(for string: CFString, range: CFRange? = nil) -> CFString? {
        CFStringTokenizerCopyBestStringLanguage(string, range ?? string.box.fullRange)
    }
}

extension CFStringTokenizer: @retroactive IteratorProtocol {

    @inlinable
    public func next() -> CFStringTokenizerTokenType? {
        box.advanceToNextToken()
    }
}

#endif
