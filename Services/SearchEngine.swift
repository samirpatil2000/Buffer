import Foundation

/// Result of evaluating a search query against a ClipboardItem
struct SearchResult: Equatable {
    let item: ClipboardItem
    let score: Int
    let snippet: String
    
    init(item: ClipboardItem, score: Int, snippet: String) {
        self.item = item
        self.score = score
        self.snippet = snippet
    }
}

/// Intelligent search engine for Buffer clipboard history
/// Supports:
/// - Out-of-order multi-term queries (AND matching)
/// - Word-level typo tolerance (Damerau-Levenshtein distance <= 1 for terms >= 3 characters)
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
            // No search query: return items in pin-first chronological order with default snippets
            let sorted = base.sorted { $0.isPinned && !$1.isPinned }
            return sorted.map { SearchResult(item: $0, score: 0, snippet: defaultSnippet(for: $0)) }
        }
        
        let tokens = extractQueryTokens(trimmedQuery)
        if tokens.isEmpty {
            let sorted = base.sorted { $0.isPinned && !$1.isPinned }
            return sorted.map { SearchResult(item: $0, score: 0, snippet: defaultSnippet(for: $0)) }
        }
        
        var results: [SearchResult] = []
        
        for item in base {
            if let result = evaluate(item: item, query: trimmedQuery, tokens: tokens) {
                results.append(result)
            }
        }
        
        // Sorting strategy:
        // 1. Pinned items float to top
        // 2. Highest search score descending
        // 3. Newest timestamp descending
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
    
    // MARK: - Evaluation
    
    /// Evaluate a single item against query tokens
    static func evaluate(
        item: ClipboardItem,
        query: String,
        tokens: [String]
    ) -> SearchResult? {
        let content = item.textContent ?? item.ocrText ?? ""
        let lowerContent = content.lowercased()
        let lowerQuery = query.lowercased()
        
        var totalScore = 0
        var matchedRanges: [Range<String.Index>] = []
        
        // Fast path check: Exact phrase match anywhere in content
        let exactPhraseRange = lowerContent.range(of: lowerQuery)
        if let range = exactPhraseRange {
            totalScore += 1000
            matchedRanges.append(range)
        }
        
        // Check metadata
        let lowerSourceApp = item.sourceApp?.lowercased() ?? ""
        let lowerTags = item.tags.map { $0.lowercased() }
        
        // Extract candidate words from content for typo and subword checking
        let contentWords = extractWords(from: content)
        
        // Keep track of token match positions for proximity & order calculation
        var tokenPositions: [Int] = []
        
        for token in tokens {
            var tokenMatched = false
            var tokenScore = 0
            
            // 1. Direct substring match in content
            if let range = lowerContent.range(of: token) {
                tokenMatched = true
                tokenScore += 100
                matchedRanges.append(range)
                
                let utf16Offset = content.distance(from: content.startIndex, to: range.lowerBound)
                tokenPositions.append(utf16Offset)
                
                // Bonus if at word boundary
                if isWordBoundary(in: lowerContent, at: range.lowerBound) {
                    tokenScore += 40
                }
            }
            
            // 2. Metadata match (sourceApp or tags)
            if !tokenMatched {
                if lowerSourceApp.contains(token) {
                    tokenMatched = true
                    tokenScore += 30
                } else if lowerTags.contains(where: { $0.contains(token) }) {
                    tokenMatched = true
                    tokenScore += 30
                }
            }
            
            // 3. Typo-tolerant and prefix matching against individual words
            if !tokenMatched {
                var bestTypoScore = 0
                var bestMatchedWordRange: Range<String.Index>?
                
                for (word, wordRange) in contentWords {
                    let lowerWord = word.lowercased()
                    
                    // Word prefix match: e.g. "auth" prefix of "authenticate"
                    if lowerWord.hasPrefix(token) {
                        bestTypoScore = max(bestTypoScore, 80)
                        bestMatchedWordRange = wordRange
                        break
                    }
                    
                    // Typo tolerance: only for tokens >= 3 characters to suppress noise
                    if token.count >= 3 {
                        // Compare against the word itself, or a prefix of word with similar length
                        let compareLength = min(lowerWord.count, token.count + 1)
                        let prefixToCompare = String(lowerWord.prefix(compareLength))
                        
                        let dist = damerauLevenshtein(Array(token), Array(prefixToCompare))
                        if dist <= 1 {
                            // Bonus if lengths match closely, slightly less if prefix
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
                        let utf16Offset = content.distance(from: content.startIndex, to: wRange.lowerBound)
                        tokenPositions.append(utf16Offset)
                    }
                }
            }
            
            // If any token fails to match, this item does not match the query (AND logic)
            guard tokenMatched else { return nil }
            
            totalScore += tokenScore
        }
        
        // Bonus for sequential order (if tokens appear in the text in typed order)
        if tokenPositions.count >= 2 {
            let isOrdered = zip(tokenPositions, tokenPositions.dropFirst()).allSatisfy { $0 <= $1 }
            if isOrdered {
                totalScore += 50
            }
            
            // Proximity bonus: closer tokens = higher score
            if let minPos = tokenPositions.min(), let maxPos = tokenPositions.max() {
                let span = maxPos - minPos
                let proximityBonus = max(0, 150 - span)
                totalScore += proximityBonus
            }
        }
        
        // Generate snippet around matched ranges
        let snippet = extractSnippet(from: content, matchedRanges: matchedRanges, targetLength: 60)
        
        return SearchResult(item: item, score: totalScore, snippet: snippet)
    }
    
    // MARK: - Snippet Extraction
    
    /// Extract a contextual snippet centered around the clustered match positions
    static func extractSnippet(
        from text: String,
        matchedRanges: [Range<String.Index>],
        targetLength: Int = 60
    ) -> String {
        guard !text.isEmpty else { return "" }
        
        let cleanedText = sanitizeText(text)
        guard !matchedRanges.isEmpty else {
            return truncate(cleanedText, to: targetLength)
        }
        
        // Find bounding indices in original text
        let minBound = matchedRanges.map { $0.lowerBound }.min() ?? text.startIndex
        let maxBound = matchedRanges.map { $0.upperBound }.max() ?? text.endIndex
        
        let startOffset = text.distance(from: text.startIndex, to: minBound)
        let endOffset = text.distance(from: text.startIndex, to: maxBound)
        
        // If the span fits within target length, center around it
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
    
    /// Default snippet for an item when no search is active
    static func defaultSnippet(for item: ClipboardItem) -> String {
        let text = item.textContent ?? item.ocrText ?? (item.type == .image ? "Image" : "")
        let singleLine = sanitizeText(text)
        return truncate(singleLine, to: 50)
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
    
    // MARK: - Damerau-Levenshtein Distance
    
    /// Computes Damerau-Levenshtein distance (insert, delete, substitute, transpose adjacent)
    static func damerauLevenshtein(_ s1: [Character], _ s2: [Character]) -> Int {
        let len1 = s1.count
        let len2 = s2.count
        if len1 == 0 { return len2 }
        if len2 == 0 { return len1 }
        
        var d = Array(repeating: Array(repeating: 0, count: len2 + 1), count: len1 + 1)
        for i in 0...len1 { d[i][0] = i }
        for j in 0...len2 { d[0][j] = j }
        
        for i in 1...len1 {
            for j in 1...len2 {
                let cost = (s1[i - 1] == s2[j - 1]) ? 0 : 1
                d[i][j] = min(
                    d[i - 1][j] + 1,       // deletion
                    d[i][j - 1] + 1,       // insertion
                    d[i - 1][j - 1] + cost // substitution
                )
                if i > 1 && j > 1 && s1[i - 1] == s2[j - 2] && s1[i - 2] == s2[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) // transposition
                }
            }
        }
        return d[len1][len2]
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
    
    private static func truncate(_ text: String, to limit: Int) -> String {
        if text.count > limit {
            return String(text.prefix(limit)) + "…"
        }
        return text
    }
}
