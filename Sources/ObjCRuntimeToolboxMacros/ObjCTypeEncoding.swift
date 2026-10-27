/// Derives Objective-C method type encodings from Swift type syntax at compile
/// time.
///
/// ## Why this exists
///
/// Replacing a method implementation requires two things to agree: the
/// `@convention(block)` Swift signature that becomes the new IMP, and the type
/// encoding registered for it. Written by hand they are two independent strings
/// that nothing compares — a `Bool` typed as `Int` in the block passes every
/// check and then corrupts registers when the host calls it.
///
/// Deriving the encoding *from* the Swift signature removes that whole class of
/// mistake: there is one hand-written description of the method, and the
/// runtime comparison against the live class becomes a real assertion rather
/// than a check of one guess against another.
///
/// ## Bare encodings
///
/// Encodings are emitted without frame offsets — `v@:@B` rather than
/// `v28@0:8@16B24`. The runtime reports the offset-annotated flavour, and
/// ``ObjCTypeEncodingNormalization`` strips digits from both sides before
/// comparing, so the offsets carry no information the comparison uses. Not
/// computing them avoids reimplementing the runtime's frame-layout rules, which
/// are not part of any stable contract.
///
/// ## Unknown types
///
/// The table only covers spellings it can be sure of. An identifier it does not
/// list — `TimeInterval`, `NSInteger`, `NSTextAlignment`, a class it has no
/// entry for — is not guessed: the generated code calls
/// `ObjCRuntimeToolbox._ObjCTypeEncoding.of(T.self)` instead, and overload
/// resolution at that call site picks the encoding from what the type is, with
/// typealiases seen through. See ``methodEncodingExpression(returnTypeText:parameterTypeTexts:)``.
/// Until that existed every unknown name was encoded as an object, which made
/// a typealias or an imported enumeration fail the install-time comparison and
/// left `@RuntimeClassProxy` — which has no `typeEncoding:` to fall back on —
/// unusable for it.
///
/// ``encoding(forTypeText:)`` still answers `@` for an unknown name; it is what
/// the shape decisions below the encoding (object or scalar return) used to rest
/// on, and only types the table knows reach it now.
enum ObjCTypeEncoding {

    /// Encoding for a method's full signature: return type, receiver, selector,
    /// then one entry per declared parameter.
    ///
    /// - Parameters:
    ///   - returnTypeText: Swift return type as written, or `nil` for `Void`.
    ///   - parameterTypeTexts: Swift parameter types as written, excluding the
    ///     implicit receiver and selector.
    static func methodEncoding(
        returnTypeText: String?,
        parameterTypeTexts: [String]
    ) -> String {
        var result = encoding(forTypeText: returnTypeText) + "@:"
        for parameterTypeText in parameterTypeTexts {
            result += encoding(forTypeText: parameterTypeText)
        }
        return result
    }

    /// Encoding for a single Swift type. `nil` means `Void`.
    static func encoding(forTypeText typeText: String?) -> String {
        guard let typeText else { return "v" }

        let normalizedTypeText = stripOptionalityAndSugar(from: typeText)
        if normalizedTypeText.isEmpty { return "v" }

        if let knownEncoding = encodingTable[normalizedTypeText] {
            return knownEncoding
        }

        // Any pointer-shaped generic collapses to a raw pointer; the runtime
        // does not distinguish pointee types in a method encoding beyond the
        // `^` prefix, and `^v` is what the compiler emits for `void *`.
        if normalizedTypeText.hasPrefix("Unsafe"), normalizedTypeText.containsSubstring("Pointer") {
            return "^v"
        }

        // Unknown identifier — assume an object. See the type-level discussion.
        return "@"
    }

    /// Whether the table, rather than the compiler, decides this type's
    /// encoding. `nil` (`Void`) counts as known.
    static func isKnownType(_ typeText: String?) -> Bool {
        guard let typeText else { return true }
        let normalizedTypeText = stripOptionalityAndSugar(from: typeText)
        if normalizedTypeText.isEmpty { return true }
        if encodingTable[normalizedTypeText] != nil { return true }
        if normalizedTypeText.hasPrefix("Unsafe"), normalizedTypeText.containsSubstring("Pointer") { return true }
        return false
    }

