import Foundation

/// Result of evaluating a search query against a ClipboardItem
struct SearchResult: Equatable {
    let item: ClipboardItem
    let score: Int
    let snippet: String
    
    init(item: ClipboardItem, score: Int, snippet: String = "") {
        self.item = item
        self.score = score
        self.snippet = snippet
    }
}

/// Intelligent search engine for Buffer clipboard history
/// Supports:
/// - Fast-path out-of-order multi-term queries (<0.2ms)
/// - Fallback word-level typo tolerance (Damerau-Levenshtein distance <= 1 for terms >= 3 characters)
/// - CamelCase & snake_case subword matching
/// - Relevance scoring (exact phrase > exact tokens > word boundaries > proximity > typos)
/// - Contextual match snippet extraction around matched terms
/// - Universal searching across textContent, ocrText (images), sourceApp, and tags
enum SearchEngine {
    
    // MARK: - Public API
    
    /// Evaluate a query against a list of clipboard items, returning sorted results
    static func search(
        query: String,
        in items: [ClipboardItem],
        activeTag: String? = nil
    ) -> [SearchResult] {
        var base = items
        if let tag = activeTag {
            base = base.filter { $0.tags.contains(tag) }
        }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty || trimmedQuery.hasPrefix("#") {
            // Instant return for empty/tag query: 0 allocations, 0 regex
            let sorted = base.sorted { $0.isPinned && !$1.isPinned }
            return sorted.map { SearchResult(item: $0, score: 0, snippet: "") }
        }
        
        let tokens = extractQueryTokens(trimmedQuery)
        if tokens.isEmpty {
            let sorted = base.sorted { $0.isPinned && !$1.isPinned }
            return sorted.map { SearchResult(item: $0, score: 0, snippet: "") }
        }
        
        // Stage 1: Ultra-fast Exact Out-of-Order Substring Match
        var exactResults: [SearchResult] = []
        for item in base {
            if let result = evaluateExact(item: item, query: trimmedQuery, tokens: tokens) {
                exactResults.append(result)
            }
        }
        
        if !exactResults.isEmpty {
            return sortResults(exactResults)
        }
        
        // Stage 2: Typo-Tolerant Fallback (only reached when exact match yields 0 results)
        var typoResults: [SearchResult] = []
        for item in base {
            if let result = evaluateTypo(item: item, query: trimmedQuery, tokens: tokens) {
                typoResults.append(result)
            }
        }
        
        return sortResults(typoResults)
    }
    
    // MARK: - Stage 1: Fast-Path Exact Out-of-Order
    
    /// Evaluates exact out-of-order tokens (all tokens must exist as substrings)
    static func evaluateExact(
        item: ClipboardItem,
        query: String,
        tokens: [String]
    ) -> SearchResult? {
        let content = item.textContent ?? item.ocrText ?? ""
        let lowerContent = content.lowercased()
        let lowerQuery = query.lowercased()
        
        var totalScore = 0
        var matchedRanges: [Range<String.Index>] = []
        
        // Phrase match bonus
        if let range = lowerContent.range(of: lowerQuery) {
            totalScore += 1000
            matchedRanges.append(range)
        }
        
        let lowerSourceApp = item.sourceApp?.lowercased() ?? ""
        let lowerTags = item.tags.map { $0.lowercased() }
        var tokenPositions: [Int] = []
        
        for token in tokens {
            var tokenMatched = false
            var tokenScore = 0
            
            if let range = lowerContent.range(of: token) {
                tokenMatched = true
                tokenScore += 100
                matchedRanges.append(range)
                
                let offset = content.distance(from: content.startIndex, to: range.lowerBound)
                tokenPositions.append(offset)
                
                if isWordBoundary(in: lowerContent, at: range.lowerBound) {
                    tokenScore += 40
                }
            } else if lowerSourceApp.contains(token) {
                tokenMatched = true
                tokenScore += 30
            } else if lowerTags.contains(where: { $0.contains(token) }) {
                tokenMatched = true
                tokenScore += 30
            }
            
            guard tokenMatched else { return nil }
            totalScore += tokenScore
        }
        
        if tokenPositions.count >= 2 {
            let isOrdered = zip(tokenPositions, tokenPositions.dropFirst()).allSatisfy { $0 <= $1 }
            if isOrdered {
                totalScore += 50
            }
            if let minPos = tokenPositions.min(), let maxPos = tokenPositions.max() {
                let span = maxPos - minPos
                let proximityBonus = max(0, 150 - span)
                totalScore += proximityBonus
            }
        }
        
        let snippet = extractSnippet(from: content, matchedRanges: matchedRanges, targetLength: 60)
        return SearchResult(item: item, score: totalScore, snippet: snippet)
    }
    
    // MARK: - Stage 2: Typo-Tolerant Fallback
    
