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

## ✨ Features

- **📋 Clipboard History** — Automatically saves everything you copy (text & images)
- **⌨️ Global Hotkey** — Instantly access history with `⇧⌘V` (Shift + Command + V)
- **🔍 Powerful Search** — Quickly find any copied item with real-time search
- **🖼️ Image Support** — Copy and paste images seamlessly
- **📱 Menu Bar App** — Lives in your menu bar, never in your way
- **🎨 Native macOS Design** — Beautiful, minimal interface that feels right at home
- **⚡ Lightweight** — Uses minimal system resources
- **🔒 Privacy First** — All data stored locally, nothing leaves your Mac

---

## 📥 Download

<p align="center">
  <a href="https://github.com/samirpatil2000/Buffer/releases/download/v1.0/Buffer.dmg">
    <img src="https://img.shields.io/badge/⬇️_Download_Buffer.dmg-1.0-2ea44f?style=for-the-badge" alt="Download Buffer.dmg">
  </a>
</p>

> **Note:** Buffer is not notarized with Apple Developer ID. On first launch:
> 1. Right-click on **Buffer.app**
> 2. Click **Open**
> 3. Click **Open** in the security dialog

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
