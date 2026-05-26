import CoreFoundation

extension CFString {

    public struct Transform: CFStringKey {

        public let rawValue: CFString

        public init(_ key: CFString) {
            rawValue = key
        }
    }
}

extension CFString.Transform {

    public static func icuTransform(id: CFString) -> CFString.Transform {
        .init(id)
    }

    public static let stripCombiningMarks = CFString.Transform(kCFStringTransformStripCombiningMarks)
    public static let toLatin = CFString.Transform(kCFStringTransformToLatin)
    public static let fullwidthHalfwidth = CFString.Transform(kCFStringTransformFullwidthHalfwidth)
    public static let latinKatakana = CFString.Transform(kCFStringTransformLatinKatakana)
    public static let latinHiragana = CFString.Transform(kCFStringTransformLatinHiragana)
    public static let hiraganaKatakana = CFString.Transform(kCFStringTransformHiraganaKatakana)
    public static let mandarinLatin = CFString.Transform(kCFStringTransformMandarinLatin)
    public static let latinHangul = CFString.Transform(kCFStringTransformLatinHangul)
    public static let latinArabic = CFString.Transform(kCFStringTransformLatinArabic)
    public static let latinHebrew = CFString.Transform(kCFStringTransformLatinHebrew)
    public static let latinThai = CFString.Transform(kCFStringTransformLatinThai)
    public static let latinCyrillic = CFString.Transform(kCFStringTransformLatinCyrillic)
    public static let latinGreek = CFString.Transform(kCFStringTransformLatinGreek)
    public static let toXMLHex = CFString.Transform(kCFStringTransformToXMLHex)
    public static let toUnicodeName = CFString.Transform(kCFStringTransformToUnicodeName)
    public static let stripDiacritics = CFString.Transform(kCFStringTransformStripDiacritics)
}