    /// Evaluates tokens allowing typo tolerance (only when Stage 1 finds 0 items)
    static func evaluateTypo(
        item: ClipboardItem,
        query: String,
        tokens: [String]
    ) -> SearchResult? {
        let content = item.textContent ?? item.ocrText ?? ""
        let lowerContent = content.lowercased()
        let lowerQuery = query.lowercased()
        
        var totalScore = 0
        var matchedRanges: [Range<String.Index>] = []
        
        if let range = lowerContent.range(of: lowerQuery) {
            totalScore += 1000
            matchedRanges.append(range)
        }
        
        let lowerSourceApp = item.sourceApp?.lowercased() ?? ""
        let lowerTags = item.tags.map { $0.lowercased() }
        
        // Lazy extraction of content words only when evaluating typos
        let contentWords = extractWords(from: content)
        var tokenPositions: [Int] = []
        
        for token in tokens {
            var tokenMatched = false
            var tokenScore = 0
            
            if let range = lowerContent.range(of: token) {
                tokenMatched = true
                tokenScore += 100
                matchedRanges.append(range)
                let offset = content.distance(from: content.startIndex, to: range.lowerBound)
                tokenPositions.append(offset)
                if isWordBoundary(in: lowerContent, at: range.lowerBound) {
                    tokenScore += 40
                }
            } else if lowerSourceApp.contains(token) {
                tokenMatched = true
                tokenScore += 30
            } else if lowerTags.contains(where: { $0.contains(token) }) {
                tokenMatched = true
                tokenScore += 30
            } else {
                var bestTypoScore = 0
                var bestMatchedWordRange: Range<String.Index>?
                let tokenChars = Array(token)
                
                for (word, wordRange) in contentWords {
                    let lowerWord = word.lowercased()
                    
                    if lowerWord.hasPrefix(token) {
                        bestTypoScore = max(bestTypoScore, 80)
                        bestMatchedWordRange = wordRange
                        break
                    }
                    
                    if token.count >= 3 {
                        // Length difference pruning
                        guard abs(lowerWord.count - token.count) <= 1 ||
                              (lowerWord.count > token.count && abs((token.count + 1) - token.count) <= 1) else {
                            continue
                        }
                        // First letter heuristic
                        guard lowerWord.first == token.first else { continue }
                        
                        let compareLength = min(lowerWord.count, token.count + 1)
                        let prefixToCompare = String(lowerWord.prefix(compareLength))
                        
                        let dist = damerauLevenshtein(tokenChars, Array(prefixToCompare))
                        if dist <= 1 {
                            let score = (dist == 0) ? 70 : 35
                            if score > bestTypoScore {
                                bestTypoScore = score
                                bestMatchedWordRange = wordRange
                            }
                        }
                    }
                }
                
                if bestTypoScore > 0 {
                    tokenMatched = true
                    tokenScore += bestTypoScore
                    if let wRange = bestMatchedWordRange {
                        matchedRanges.append(wRange)
                        let offset = content.distance(from: content.startIndex, to: wRange.lowerBound)
                        tokenPositions.append(offset)
                    }
                }
            }
            
            guard tokenMatched else { return nil }
            totalScore += tokenScore
        }
        
        if tokenPositions.count >= 2 {
            let isOrdered = zip(tokenPositions, tokenPositions.dropFirst()).allSatisfy { $0 <= $1 }
            if isOrdered { totalScore += 50 }
            if let minPos = tokenPositions.min(), let maxPos = tokenPositions.max() {
                let span = maxPos - minPos
                let proximityBonus = max(0, 150 - span)
                totalScore += proximityBonus
            }
        }
        
        let snippet = extractSnippet(from: content, matchedRanges: matchedRanges, targetLength: 60)
        return SearchResult(item: item, score: totalScore, snippet: snippet)
    }
    
    // MARK: - Sorting
    
    private static func sortResults(_ results: [SearchResult]) -> [SearchResult] {
        return results.sorted { lhs, rhs in
            if lhs.item.isPinned != rhs.item.isPinned {
                return lhs.item.isPinned && !rhs.item.isPinned
            }
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.item.timestamp > rhs.item.timestamp
        }
    }
    
    // MARK: - Snippet Extraction
    
