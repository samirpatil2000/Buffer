<p align="center">
  <img src="Assets/Buffer-Logo.png" alt="Buffer Logo" width="128" height="128">
</p>

<h1 align="center">Buffer</h1>

<p align="center">
  <strong>A lightweight, beautiful clipboard manager for macOS</strong>
</p>

<p align="center">
<a href="https://github.com/samirpatil2000/Buffer/releases/latest">
  <img src="https://img.shields.io/badge/Download-v3.0.0-blue?style=for-the-badge&logo=apple" alt="Download">
</a>
<img src="https://img.shields.io/badge/macOS-13.0+-black?style=for-the-badge&logo=apple" alt="macOS 13+">
<img src="https://img.shields.io/badge/Swift-5.9-orange?style=for-the-badge&logo=swift" alt="Swift 5.9">
<a href="https://deepwiki.com/samirpatil2000/Buffer"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
<br><br>
<img src="https://img.shields.io/github/stars/samirpatil2000/Buffer?style=flat-square&color=orange&label=stars" alt="Stars">
&nbsp;
<img src="https://img.shields.io/github/downloads/samirpatil2000/Buffer/total?style=flat-square&color=blue&label=downloads" alt="Downloads">
</p>

---

### ✨ Why Buffer?

- **Ultra-lightweight** — Only ~2 MB download/install, minimal RAM/CPU usage  
- **100% Private &amp; Local** — Everything stays on your Mac, no cloud, no tracking  
- **Text + Images + OCR** — Copies anything; extracts searchable text from images/screenshots/memes using on-device Vision  
- **Great for developers** — Handles large text snippets, JSON payloads, logs, and other verbose content with ease  
- **Large-content friendly** — Lazy, chunked previews and disk-backed storage for multi‑MB text, with size indicators  
- **Pins & Smart History** — Pin favorites, keep them anchored, and cycle history while prioritizing unpinned items  
- **Multi-select & multi‑paste** — Select multiple items in history with clear on-screen instructions, paste them together, or bulk-delete with inline confirmation 
- **Bookmarks** — Star important items with Cmd+B for quick reuse  
- **Tags & Filtering** — Categorize history items with custom, color-coded tags. Quick tag items with `Cmd+T` and filter using `#` autocomplete in the search bar  
- **Configurable hotkeys** — Change the global shortcut in Settings with dynamic re-registration  
- **Native macOS Feel** — Clean SwiftUI + AppKit menu-bar app  
- **Interactive Image Inspection Canvas** — Pinch-to-zoom, pan, double-click fit/reset, and `⌘+`/`⌘-` zoom controls for inspecting screenshots and image clips  
- **Shortcuts Cheat Sheet & Content Zoom** — On-screen interactive shortcuts popup (`⌘/`), footer shortcuts bar, and content text zoom (`⌘+`/`⌘-`/`⌘0`)  
- **Noise Controls & History Tiers** — Configurable history capacity tiers and automatic noise filtering to suppress rapid duplicate clips and short fragments  
- **Seamless Updates** — Built-in secure auto-updater with in-app notification chip, release highlights popover, and post-update HUD  
- **Inline Text Editing** — Edit any text or code snippet directly within the clipboard history window with safe cancel (`Esc`) and macOS pasteboard sync  
- **Open Source** — MIT license, actively maintained  

---


### 📥 Download

<p align="center">
  <a href="https://github.com/samirpatil2000/Buffer/releases/download/buffer-v3.0.0/Buffer_Silicon.dmg">
    <img src="https://img.shields.io/badge/⬇️_Apple_Silicon_DMG-v3.0.0-2ea44f?style=for-the-badge" alt="Download Buffer Silicon DMG">
  </a>
  &nbsp;
  <a href="https://github.com/samirpatil2000/Buffer/releases/download/buffer-v3.0.0/Buffer_Intel.dmg">
    <img src="https://img.shields.io/badge/⬇️_Intel_DMG-v3.0.0-8a3ffc?style=for-the-badge" alt="Download Buffer Intel DMG">
  </a>
</p>

1. Download the `.dmg` from the latest release
2. Drag **Buffer.app** to your **Applications** folder
3. Launch it (lives in menu bar)

---

## 🍺 Install with Homebrew

Buffer is a GUI macOS app, so Homebrew support should be added as a `cask`, not a formula.

### For users

If you publish a tap, users can install Buffer with:

```bash
brew install --cask samirpatil2000/buffer/buffer
```

### For maintainers

The easiest setup is:

1. Create a tap repo named `homebrew-buffer`
2. Keep the cask file at `Casks/buffer.rb`
3. Continue shipping notarized `.dmg` assets from GitHub Releases

This repo includes a helper script to generate the cask from your release DMGs:

```bash
./scripts/generate_homebrew_cask.sh 1.6 Buffer_Silicon.dmg Buffer_Intel.dmg
```

That writes `Casks/buffer.rb` using:

- `https://github.com/samirpatil2000/Buffer/releases/download/buffer-v#{version}/Buffer_Silicon.dmg`
- `https://github.com/samirpatil2000/Buffer/releases/download/buffer-v#{version}/Buffer_Intel.dmg`

Typical release flow:

