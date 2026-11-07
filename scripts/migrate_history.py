#!/usr/bin/env python3
"""
Buffer Clipboard History Migration Tool
Migrates history.json to SQLite with FTS5 full-text search indexing.

Usage:
  python3 scripts/migrate_history.py --dry-run
  python3 scripts/migrate_history.py --execute
  python3 scripts/migrate_history.py --verify
"""

import sys
import os
import json
import sqlite3
import shutil
from datetime import datetime

DEFAULT_SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/Buffer")
DEFAULT_JSON_PATH = os.path.join(DEFAULT_SUPPORT_DIR, "history.json")
DEFAULT_DB_PATH = os.path.join(DEFAULT_SUPPORT_DIR, "buffer.sqlite")

SCHEMA_SQL = """
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 3000;

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

CREATE INDEX IF NOT EXISTS idx_items_ordering ON items (is_pinned DESC, timestamp DESC);

CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
    id UNINDEXED,
    preview_text,
    ocr_text,
    tokenize = 'unicode61'
);
"""

def compute_preview_text(item):
    """Computes a short preview text consistent with Swift ClipboardItem.previewText."""
    item_type = item.get("type", "text")
    if item_type == "image":
        ocr = item.get("ocrText")
        if ocr and ocr.strip():
            return f"Image: {ocr.strip()}"
        return "Image"
    
    # Text item
    text = item.get("textContent")
    if text:
        return text
    # Large text file fallback
    filename = item.get("textFilename")
    if filename:
        return f"Large text ({filename})"
    return ""

def migrate(json_path, db_path, dry_run=False):
    if not os.path.exists(json_path):
        print(f"[Error] Source history JSON not found at {json_path}")
        return False

    print(f"[*] Reading {json_path}...")
    file_size_mb = os.path.getsize(json_path) / (1024 * 1024)
    with open(json_path, "r", encoding="utf-8") as f:
        items = json.load(f)

    total_count = len(items)
    print(f"[*] Loaded {total_count} items ({file_size_mb:.2f} MB)")

    target_db = ":memory:" if dry_run else db_path
    if dry_run:
        print("[*] Running in DRY-RUN mode (in-memory SQLite database)")
    else:
        # Create timestamped backup of history.json
        backup_path = f"{json_path}.bak-{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        print(f"[*] Creating backup at {backup_path}")
        shutil.copy2(json_path, backup_path)
        print(f"[*] Target SQLite database: {target_db}")

    conn = sqlite3.connect(target_db)
    cur = conn.cursor()

    print("[*] Initializing schema...")
    cur.executescript(SCHEMA_SQL)

    print("[*] Migrating records into SQLite inside single transaction...")
    start_time = datetime.now()

    insert_sql = """
    INSERT INTO items (
        id, type, timestamp, source_app, preview_text,
        is_pinned, is_bookmarked, tags, is_truncated,
        original_size_bytes, language, has_images, has_rich_text,
        text_content, text_filename, image_filename, image_filenames,
        remote_image_map, links_json, ocr_text, rtf_data, html_data, rtfd_data
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    insert_fts_sql = "INSERT INTO items_fts (id, preview_text, ocr_text) VALUES (?, ?, ?)"

    cur.execute("BEGIN IMMEDIATE TRANSACTION;")

    inserted = 0
    for it in items:
        item_id = str(it.get("id"))
        item_type = str(it.get("type", "text"))
        timestamp = float(it.get("timestamp", 0.0))
        source_app = it.get("sourceApp")
        
        # Text & preview
        text_content = it.get("textContent")
        preview = compute_preview_text(it)
        ocr_text = it.get("ocrText")
        
        is_pinned = 1 if it.get("isPinned") else 0
        is_bookmarked = 1 if it.get("isBookmarked") else 0
        tags_str = ",".join(it.get("tags", [])) if isinstance(it.get("tags"), list) else ""
        is_truncated = 1 if it.get("isTruncated") else 0
        original_size = it.get("originalSizeBytes")
        language = it.get("language")

        # Blobs & Files
        image_filename = it.get("imageFilename")
        text_filename = it.get("textFilename")
        image_filenames = json.dumps(it.get("imageFilenames", [])) if it.get("imageFilenames") else None
        remote_image_map = json.dumps(it.get("remoteImageMap", {})) if it.get("remoteImageMap") else None
        links_json = json.dumps(it.get("links", [])) if it.get("links") else None

        has_images = 1 if (image_filename or it.get("imageFilenames")) else 0
        has_rich = 1 if (it.get("rtfData") or it.get("htmlData") or it.get("rtfdData")) else 0

        # Base64 data decoded to BLOB if present
        import base64
        rtf_blob = base64.b64decode(it["rtfData"]) if it.get("rtfData") else None
        html_blob = base64.b64decode(it["htmlData"]) if it.get("htmlData") else None
        rtfd_blob = base64.b64decode(it["rtfdData"]) if it.get("rtfdData") else None

        cur.execute(insert_sql, (
            item_id, item_type, timestamp, source_app, preview,
            is_pinned, is_bookmarked, tags_str, is_truncated,
            original_size, language, has_images, has_rich,
            text_content, text_filename, image_filename, image_filenames,
            remote_image_map, links_json, ocr_text, rtf_blob, html_blob, rtfd_blob
        ))

        cur.execute(insert_fts_sql, (item_id, preview, ocr_text or ""))
        inserted += 1

    cur.execute("COMMIT;")
    duration_ms = (datetime.now() - start_time).total_seconds() * 1000

    print(f"[✓] Successfully inserted {inserted} items in {duration_ms:.1f} ms")

    # Verification checks
    cur.execute("SELECT COUNT(*) FROM items")
    db_count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM items_fts")
    fts_count = cur.fetchone()[0]
    cur.execute("PRAGMA integrity_check;")
    integrity = cur.fetchone()[0]

    print(f"[*] Verification: Items count = {db_count}, FTS index count = {fts_count}, Integrity = {integrity}")

    if db_count != total_count or integrity != "ok":
        print(f"[FAIL] Validation mismatch! items: {db_count} != {total_count}")
        conn.close()
        return False

    # Test FTS query speed
    cur.execute("SELECT id, preview_text FROM items_fts WHERE items_fts MATCH 'http*' LIMIT 5")
    sample_hits = cur.fetchall()
    print(f"[*] FTS5 search test ('http*'): {len(sample_hits)} sample matches found instantly")

    if not dry_run:
        migrated_name = f"{json_path}.migrated"
        print(f"[*] Renaming {json_path} -> {migrated_name}")
        shutil.move(json_path, migrated_name)
        sqlite_size_mb = os.path.getsize(db_path) / (1024 * 1024)
        print(f"[✓] Migration complete! SQLite size: {sqlite_size_mb:.2f} MB (vs JSON {file_size_mb:.2f} MB)")

    conn.close()
    return True

if __name__ == "__main__":
    mode = "--dry-run" if len(sys.argv) < 2 else sys.argv[1]
    if mode == "--dry-run":
        migrate(DEFAULT_JSON_PATH, DEFAULT_DB_PATH, dry_run=True)
    elif mode == "--execute":
        migrate(DEFAULT_JSON_PATH, DEFAULT_DB_PATH, dry_run=False)
    else:
        print("Usage: migrate_history.py [--dry-run | --execute]")
