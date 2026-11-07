import Foundation
import SQLite3

/// Thread-safe manager for the SQLite persistence layer.
/// Replaces monolithic JSON storage with WAL-mode SQLite and FTS5 full-text indexing.
final class DatabaseManager {
    static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.buffer.database", qos: .userInitiated)
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private var isInitialized = false
    
    private init() {}
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Initialization & Schema
    
    /// Open the database at `databaseURL` and initialize schema if needed.
    func initialize(databaseURL: URL) {
        queue.sync {
            guard !isInitialized else { return }
            
            let path = databaseURL.path
            if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                print("[DatabaseManager] Error opening SQLite database at \(path): \(msg)")
                return
            }
            
            // Configure WAL mode and busy timeout for high-concurrency background writes
            executeRawSQL("PRAGMA journal_mode = WAL;")
            executeRawSQL("PRAGMA synchronous = NORMAL;")
            executeRawSQL("PRAGMA busy_timeout = 3000;")
            
            createSchema()
            isInitialized = true
            print("[DatabaseManager] Database initialized at \(path)")
        }
    }
    
    private func executeRawSQL(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let errorMsg = err.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(err)
            print("[DatabaseManager] SQL error for '\(sql)': \(errorMsg)")
        }
    }
    
    private func createSchema() {
        let createItemsTable = """
        CREATE TABLE IF NOT EXISTS items (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            timestamp REAL NOT NULL,
            source_app TEXT,
            preview_text TEXT NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            is_bookmarked INTEGER NOT NULL DEFAULT 0,
            tags TEXT NOT NULL DEFAULT '',
            is_truncated INTEGER NOT NULL DEFAULT 0,
            original_size_bytes INTEGER,
            language TEXT,
            has_images INTEGER NOT NULL DEFAULT 0,
            has_rich_text INTEGER NOT NULL DEFAULT 0,
            text_content TEXT,
            text_filename TEXT,
            image_filename TEXT,
            image_filenames TEXT,
            remote_image_map TEXT,
            links_json TEXT,
            ocr_text TEXT,
            rtf_data BLOB,
            html_data BLOB,
            rtfd_data BLOB
        );
        """
        executeRawSQL(createItemsTable)
        executeRawSQL("CREATE INDEX IF NOT EXISTS idx_items_ordering ON items (is_pinned DESC, timestamp DESC);")
        
        // FTS5 Virtual Table for full-text search
        let createFTS5 = """
        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
            id UNINDEXED,
            preview_text,
            ocr_text,
            tokenize = 'unicode61'
        );
        """
        executeRawSQL(createFTS5)
    }
    
    // MARK: - Migration from JSON
    
    /// Migrates existing history.json items to SQLite if the database is newly initialized.
    func migrateFromJSONIfNeeded(jsonURL: URL) {
        queue.sync {
            guard let db = db else { return }
            guard FileManager.default.fileExists(atPath: jsonURL.path) else { return }
            
            // Check if items table already has records
            var count: Int = 0
            var countStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM items;", -1, &countStmt, nil) == SQLITE_OK {
                if sqlite3_step(countStmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int64(countStmt, 0))
                }
            }
            sqlite3_finalize(countStmt)
            
            guard count == 0 else {
                // Already migrated
                return
            }
            
            print("[DatabaseManager] Found existing history.json. Starting migration...")
            do {
                let data = try Data(contentsOf: jsonURL)
                let legacyItems = try JSONDecoder().decode([ClipboardItem].self, from: data)
                
                guard !legacyItems.isEmpty else { return }
                
                // Create timestamped backup of history.json
                let backupPath = jsonURL.path + ".bak-" + ISO8601DateFormatter().string(from: Date())
                try? FileManager.default.copyItem(atPath: jsonURL.path, toPath: backupPath)
                print("[DatabaseManager] Created backup at \(backupPath)")
                
                executeRawSQL("BEGIN IMMEDIATE TRANSACTION;")
                
                for item in legacyItems {
                    insertItemInternal(item)
                }
                
                executeRawSQL("COMMIT;")
                
                // Verify migration count
                var verifiedCount = 0
                if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM items;", -1, &countStmt, nil) == SQLITE_OK {
                    if sqlite3_step(countStmt) == SQLITE_ROW {
                        verifiedCount = Int(sqlite3_column_int64(countStmt, 0))
                    }
                }
                sqlite3_finalize(countStmt)
                
                if verifiedCount == legacyItems.count {
                    print("[DatabaseManager] Migration verified! \(verifiedCount) items migrated.")
                    let migratedPath = jsonURL.path + ".migrated"
                    try? FileManager.default.moveItem(atPath: jsonURL.path, toPath: migratedPath)
                } else {
                    print("[DatabaseManager] Warning: Migrated count \(verifiedCount) does not match JSON count \(legacyItems.count)")
                }
            } catch {
                print("[DatabaseManager] Migration failed: \(error)")
                executeRawSQL("ROLLBACK;")
            }
        }
    }
    
    // MARK: - CRUD Operations
    
    /// Insert a new item into items and items_fts tables.
    func insert(_ item: ClipboardItem) {
        queue.async {
            self.insertItemInternal(item)
        }
    }
    
    private func insertItemInternal(_ item: ClipboardItem) {
        guard let db = db else { return }
        
        let insertSQL = """
        INSERT OR REPLACE INTO items (
            id, type, timestamp, source_app, preview_text,
            is_pinned, is_bookmarked, tags, is_truncated,
            original_size_bytes, language, has_images, has_rich_text,
            text_content, text_filename, image_filename, image_filenames,
            remote_image_map, links_json, ocr_text, rtf_data, html_data, rtfd_data
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, 1, item.id.uuidString)
            bindText(stmt, 2, item.type.rawValue)
            sqlite3_bind_double(stmt, 3, item.timestamp.timeIntervalSinceReferenceDate)
            bindText(stmt, 4, item.sourceApp)
            bindText(stmt, 5, item.previewText)
            sqlite3_bind_int(stmt, 6, item.isPinned ? 1 : 0)
            sqlite3_bind_int(stmt, 7, item.isBookmarked ? 1 : 0)
            bindText(stmt, 8, item.tags.joined(separator: ","))
            sqlite3_bind_int(stmt, 9, item.isTruncated ? 1 : 0)
            if let size = item.originalSizeBytes {
                sqlite3_bind_int64(stmt, 10, Int64(size))
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            bindText(stmt, 11, item.language)
            sqlite3_bind_int(stmt, 12, item.hasImages ? 1 : 0)
            sqlite3_bind_int(stmt, 13, item.hasRichText ? 1 : 0)
            bindText(stmt, 14, item.textContent)
            bindText(stmt, 15, item.textFilename)
            bindText(stmt, 16, item.imageFilename)
            
            // JSON serialized arrays / maps
            if !item.imageFilenames.isEmpty, let d = try? JSONEncoder().encode(item.imageFilenames), let s = String(data: d, encoding: .utf8) {
                bindText(stmt, 17, s)
            } else {
                sqlite3_bind_null(stmt, 17)
            }
            
            if !item.remoteImageMap.isEmpty, let d = try? JSONEncoder().encode(item.remoteImageMap), let s = String(data: d, encoding: .utf8) {
                bindText(stmt, 18, s)
            } else {
                sqlite3_bind_null(stmt, 18)
            }
            
            if !item.links.isEmpty, let d = try? JSONEncoder().encode(item.links), let s = String(data: d, encoding: .utf8) {
                bindText(stmt, 19, s)
            } else {
                sqlite3_bind_null(stmt, 19)
            }
            
            bindText(stmt, 20, item.ocrText)
            bindBlob(stmt, 21, item.rtfData)
            bindBlob(stmt, 22, item.htmlData)
            bindBlob(stmt, 23, item.rtfdData)
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(db))
                print("[DatabaseManager] Failed to insert item: \(msg)")
            }
        }
        sqlite3_finalize(stmt)
        
        // Insert into FTS5
        let ftsSQL = "INSERT INTO items_fts (id, preview_text, ocr_text) VALUES (?, ?, ?);"
        var ftsStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, ftsSQL, -1, &ftsStmt, nil) == SQLITE_OK {
            bindText(ftsStmt, 1, item.id.uuidString)
            bindText(ftsStmt, 2, item.previewText)
            bindText(ftsStmt, 3, item.ocrText ?? "")
            sqlite3_step(ftsStmt)
        }
        sqlite3_finalize(ftsStmt)
    }
    
    /// Delete an item by ID.
    func delete(id: UUID) {
        queue.async {
            guard let db = self.db else { return }
            let idStr = id.uuidString
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM items WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                self.bindText(stmt, 1, idStr)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            
            if sqlite3_prepare_v2(db, "DELETE FROM items_fts WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                self.bindText(stmt, 1, idStr)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    /// Delete multiple items by IDs.
    func deleteMultiple(ids: [UUID]) {
        queue.async {
            guard let db = self.db, !ids.isEmpty else { return }
            self.executeRawSQL("BEGIN IMMEDIATE TRANSACTION;")
            
            var stmt: OpaquePointer?
            var ftsStmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM items WHERE id = ?;", -1, &stmt, nil)
            sqlite3_prepare_v2(db, "DELETE FROM items_fts WHERE id = ?;", -1, &ftsStmt, nil)
            
            for id in ids {
                let idStr = id.uuidString
                if let s = stmt {
                    self.bindText(s, 1, idStr)
                    sqlite3_step(s)
                    sqlite3_reset(s)
                }
                if let f = ftsStmt {
                    self.bindText(f, 1, idStr)
                    sqlite3_step(f)
                    sqlite3_reset(f)
                }
            }
            
            sqlite3_finalize(stmt)
            sqlite3_finalize(ftsStmt)
            self.executeRawSQL("COMMIT;")
        }
    }
    
    /// Update pin state.
    func updatePin(id: UUID, isPinned: Bool) {
        queue.async {
            guard let db = self.db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE items SET is_pinned = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, isPinned ? 1 : 0)
                self.bindText(stmt, 2, id.uuidString)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    /// Update bookmark state.
    func updateBookmark(id: UUID, isBookmarked: Bool) {
        queue.async {
            guard let db = self.db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE items SET is_bookmarked = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, isBookmarked ? 1 : 0)
                self.bindText(stmt, 2, id.uuidString)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    /// Update tags.
    func updateTags(id: UUID, tags: [String]) {
        queue.async {
            guard let db = self.db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE items SET tags = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                self.bindText(stmt, 1, tags.joined(separator: ","))
                self.bindText(stmt, 2, id.uuidString)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    /// Update text content.
    func updateText(id: UUID, textContent: String, previewText: String) {
        queue.async {
            guard let db = self.db else { return }
            let idStr = id.uuidString
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE items SET text_content = ?, preview_text = ?, rtf_data = NULL, html_data = NULL, has_rich_text = 0 WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                self.bindText(stmt, 1, textContent)
                self.bindText(stmt, 2, previewText)
                self.bindText(stmt, 3, idStr)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            
            // Update FTS
            if sqlite3_prepare_v2(db, "UPDATE items_fts SET preview_text = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                self.bindText(stmt, 1, previewText)
                self.bindText(stmt, 2, idStr)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    /// Update OCR text.
    func updateOCRText(id: UUID, ocrText: String) {
        queue.async {
            guard let db = self.db else { return }
            let idStr = id.uuidString
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE items SET ocr_text = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                self.bindText(stmt, 1, ocrText)
                self.bindText(stmt, 2, idStr)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            
            if sqlite3_prepare_v2(db, "UPDATE items_fts SET ocr_text = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                self.bindText(stmt, 1, ocrText)
                self.bindText(stmt, 2, idStr)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    /// Update syntax language override.
    func updateLanguage(id: UUID, language: String?) {
        queue.async {
            guard let db = self.db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE items SET language = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                self.bindText(stmt, 1, language)
                self.bindText(stmt, 2, id.uuidString)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    /// Move an item to the top by giving it a fresh timestamp.
    func moveToTop(id: UUID, newTimestamp: Date) {
        queue.async {
            guard let db = self.db else { return }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "UPDATE items SET timestamp = ? WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, newTimestamp.timeIntervalSinceReferenceDate)
                self.bindText(stmt, 2, id.uuidString)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - Query Operations
    
    /// Fetches all items in history order. By default `includeBlobs` is false,
    /// so the full history fits in minimal RAM (<2MB) without loading multi-megabyte RTF/HTML blobs.
    func fetchAllItems(includeBlobs: Bool = false) -> [ClipboardItem] {
        queue.sync {
            guard let db = db else { return [] }
            
            let sql: String
            if includeBlobs {
                sql = "SELECT id, type, timestamp, source_app, preview_text, is_pinned, is_bookmarked, tags, is_truncated, original_size_bytes, language, has_images, has_rich_text, text_content, text_filename, image_filename, image_filenames, remote_image_map, links_json, ocr_text, rtf_data, html_data, rtfd_data FROM items ORDER BY is_pinned DESC, timestamp DESC;"
            } else {
                sql = "SELECT id, type, timestamp, source_app, preview_text, is_pinned, is_bookmarked, tags, is_truncated, original_size_bytes, language, has_images, has_rich_text, text_content, text_filename, image_filename, image_filenames, remote_image_map, links_json, ocr_text, NULL, NULL, NULL FROM items ORDER BY is_pinned DESC, timestamp DESC;"
            }
            
            var stmt: OpaquePointer?
            var results: [ClipboardItem] = []
            
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let item = parseItem(from: stmt, includeBlobs: includeBlobs) {
                        results.append(item)
                    }
                }
            }
            sqlite3_finalize(stmt)
            return results
        }
    }
    
    /// Fetches the heavy rich-text blobs on demand for a single item.
    func fetchPayload(for id: UUID) -> (rtfData: Data?, htmlData: Data?, rtfdData: Data?, ocrText: String?, textContent: String?)? {
        queue.sync {
            guard let db = db else { return nil }
            var stmt: OpaquePointer?
            var result: (rtfData: Data?, htmlData: Data?, rtfdData: Data?, ocrText: String?, textContent: String?)?
            
            let sql = "SELECT rtf_data, html_data, rtfd_data, ocr_text, text_content FROM items WHERE id = ? LIMIT 1;"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                self.bindText(stmt, 1, id.uuidString)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let rtf = readBlob(stmt, 0)
                    let html = readBlob(stmt, 1)
                    let rtfd = readBlob(stmt, 2)
                    let ocr = readText(stmt, 3)
                    let text = readText(stmt, 4)
                    result = (rtf, html, rtfd, ocr, text)
                }
            }
            sqlite3_finalize(stmt)
            return result
        }
    }
    
    /// Search items using SQLite FTS5 full-text index.
    func searchFTS(query: String) -> [UUID] {
        queue.sync {
            guard let db = db else { return [] }
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return [] }
            
            // Sanitize query for FTS5 (escape quotes and append prefix wildcard)
            let sanitized = trimmed.replacingOccurrences(of: "\"", with: "\"\"")
            let ftsQuery = "\"\(sanitized)\"*"
            
            var stmt: OpaquePointer?
            var ids: [UUID] = []
            let sql = "SELECT id FROM items_fts WHERE items_fts MATCH ? LIMIT 200;"
            
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                self.bindText(stmt, 1, ftsQuery)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let text = readText(stmt, 0), let uuid = UUID(uuidString: text) {
                        ids.append(uuid)
                    }
                }
            }
            sqlite3_finalize(stmt)
            return ids
        }
    }
    
    // MARK: - Row Parsing Helper
    
    private func parseItem(from stmt: OpaquePointer?, includeBlobs: Bool) -> ClipboardItem? {
        guard let stmt = stmt else { return nil }
        guard let idStr = readText(stmt, 0), let id = UUID(uuidString: idStr) else { return nil }
        let typeRaw = readText(stmt, 1) ?? "text"
        let type = ClipboardItemType(rawValue: typeRaw) ?? .text
        let timestampSec = sqlite3_column_double(stmt, 2)
        let timestamp = Date(timeIntervalSinceReferenceDate: timestampSec)
        let sourceApp = readText(stmt, 3)
        // preview_text at 4 (handled via previewText or textContent)
        let isPinned = sqlite3_column_int(stmt, 5) != 0
        let isBookmarked = sqlite3_column_int(stmt, 6) != 0
        let tagsRaw = readText(stmt, 7) ?? ""
        let tags = tagsRaw.isEmpty ? [] : tagsRaw.components(separatedBy: ",")
        let isTruncated = sqlite3_column_int(stmt, 8) != 0
        
        let originalSizeBytes: Int?
        if sqlite3_column_type(stmt, 9) != SQLITE_NULL {
            originalSizeBytes = Int(sqlite3_column_int64(stmt, 9))
        } else {
            originalSizeBytes = nil
        }
        
        let language = readText(stmt, 10)
        let hasRichTextFlag = sqlite3_column_int(stmt, 12) != 0
        let textContent = readText(stmt, 13)
        let textFilename = readText(stmt, 14)
        let imageFilename = readText(stmt, 15)
        
        // Decoded image filenames
        var imageFilenames: [String] = []
        if let s = readText(stmt, 16), let d = s.data(using: .utf8), let arr = try? JSONDecoder().decode([String].self, from: d) {
            imageFilenames = arr
        }
        
        var remoteImageMap: [String: String] = [:]
        if let s = readText(stmt, 17), let d = s.data(using: .utf8), let map = try? JSONDecoder().decode([String: String].self, from: d) {
            remoteImageMap = map
        }
        
        var links: [WebLink] = []
        if let s = readText(stmt, 18), let d = s.data(using: .utf8), let arr = try? JSONDecoder().decode([WebLink].self, from: d) {
            links = arr
        }
        
        let ocrText = readText(stmt, 19)
        let rtfData = includeBlobs ? readBlob(stmt, 20) : nil
        let htmlData = includeBlobs ? readBlob(stmt, 21) : nil
        let rtfdData = includeBlobs ? readBlob(stmt, 22) : nil
        
        return ClipboardItem(
            id: id,
            type: type,
            timestamp: timestamp,
            sourceApp: sourceApp,
            textContent: textContent,
            textFilename: textFilename,
            imageFilename: imageFilename,
            isPinned: isPinned,
            isBookmarked: isBookmarked,
            tags: tags,
            ocrText: ocrText,
            isTruncated: isTruncated,
            originalSizeBytes: originalSizeBytes,
            rtfData: rtfData,
            htmlData: htmlData,
            rtfdData: rtfdData,
            imageFilenames: imageFilenames,
            language: language,
            links: links,
            remoteImageMap: remoteImageMap,
            storedHasRichText: hasRichTextFlag
        )
    }
    
    // MARK: - SQLite Binding & Reading Helpers
    
    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ string: String?) {
        guard let string = string else {
            sqlite3_bind_null(stmt, index)
            return
        }
        sqlite3_bind_text(stmt, index, (string as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }
    
    private func bindBlob(_ stmt: OpaquePointer?, _ index: Int32, _ data: Data?) {
        guard let data = data, !data.isEmpty else {
            sqlite3_bind_null(stmt, index)
            return
        }
        data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, index, rawBuffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
    }
    
    private func readText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: ptr)
    }
    
    private func readBlob(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(stmt, index) else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: bytes, count: count)
    }
}
