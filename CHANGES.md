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
- The button appears only for content that can actually be formatted. JSON key
  order is preserved.

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