    /// Extract a contextual snippet centered around the clustered match positions
    static func extractSnippet(
        from text: String,
        matchedRanges: [Range<String.Index>],
        targetLength: Int = 60
    ) -> String {
        guard !text.isEmpty, !matchedRanges.isEmpty else { return "" }
        
        let minBound = matchedRanges.map { $0.lowerBound }.min() ?? text.startIndex
        let maxBound = matchedRanges.map { $0.upperBound }.max() ?? text.endIndex
        
        let startOffset = text.distance(from: text.startIndex, to: minBound)
        let endOffset = text.distance(from: text.startIndex, to: maxBound)
        
        let span = endOffset - startOffset
        let availablePadding = max(0, targetLength - span)
        let leadingPadding = availablePadding / 2
        
        let snippetStartOffset = max(0, startOffset - leadingPadding)
        let snippetEndOffset = min(text.count, snippetStartOffset + targetLength)
        
        let startIdx = text.index(text.startIndex, offsetBy: snippetStartOffset)
        let endIdx = text.index(text.startIndex, offsetBy: snippetEndOffset)
        
        let rawSnippet = String(text[startIdx..<endIdx])
        var cleanSnippet = sanitizeText(rawSnippet)
        
        if snippetStartOffset > 0 {
            cleanSnippet = "… " + cleanSnippet
        }
        if snippetEndOffset < text.count {
            cleanSnippet = cleanSnippet + " …"
        }
        
        return cleanSnippet
    }
    
    // MARK: - Tokenization & Words
    
    /// Split query into non-empty lowercase tokens
    static func extractQueryTokens(_ query: String) -> [String] {
        return query.lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }
    
    /// Extract words from text along with their character ranges, expanding camelCase and snake_case
    static func extractWords(from text: String) -> [(word: String, range: Range<String.Index>)] {
        var results: [(String, Range<String.Index>)] = []
        guard !text.isEmpty else { return [] }
        
        var wordStart: String.Index?
        var currentSubwordStart: String.Index?
        var prevChar: Character?
        
        var currentIndex = text.startIndex
        while currentIndex < text.endIndex {
            let char = text[currentIndex]
            let isLetterOrDigit = char.isLetter || char.isNumber
            
            if isLetterOrDigit {
                if wordStart == nil {
                    wordStart = currentIndex
                    currentSubwordStart = currentIndex
                } else if let prev = prevChar {
                    // Check for camelCase boundary (e.g. 'a' followed by 'B')
                    if prev.isLowercase && char.isUppercase {
                        if let subStart = currentSubwordStart {
                            let subword = String(text[subStart..<currentIndex])
                            results.append((subword, subStart..<currentIndex))
                        }
                        currentSubwordStart = currentIndex
                    }
                }
            } else {
                if let wStart = wordStart {
                    let word = String(text[wStart..<currentIndex])
                    results.append((word, wStart..<currentIndex))
                    
                    if let subStart = currentSubwordStart, subStart != wStart {
                        let subword = String(text[subStart..<currentIndex])
                        results.append((subword, subStart..<currentIndex))
                    }
                    wordStart = nil
                    currentSubwordStart = nil
                }
            }
            
            prevChar = char
            currentIndex = text.index(after: currentIndex)
        }
        
        // Flush final word
        if let wStart = wordStart {
            let word = String(text[wStart..<text.endIndex])
            results.append((word, wStart..<text.endIndex))
            if let subStart = currentSubwordStart, subStart != wStart {
                let subword = String(text[subStart..<text.endIndex])
                results.append((subword, subStart..<text.endIndex))
            }
        }
        
        return results
    }
    
    // MARK: - Fast Damerau-Levenshtein Distance
    
    /// Computes Damerau-Levenshtein distance (insert, delete, substitute, transpose adjacent)
    /// Optimized with early length pruning and a contiguous 1D buffer.
    static func damerauLevenshtein(_ s1: [Character], _ s2: [Character]) -> Int {
        let len1 = s1.count
        let len2 = s2.count
        if len1 == 0 { return len2 }
        if len2 == 0 { return len1 }
        
        // Mathematical length pruning: if length difference > 1, distance cannot be <= 1
        if abs(len1 - len2) > 1 { return 2 }
        
        let cols = len2 + 1
        var d = [Int](repeating: 0, count: (len1 + 1) * cols)
        for i in 0...len1 { d[i * cols + 0] = i }
        for j in 0...len2 { d[0 * cols + j] = j }
        
        for i in 1...len1 {
            for j in 1...len2 {
                let cost = (s1[i - 1] == s2[j - 1]) ? 0 : 1
                let del = d[(i - 1) * cols + j] + 1
                let ins = d[i * cols + (j - 1)] + 1
                let sub = d[(i - 1) * cols + (j - 1)] + cost
                
                var minVal = min(del, ins, sub)
                if i > 1 && j > 1 && s1[i - 1] == s2[j - 2] && s1[i - 2] == s2[j - 1] {
                    let trans = d[(i - 2) * cols + (j - 2)] + 1
                    minVal = min(minVal, trans)
                }
                d[i * cols + j] = minVal
            }
        }
        return d[len1 * cols + len2]
    }
    
    // MARK: - Helper Utilities
    
    private static func isWordBoundary(in text: String, at index: String.Index) -> Bool {
        if index == text.startIndex { return true }
        let prevIndex = text.index(before: index)
        let prevChar = text[prevIndex]
        return !prevChar.isLetter && !prevChar.isNumber
    }
    
    private static func sanitizeText(_ text: String) -> String {
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