    // MARK: - Encodings the compiler works out

    /// Source text evaluating to the method's encoding.
    ///
    /// A string literal when the table knows every type, which keeps the
    /// expansion of such a method exactly as it was. Otherwise the encoding is
    /// assembled at run time from parts, and each type the table does not know
    /// becomes `ObjCRuntimeToolbox._ObjCTypeEncoding.of(T.self)`: overload
    /// resolution at that call site sees through typealiases and tells an
    /// imported enumeration from an object, which a spelling cannot.
    static func methodEncodingExpression(
        returnTypeText: String?,
        parameterTypeTexts: [String]
    ) -> String {
        let everyTypeIsKnown = isKnownType(returnTypeText) && parameterTypeTexts.allSatisfy { isKnownType($0) }
        if everyTypeIsKnown {
            return stringLiteral(methodEncoding(returnTypeText: returnTypeText, parameterTypeTexts: parameterTypeTexts))
        }
        let components = [encodingComponentExpression(for: returnTypeText), stringLiteral("@:")]
            + parameterTypeTexts.map { encodingComponentExpression(for: $0) }
        return "ObjCRuntimeToolbox._ObjCTypeEncoding.method([\(components.joined(separator: ", "))])"
    }

    /// One type's part of ``methodEncodingExpression(returnTypeText:parameterTypeTexts:)``.
    private static func encodingComponentExpression(for typeText: String?) -> String {
        guard let typeText, !isKnownType(typeText) else {
            return stringLiteral(encoding(forTypeText: typeText))
        }
        return "ObjCRuntimeToolbox._ObjCTypeEncoding.of(\(metatypeExpression(forTypeText: typeText)))"
    }

    /// `T.self` for a written type, with its optionality removed: an optional
    /// is encoded, and returned, as what it wraps. Wrapped in parentheses where
    /// `.self` would otherwise bind to only part of the type.
    static func metatypeExpression(forTypeText typeText: String) -> String {
        let unwrapped = strippingOptionality(from: typeText)
        let needsParentheses = unwrapped.hasPrefix("any ") || unwrapped.hasPrefix("some ")
            || unwrapped.hasPrefix("@") || unwrapped.containsSubstring("->") || unwrapped.containsSubstring("&")
        return needsParentheses ? "(\(unwrapped)).self" : "\(unwrapped).self"
    }

    // MARK: - Normalisation

    /// Reduces a written type to the name the table is keyed on.
    ///
    /// Handles the spellings that reach a macro as raw source text: trailing
    /// `?` / `!`, an explicit `Optional<…>`, redundant parentheses, and module
    /// qualification (`Foundation.URL` → `URL`). Collection and existential
    /// sugar all resolve to objects, so they are folded to a single key rather
    /// than parsed.
    static func stripOptionalityAndSugar(from typeText: String) -> String {
        var result = strippingOptionality(from: typeText)

        // Arrays, dictionaries and sets are all objects; so is any existential
        // or metatype-free protocol composition. Fold them to one key.
        if result.hasPrefix("["), result.hasSuffix("]") { return "Array" }
        if result.hasPrefix("any ") || result.hasPrefix("some ") { return "AnyObject" }

        // `Foundation.URL` and `Swift.Int` reach the macro fully qualified when
        // the user writes them that way. The table is keyed on the last
        // component, which is unambiguous for every entry in it.
        if let lastComponent = result.split(separator: ".").last, result.containsSubstring(".") {
            result = String(lastComponent)
        }

        return result
    }