```bash
# 1. Build and notarize both DMGs
./build_dmg.sh

# 2. Generate the Homebrew cask with real SHA256 values
./scripts/generate_homebrew_cask.sh 1.6 Buffer_Silicon.dmg Buffer_Intel.dmg

# 3. Commit Casks/buffer.rb to your tap repo
# 4. Push the release assets and the cask update
```

If you want to use this repo itself as the tap, users can still install from the full tap name or URL, but a dedicated `homebrew-buffer` repository is the standard Homebrew layout.

---

## 🚀 Getting Started

1. **Download** the `.dmg` file from above
2. **Drag** Buffer to your Applications folder
3. **Launch** Buffer — it will appear in your menu bar
4. **Copy** anything — Buffer automatically saves it
5. Press **⇧⌘V** to access your clipboard history anytime!

---

## 🖥️ Screenshots

<p align="center">
  <img width="919" height="864" alt="image" src="https://github.com/user-attachments/assets/ebd0d454-8362-45e4-af22-27f054ba43c6" />
</p>


<p align="center">
  <em>Beautiful split-pane interface with search and preview</em>
</p>


#### Edit Text 

<img width="800" height="539" alt="buffer-18-jun–editing" src="https://github.com/user-attachments/assets/12ec7289-0a43-453b-a0cc-ae13918fcd0b" />


#### Multi select & paste

<img width="800" height="525" alt="buffer-26-apr-v2-ezgif com-video-to-gif-converter" src="https://github.com/user-attachments/assets/5dd61f35-9b16-413d-aec9-8e89fff4f7f8" />


#### Tags 

<img width="709" height="486" alt="image" src="https://github.com/user-attachments/assets/6b1ac775-b75f-43db-8438-4170336c25cc" />


#### Keyboard Shortcuts Cheat Sheet & Image Canvas

<p align="center">
  <img width="800" alt="Keyboard Shortcuts Cheat Sheet & Image Canvas" src="https://github.com/user-attachments/assets/44944452-b449-42ef-b8a9-439ad72cd6f7" />
</p>

<p align="center">
  <em>Interactive shortcuts cheat sheet popover (⌘/) and interactive image inspection canvas</em>
</p>


#### History Size Tiers

<p align="center">
  <img width="520" alt="History Size Tiers" src="Assets/history-size-tiers.png" />
</p>

<p align="center">
  <em>Configurable clipboard history retention tiers: Essential (200), Deep (1,000), or Unlimited</em>
</p>


#### Inline Text Editing

Click the **Pencil icon** in the preview/detail pane to open an inline text editor and modify any text item directly. While editing, global keyboard shortcuts are **temporarily bypassed** so you can type normally. Click **Save** to persist changes and sync them to the macOS pasteboard, or press **Escape** to cancel and cleanly discard unsaved changes.

---

## ⌨️ Keyboard Shortcuts

Press `⌘/` anytime or click the **Shortcuts** button in the footer bar to open the interactive on-screen cheat sheet.

### Navigation & Selection
| Shortcut | Action |
|----------|--------|
| `⇧⌘V` | Open clipboard history |
| `↑` / `↓` | Navigate history items |
| `⇧↑` / `⇧↓` | Multi-select items (expands / shrinks range) |
| `⌘A` | Select all items |
| `↵` Enter | Paste selected item to frontmost app |
| `⎋` Esc | Dismiss Buffer window / cancel edits |

### Item Actions
| Shortcut | Action |
|----------|--------|
| `⌘C` | Copy selected item to clipboard and dismiss |
| `⌘P` | Pin / unpin selected item |
| `⌘B` | Bookmark / unbookmark selected item |
| `⌘E` | Edit snippet inline |
| `⌘T` | Add tag to selected item |
| `⌘S` | Save image to disk (for image items) |
| `⌘⌫` | Delete selected item (or multi-selected items) |

### Zoom & Canvas
| Shortcut | Action |
|----------|--------|
| `⌘+` | Zoom in (larger rows & preview text) |
| `⌘-` | Zoom out |
| `⌘0` | Reset zoom to 100% |
| `2× Click` | Toggle image actual size / fit |
| `Pinch` / `Pan` | Zoom & navigate image canvas on trackpad |

### Application
| Shortcut | Action |
|----------|--------|
| `⌘,` | Open Settings |
| `⌘/` | Toggle keyboard shortcuts cheat sheet |

---

## 🛠️ Building from Source

```bash
# Clone the repository
git clone https://github.com/samirpatil2000/Buffer.git
cd Buffer

# Open in Xcode
open Buffer.xcodeproj

# Build and run
# Press ⌘R in Xcode
```

### Requirements
- macOS 13.0 or later
- Xcode 15.0 or later
- Swift 5.9

---

## Star History

<a href="https://star-history.dera.page/#samirpatil2000/buffer&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=samirpatil2000/buffer&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=samirpatil2000/buffer&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=samirpatil2000/buffer&type=date&legend=top-left" />
 </picture>
</a>

---

## 🤝 Contributing

Contributions are welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests

---

## 📄 License

MIT License — feel free to use this project however you like.

---

<p align="center">
  Made with ❤️ for macOS
</p>
