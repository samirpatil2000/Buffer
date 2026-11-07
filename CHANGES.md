# Buffer - Custom Enhancements

A set of enhancements to Buffer (macOS clipboard manager), built on top of
upstream v3.0.0+. This document describes everything in the
`feature/buffer-local-enhancements` branch.

- **Build:** `3.0.5 - Custom`
- **Scope:** 14 files changed (+2009 / -198), 3 new source files, 40 passing tests
- **Compatibility:** every new field on the data model is additive and
  backward-compatible, so existing `history.json` files keep loading.

---

## 1. Configurable history size

- New **Custom** tier alongside Essential (200) / Deep (1000) / Unlimited, with
  a numeric field to set any cap (for example 20000).
- **Unlimited** performs no eviction at all.
- The reduce-and-delete confirmation dialog fires correctly for every tier
  combination (including custom-to-custom, custom-to-preset, and anything to
  unlimited).

## 2. Automatic, searchable OCR

- Images are OCR'd **automatically on capture** using Apple's on-device Vision
  framework - no button press. Covers both the pasteboard-image and
  Finder-image-file capture paths.
- Extracted text is **searchable**: an image is findable by the words inside it.
- OCR runs off the main thread so the clipboard poll never blocks. The
  "no text found" case is stored as an empty sentinel that never matches a
  search query.
- A Settings toggle (default on) controls automatic OCR; a manual re-run action
  remains available as a fallback.

## 3. Rich text and combined text + image items

- **Formatting is preserved** (RTF / HTML) so pasting into a rich target such as
  Pages, Mail, or Word keeps bold, color, and fonts, while plain-text targets
  still receive clean text.
- A single history item can hold **both a text body and one or more images**
  (for example a mixed selection copied from Pages or a web page).
- The preview renders a combined item from its **stored rich payload**, so
  images appear **inline in their original position** with formatting, rather
  than stacked below the text.
- Multi-image file handling (deletion and size accounting) is correct, and
  combined items are labelled "Text + Image" in the list.
- A Settings toggle (default on) controls rich-content preservation.

## 4. Code syntax highlighting

- Uses **HighlighterSwift** (highlight.js, ~190 languages) - the first Swift
  Package dependency added to the project.
- **Automatic language detection** with a dependency-free heuristic layer in
  front for the cases highlight.js tends to misread on short fragments (JSON is
  validated, shell shebang, SQL, unified diff, XML/HTML, YAML). Ordinary prose
  is deliberately left unhighlighted.
- **Manual language override** per item (Auto / Plain Text / any supported
  language), persisted with the item.
- Light and dark themes follow the system appearance; font size tracks the
  preview zoom level.
- Highlighting runs off the main thread and is size-capped (100 KB) so large
  pastes stay responsive; it falls back to plain text on any failure. The engine
  sits behind a `SyntaxHighlighting` protocol so it can be swapped later.

## 5. In-place JSON / XML formatter

- A **Format** button in the preview pretty-prints JSON and XML/HTML **in place**
  (dependency-free, using Foundation).
- The button is a **toggle**: click once to pretty-print (expand), click again
  to minify (compact) the content back to a single line. The icon and tooltip
  switch to show which action the next click performs.
- The button appears only for content that can actually be formatted. JSON key
  order is preserved in both directions, and the pretty / compact round trip is
  lossless.

## 6. Browser image capture

- **Inline base64 images** embedded in copied HTML are captured automatically
  (local, no network).
- **Remote images** referenced by http(s) URLs in copied HTML can be downloaded,
  but this is **opt-in and off by default**, with a clear privacy warning (it
  makes network requests on copy and can trigger tracking pixels). Downloads are
  bounded: at most 8 images, a 5 second timeout each, 5 MB per image, cookies
  disabled.

## 7. Search highlighting in the preview

- The active search term is **highlighted in yellow** in the preview, across
  plain text, OCR text, rich/combined content, and syntax-highlighted code.
  It updates live as you type and is case-insensitive.

## 8. Hyperlink capture

- Copying hyperlinked content captures **every `<a href>`** from the source's
  HTML (anchor text + URL), in document order, plus the single-URL pasteboard
  flavour when the whole copy is one link. Only http(s) and mailto links are
  kept; fragment, relative, and javascript anchors are skipped, and the count
  is capped per item.