    /// A written type with every optional layer and redundant pair of
    /// parentheses removed: `Optional<Foo>?`, `(Foo)?` and `Foo!` all become
    /// `Foo`.
    static func strippingOptionality(from typeText: String) -> String {
        var result = typeText.trimmedWhitespace

        // Unwrap repeatedly: `Optional<Foo>?`, `(Foo)?`, `Foo!` all appear.
        var didChange = true
        while didChange {
            didChange = false

            if result.hasSuffix("?") || result.hasSuffix("!") {
                result = String(result.dropLast()).trimmedWhitespace
                didChange = true
                continue
            }

            if result.hasPrefix("("), result.hasSuffix(")"), isBalancedWhenOuterParenthesesDropped(result) {
                result = String(result.dropFirst().dropLast()).trimmedWhitespace
                didChange = true
                continue
            }

            if result.hasPrefix("Optional<"), result.hasSuffix(">") {
                result = String(result.dropFirst("Optional<".count).dropLast()).trimmedWhitespace
                didChange = true
                continue
            }
        }

        return result
    }

    /// Whether dropping the outer parentheses leaves a balanced string.
    ///
    /// Guards against treating `(Int, Int)` — where the outer parentheses are
    /// the tuple itself — or `(A) -> (B)` as a redundant wrapper. Tuples and
    /// function types are rejected upstream by the representability diagnostic;
    /// this only keeps the unwrapping loop from mangling them first.
    private static func isBalancedWhenOuterParenthesesDropped(_ text: String) -> Bool {
        var depth = 0
        for (offset, character) in text.enumerated() {
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                // Closed before the end means the leading "(" was not the
                // partner of the trailing ")".
                if depth == 0 && offset != text.count - 1 { return false }
            }
        }
        return depth == 0
    }

    // MARK: - Table

    /// Swift type name to Objective-C encoding, for 64-bit Apple platforms.
    ///
    /// `Bool` maps to `B` (C `bool`), which is what `BOOL` is on arm64. On
    /// x86_64 `BOOL` is `signed char` (`c`) instead; the comparison in
    /// ``ObjCTypeEncodingNormalization`` treats the two as equivalent, so a
    /// single table entry is correct on both. They share a size and an
    /// argument-passing rule, so nothing about the call is ambiguous.
    private static let encodingTable: [String: String] = [
        // Void
        "Void": "v",
        "()": "v",

        // Objects and object-like references
        "AnyObject": "@",
        "Any": "@",
        "NSObject": "@",
        "String": "@",
        "NSString": "@",
        "URL": "@",
        "NSURL": "@",
        "Array": "@",
        "NSArray": "@",
        "Dictionary": "@",
        "NSDictionary": "@",
        "Set": "@",
        "NSSet": "@",
        "Data": "@",
        "NSData": "@",
        "Date": "@",
        "NSDate": "@",
        "NSNumber": "@",
        "NSValue": "@",
        "NSError": "@",
        "Error": "@",

        // Runtime references
        "AnyClass": "#",
        "Selector": ":",
        "Protocol": "@",

        // Integers. `Int` / `UInt` are `NSInteger` / `NSUInteger`, which are
        // `long` / `unsigned long` on every 64-bit Apple platform.
        "Bool": "B",
        "Int": "q",
        "UInt": "Q",
        "Int8": "c",
        "UInt8": "C",
        "CChar": "c",
        "Int16": "s",
        "UInt16": "S",
        "Int32": "i",
        "UInt32": "I",
        "Int64": "q",
        "UInt64": "Q",

        // Floating point
        "Float": "f",
        "Double": "d",
        "CGFloat": "d",

        // Pointers
        "UnsafeRawPointer": "^v",
        "UnsafeMutableRawPointer": "^v",
        "OpaquePointer": "^v",

        // Structs that appear routinely in AppKit / UIKit signatures. Written
        // out because the runtime encodes struct layout, not just a tag.
        "CGPoint": "{CGPoint=dd}",
        "CGSize": "{CGSize=dd}",
        "CGVector": "{CGVector=dd}",
        "CGRect": "{CGRect={CGPoint=dd}{CGSize=dd}}",
        "NSRange": "{_NSRange=QQ}",
    ]
}
