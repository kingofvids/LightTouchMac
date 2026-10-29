import Foundation

/// Compiled patterns, kept: the call sites run them repeatedly.
private let regexCache = HostLock<[String: NSRegularExpression]>(initialState: [:])

private func compiledRegex(_ pattern: String) -> NSRegularExpression? {
    regexCache.hostWithLock { cache in
        if let found = cache[pattern] { return found }
        guard let made = try? NSRegularExpression(pattern: pattern) else { return nil }
        cache[pattern] = made
        return made
    }
}

extension String {
    /// Swift's `Regex` (macOS 13) for macOS 12, on NSRegularExpression (ICU syntax).
    /// Each match is its capture groups as strings: index 0 the whole match, then groups 1…n ("" if one didn't take part).
    private func groups(of match: NSTextCheckingResult) -> [String] {
        let whole = self as NSString
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : whole.substring(with: range)
        }
    }

    /// The first match anywhere in the string.
    public func hostFirstMatch(_ pattern: String) -> [String]? {
        guard let regex = compiledRegex(pattern),
            let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self))
        else { return nil }
        return groups(of: match)
    }

    /// Every non-overlapping match.
    public func hostMatches(_ pattern: String) -> [[String]] {
        guard let regex = compiledRegex(pattern) else { return [] }
        return regex.matches(in: self, range: NSRange(startIndex..., in: self)).map { groups(of: $0) }
    }

    /// A match of the whole string (`wholeMatch(of:)`).
    public func hostWholeMatch(_ pattern: String) -> [String]? {
        guard let regex = compiledRegex(pattern) else { return nil }
        let full = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, options: [.anchored], range: full), match.range == full else {
            return nil
        }
        return groups(of: match)
    }
}

extension Collection where Element: Equatable {
    /// `firstRange(of:)` (macOS 13) for macOS 12: where `needle` first occurs, as indices of this collection.
    public func hostFirstRange<Needle: Collection>(of needle: Needle) -> Range<Index>? where Needle.Element == Element {
        guard let first = needle.first else { return startIndex..<startIndex }
        let count = needle.count
        var start = startIndex
        while start != endIndex {
            if self[start] == first, let end = index(start, offsetBy: count, limitedBy: endIndex) {
                if self[start..<end].elementsEqual(needle) { return start..<end }
            }
            start = index(after: start)
        }
        return nil
    }
}