- Captured links are **searchable** by both the visible anchor text and the URL.
- A **Links** section in the preview lists each link, clickable (opens in the
  browser) with a copy-URL action.
- Within the text body, hyperlinks render **inline as classic blue underlined
  clickable links**, matching how they appeared in the source, while the
  surrounding text keeps the standard preview color and the same monospaced
  font and size as plain-text entries (so it respects the zoom level).
- **Bare URLs in plain text** (copied without any HTML markup) are detected,
  stored, searchable, and rendered clickable inline too.
- URLs in the Links section are left-aligned, single-line (middle-truncated),
  and HTML entities in captured URLs are decoded so links are valid.
- Items captured **before link detection existed** are handled too: any URL
  found in their text body is detected live at display time, so those older
  entries show up in the **Links** section, match the **Link** type filter, are
  searchable by URL, and render clickable inline, with no change to stored data.

## 9. Inline images in web-article previews

- When a copied web article references remote images, Buffer (with the opt-in
  remote-image download enabled) records a map of each remote image URL to the
  local file it was downloaded into.
- The preview renders those images **inline at their original position** by
  splicing the real local image into the parsed text. Preview images are scaled
  to fit the pane (up to 480px wide); this is display-only - **paste/copy still
  carries the original full-size content** via the source HTML/RTF, so a rich
  target receives images at native resolution.
- Images that could not be downloaded are omitted from the preview rather than
  shown as broken icons.

## 10. Filter by type

Filter the history down to a single content category. Works alongside search and
tag filters.

**Categories (plus All):**

- **Text** - any item with a text body (plain text, and combined text+image items)
- **Image** - any item carrying an image (pure images, and combined text+image items)
- **Link** - items that captured one or more hyperlinks (or bare URLs in plain text)
- **Code** - items whose content was detected as source code (JSON, shell, SQL, Swift, etc.)

**Two ways to filter:**

1. **Chips** - a row under the search bar (`All / Text / Image / Link / Code`).
   Click one to filter; click All to clear.
2. **Search tokens** - type `type:` and a category in the search box:
   `type:image`, `type:link`, `type:code`, `type:text`. A token overrides the
   chips (which dim and reflect it) and combines with free text, so
   `type:link invoice` shows link items that also match "invoice".

**Notes:**

- An item can match more than one category - a combined text+image item shows
  under both Text and Image.
- The filter resets to All each time the window opens.
- It stacks with text search and `#tag` filters.
- Code and Link classification only applies to items captured after those
  features existed; Text and Image are accurate for all history.

## 11. Aligned preview for tab-separated tables

- When a copied item is a **tab-separated table** (as produced by copying a
  table from Notion, a spreadsheet, or a web page), the preview renders it as an
  **aligned grid** instead of ragged monospaced text, so columns line up.
- The first row is treated as a header (bold, with a divider beneath it).
- Detection is conservative: it needs multiple rows, at least two columns, and a
  consistent column count across most rows, so ordinary prose or code with a
  stray tab is never mistaken for a table. Anything that does not qualify falls
  back to the normal plain-text preview.
- Tables copied from **Teams** (and similar sources) often split a single row
  across several lines when a cell contains an internal line break. When the
  header establishes a clear column count and enough clean rows confirm it, the
  detector stitches those split lines back into the correct rows.

## Developer-facing

- **Debug builds use a separate data directory** (`Buffer-dev/` instead of
  `Buffer/`) so development and testing never read or overwrite real clipboard
  data. Release builds are unaffected.

---

## Known limitations

- **Combined text + image capture** works from native rich-text apps (Pages,
  Mail, TextEdit, Notes) and from browser copies whose images are inline base64
  or, with the opt-in setting enabled, remote URLs. Images that exist only as
  remote URLs are not captured unless remote download is turned on.
- **Remote image download** is privacy-sensitive and is off by default by
  design.
- Builds here are ad-hoc signed, not notarized. On a different Mac the first
  launch may require right-click -> Open (or stripping the quarantine
  attribute). This does not affect normal local use.
