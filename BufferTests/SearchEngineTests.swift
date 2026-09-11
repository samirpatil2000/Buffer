import XCTest
#if canImport(Buffer)
@testable import Buffer
#endif

class SearchEngineTests: XCTestCase {
    
    // MARK: - Damerau-Levenshtein Tests
    
    func testDamerauLevenshteinExactMatch() {
        let dist = SearchEngine.damerauLevenshtein(Array("admin"), Array("admin"))
        XCTAssertEqual(dist, 0)
    }
    
    func testDamerauLevenshteinTransposition() {
        // Transposition of adjacent characters: jtw -> jwt
        let dist = SearchEngine.damerauLevenshtein(Array("jtw"), Array("jwt"))
        XCTAssertEqual(dist, 1)
    }
    
    func testDamerauLevenshteinDeletion() {
        // admn -> admin (missing 'i')
        let dist = SearchEngine.damerauLevenshtein(Array("admn"), Array("admin"))
        XCTAssertEqual(dist, 1)
    }
    
    func testDamerauLevenshteinInsertion() {
        // tokenn -> token (extra 'n')
        let dist = SearchEngine.damerauLevenshtein(Array("tokenn"), Array("token"))
        XCTAssertEqual(dist, 1)
    }
    
    func testDamerauLevenshteinSubstitution() {
        // admin -> edmin
        let dist = SearchEngine.damerauLevenshtein(Array("edmin"), Array("admin"))
        XCTAssertEqual(dist, 1)
    }
    
    // MARK: - Out-of-Order Matching Tests
    
    func testOutOfOrderWordsMatch() {
        let item = ClipboardItem.text("func authenticateWithJWT(token: String) -> User")
        let items = [item]
        
        // Out of order: "jwt auth" vs "authenticateWithJWT"
        let results = SearchEngine.search(query: "jwt auth", in: items)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.id, item.id)
    }
    
    func testReverseOrderMatching() {
        let item = ClipboardItem.text("I bought an apple and later ate a banana")
        let items = [item]
        
        // Search "banana apple"
        let results = SearchEngine.search(query: "banana apple", in: items)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.id, item.id)
    }
    
    // MARK: - Typo Tolerance Tests
    
    func testTypoToleranceAdmnMatchesAdmin() {
        let item = ClipboardItem.text("System administrator configuration notes")
        let items = [item]
        
        let results = SearchEngine.search(query: "admn config", in: items)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.id, item.id)
    }
    
    func testTypoToleranceJtwMatchesJwt() {
        let item = ClipboardItem.text("Bearer token using JWT format")
        let items = [item]
        
        let results = SearchEngine.search(query: "bearer jtw", in: items)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.id, item.id)
    }
    
    // MARK: - Relevance Ranking Tests
    
    func testExactPhraseRanksHigherThanOutOfOrder() {
        let itemExact = ClipboardItem.text("docker compose up -d")
        let itemOutOfOrder = ClipboardItem.text("compose your music while running docker")
        
        let results = SearchEngine.search(query: "docker compose", in: [itemOutOfOrder, itemExact])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].item.id, itemExact.id, "Exact phrase should rank first")
        XCTAssertEqual(results[1].item.id, itemOutOfOrder.id)
    }
    
    func testExactMatchRanksHigherThanTypoMatch() {
        let itemExact = ClipboardItem.text("The admin logged into the dashboard")
        let itemTypoTarget = ClipboardItem.text("The admit was processed yesterday")
        
        let results = SearchEngine.search(query: "admin", in: [itemTypoTarget, itemExact])
        XCTAssertEqual(results[0].item.id, itemExact.id, "Exact match should rank ahead of typo match")
    }
    
    // MARK: - Universal Search (OCR, Tags, SourceApp)
    
    func testImageOCRTextSearch() {
        var item = ClipboardItem.image(filename: "screenshot.png")
        item.ocrText = "Invoice #10293 paid via Stripe"
        
        let results = SearchEngine.search(query: "invoice stripe", in: [item])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.id, item.id)
    }
    
    func testSourceAppSearch() {
        let item = ClipboardItem(
            type: .text,
            sourceApp: "Xcode",
            textContent: "let x = 42"
        )
        let results = SearchEngine.search(query: "xcode 42", in: [item])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.id, item.id)
    }
    
    func testTagsSearch() {
        var item = ClipboardItem.text("SELECT * FROM users")
        item.tags = ["database", "sql"]
        
        let results = SearchEngine.search(query: "database users", in: [item])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.id, item.id)
    }
    
    // MARK: - Contextual Snippet Extraction
    
    func testSnippetCentersAroundMatch() {
        let longPrefix = String(repeating: "abcdef ", count: 20) // ~140 chars
        let content = longPrefix + "TARGET_KEYWORD_HERE " + longPrefix
        let item = ClipboardItem.text(content)
        
        let results = SearchEngine.search(query: "TARGET_KEYWORD_HERE", in: [item])
        XCTAssertEqual(results.count, 1)
        guard let snippet = results.first?.snippet else {
            XCTFail("Missing snippet")
            return
        }
        
        XCTAssertTrue(snippet.contains("TARGET_KEYWORD_HERE"), "Snippet should contain matched target")
        XCTAssertTrue(snippet.hasPrefix("…"), "Snippet should have leading ellipsis when match is not at start")
        XCTAssertTrue(snippet.hasSuffix("…"), "Snippet should have trailing ellipsis when match is not at end")
    }
}
