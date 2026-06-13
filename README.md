<p align="center">
  <img src="Assets/Buffer-Logo.png" alt="Buffer Logo" width="128" height="128">
</p>

<h1 align="center">Buffer</h1>

<p align="center">
  <strong>A lightweight, beautiful clipboard manager for macOS</strong>
</p>

<p align="center">
  <a href="https://github.com/samirpatil2000/Buffer/releases/latest">
    <img src="https://img.shields.io/badge/Download-v2.1.0-blue?style=for-the-badge&logo=apple" alt="Download">
  </a>
  <img src="https://img.shields.io/badge/macOS-13.0+-black?style=for-the-badge&logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=for-the-badge&logo=swift" alt="Swift 5.9">
  <a href="https://deepwiki.com/samirpatil2000/Buffer"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
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
- **Seamless Updates** — Built-in secure auto-updater with code signature verification and a native post-update HUD with a "What's New" link  
- **Inline Text Editing** — Edit any text or code snippet directly within the clipboard history window with auto-save and macOS pasteboard sync
- **Open Source** — MIT license, actively maintained  

---


### 📥 Download

<p align="center">
  <a href="https://github.com/samirpatil2000/Buffer/releases/download/buffer-v2.1.0/Buffer_Silicon.dmg">
    <img src="https://img.shields.io/badge/⬇️_Apple_Silicon_DMG-v2.1.0-2ea44f?style=for-the-badge" alt="Download Buffer Silicon DMG">
  </a>
  &nbsp;
  <a href="https://github.com/samirpatil2000/Buffer/releases/download/buffer-v2.1.0/Buffer_Intel.dmg">
    <img src="https://img.shields.io/badge/⬇️_Intel_DMG-v2.1.0-8a3ffc?style=for-the-badge" alt="Download Buffer Intel DMG">
  </a>
</p>

1. Download the `.dmg` from the latest release
2. Drag **Buffer.app** to your **Applications** folder
3. Launch it (lives in menu bar)

---

### 🛣️ Coming Next

- Multi‑paste support for quickly pasting multiple items in sequence

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

#### Multi select & paste

<img width="800" height="525" alt="buffer-26-apr-v2-ezgif com-video-to-gif-converter" src="https://github.com/user-attachments/assets/5dd61f35-9b16-413d-aec9-8e89fff4f7f8" />


#### Tags 

<img width="709" height="486" alt="image" src="https://github.com/user-attachments/assets/6b1ac775-b75f-43db-8438-4170336c25cc" />


#### Inline Text Editing

Click the **Pencil icon** in the preview/detail pane to open an inline text editor and modify any text item directly. While editing, global keyboard shortcuts are **temporarily bypassed** so you can type normally. Press **Escape**, click the pencil icon again, or select a different item to **auto-save** your changes and sync them to the system pasteboard.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⇧⌘V` | Open clipboard history |
| `↑` / `↓` | Navigate items |
| `⇧↑` / `⇧↓` | Expand selection (Multi-select) |
| `↵` Enter | Paste selected item |
| `⌘C` | Copy selected item text to clipboard |
| `⌘P` | Pin / unpin selected item |
| `⌘B` | Bookmark / unbookmark selected item |
| `⌘T` | Add tag to selected item |
| `⌘S` | Save image to disk (for image items) |
| `⌘⌫` | Delete selected item |
| `⎋` Esc | Close history window |

### 📝 Inline Text Editing

Text items can be edited directly within Buffer by clicking the **Pencil icon** in the preview/detail pane, which opens an inline text editor. While editing:

- **Global keyboard shortcuts are temporarily bypassed** so you can type normally without triggering shortcuts.
- Press **Escape**, click the **pencil icon** again, or **select a different item** in the list to **auto-save** your changes and sync them to the macOS pasteboard.

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

<a href="https://www.star-history.com/?repos=samirpatil2000%2Fbuffer&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=samirpatil2000/buffer&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=samirpatil2000/buffer&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=samirpatil2000/buffer&type=date&legend=top-left" />
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
