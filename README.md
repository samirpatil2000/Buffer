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
- **100% Private & Local** — Everything stays on your Mac, no cloud, no tracking
- **Text + Images + OCR** — Copies anything; extracts searchable text from images/screenshots/memes using on-device Vision
- **Great for developers** — Handles large text snippets, JSON payloads, logs, and other verbose content with ease
- **Instant Access** — Global hotkey ⇧⌘V opens history in a flash
- **Native macOS Feel** — Clean SwiftUI + AppKit menu-bar app
- **Bookmarks** — Star important items with Cmd+B for quick reuse
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
4. **Note (not yet notarized)**: Right-click → Open → confirm in security dialog

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
