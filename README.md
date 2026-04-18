<p align="center">
  <img src="Assets/Buffer-Logo.png" alt="Buffer Logo" width="128" height="128">
</p>

<h1 align="center">Buffer</h1>

<p align="center">
  <strong>A lightweight, beautiful clipboard manager for macOS</strong>
</p>

<p align="center">
  <a href="https://github.com/samirpatil2000/Buffer/releases/latest">
    <img src="https://img.shields.io/badge/Download-v1.0-blue?style=for-the-badge&logo=apple" alt="Download">
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
- **Bookmarks** — Star important items with Cmd+B for quick reuse  
- **Configurable hotkeys** — Change the global shortcut in Settings with dynamic re-registration  
- **Native macOS Feel** — Clean SwiftUI + AppKit menu-bar app  
- **Open Source** — MIT license, actively maintained  

---


### 📥 Download

<p align="center">
  <a href="https://github.com/samirpatil2000/Buffer/releases/download/buffer-v1.6/Buffer_Release.dmg">
    <img src="https://img.shields.io/badge/⬇️_Download_Buffer.dmg-v1.6-2ea44f?style=for-the-badge" alt="Download Buffer.dmg">
  </a>
</p>

1. Download the `.dmg` from the latest release
2. Drag **Buffer.app** to your **Applications** folder
3. Launch it (lives in menu bar)

---

### 🛣️ Coming Next

- Multi‑paste support for quickly pasting multiple items in sequence  
- Content Editing

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

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⇧⌘V` | Open clipboard history |
| `↑` / `↓` | Navigate items |
| `↵` Enter | Paste selected item |
| `⎋` Esc | Close history window |

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

## 📁 Project Structure

```
Buffer/
├── BufferApp.swift          # App entry point
├── AppDelegate.swift        # App lifecycle & hotkey setup
├── Models/
│   └── ClipboardItem.swift  # Clipboard item data model
├── Services/
│   ├── ClipboardStore.swift    # Persistent storage
│   ├── ClipboardWatcher.swift  # Monitors clipboard changes
│   ├── HotkeyManager.swift     # Global keyboard shortcuts
│   └── PasteController.swift   # Paste functionality
└── Views/
    ├── HistoryWindow.swift      # Main history window
    ├── ClipboardListView.swift  # List of clipboard items
    ├── ClipboardItemRow.swift   # Individual item row
    ├── SearchField.swift        # Search component
    └── StatusBarController.swift # Menu bar controller
```

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
