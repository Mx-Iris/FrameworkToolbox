/// Small string utilities for the macro plugin.
///
/// Deliberately standard-library only, and deliberately spelled out rather than
/// reached for from Foundation or the regex-backed `contains(_:)`. A compiler
/// plugin runs on every build of every target that expands one of these macros,
/// so it stays off Foundation; and `StringProtocol.contains(_: some
/// StringProtocol)` carries a macOS 13 availability floor that this package's
/// macOS 10.15 floor cannot adopt.
extension String {

    /// Drops leading and trailing whitespace, including newlines.
    var trimmedWhitespace: String {
        var characters = Substring(self)
        while let first = characters.first, first.isWhitespace {
            characters = characters.dropFirst()
        }
        while let last = characters.last, last.isWhitespace {
            characters = characters.dropLast()
        }
        return String(characters)
    }

    /// Whether `target` occurs anywhere in this string.
    func containsSubstring(_ target: String) -> Bool {
        firstIndex(ofSubstring: target, from: startIndex) != nil
    }

    /// Replaces every occurrence of `target` with `replacement`.
    func replacingEvery(_ target: String, with replacement: String) -> String {
        guard !target.isEmpty else { return self }
        var result = ""
        result.reserveCapacity(count)
        var scanIndex = startIndex
        while let matchStart = firstIndex(ofSubstring: target, from: scanIndex) {
            result += self[scanIndex ..< matchStart]
            result += replacement
            scanIndex = index(matchStart, offsetBy: target.count)
        }
        result += self[scanIndex...]
        return result
    }

    /// Index of the first occurrence of `target` at or after `searchStart`.
    private func firstIndex(ofSubstring target: String, from searchStart: Index) -> Index? {
        guard !target.isEmpty else { return searchStart }
        var candidate = searchStart
        while candidate < endIndex {
            guard let candidateEnd = index(candidate, offsetBy: target.count, limitedBy: endIndex) else {
                return nil
            }
            if self[candidate ..< candidateEnd] == target { return candidate }
            candidate = index(after: candidate)
        }
        return nil
    }
}
