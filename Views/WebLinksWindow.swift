import Cocoa
import SwiftUI

class WebLinksPanel: NSPanel {
    var onClickOutside: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onClickOutside?()
    }
}

class WebLinkWindowController: NSWindowController {
    private let store: WebLinkStore

    init(store: WebLinkStore) {
        self.store = store

        let panel = WebLinksPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)

        panel.onClickOutside = { [weak self] in
            self?.close()
        }

        setupPanel(panel)
        setupContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPanel(_ panel: NSPanel) {
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false

        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 10
        panel.contentView?.layer?.masksToBounds = true

        panel.center()

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func setupContent() {
        let contentView = WebLinksContentView(store: store, onDismiss: { [weak self] in
            self?.close()
        })
        window?.contentView = NSHostingView(rootView: contentView)
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
    }
}

struct WebLinksContentView: View {
    @ObservedObject var store: WebLinkStore
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    @State private var scrollTrigger = false

    @State private var editingLinkID: UUID?
    @State private var editName = ""
    @State private var editURL = ""

    @State private var showAddRow = false
    @State private var addName = ""
    @State private var addURL = ""

    private var filteredLinks: [WebLink] {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return store.links }
        return store.links.filter {
            $0.name.lowercased().contains(query) || $0.url.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Divider()

            if filteredLinks.isEmpty {
                emptyState
            } else {
                linkList
            }

            Divider()

            actionBar
        }
        .frame(minWidth: 380, minHeight: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: searchText) { newValue in
            let query = newValue.trimmingCharacters(in: .whitespaces).lowercased()
            if query.isEmpty {
                debouncedSearchText = query
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if self.searchText == newValue {
                        self.debouncedSearchText = newValue
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary.opacity(0.7))
                .font(.system(size: 13, weight: .medium))

            TextField("Search web links…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.5))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("\(store.links.count) link\(store.links.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color(NSColor.controlBackgroundColor)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.primary.opacity(0.15)),
                    alignment: .bottom
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if store.links.isEmpty {
                Image(systemName: "globe")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary.opacity(0.3))
                Text("No web links yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Click \"Add Link\" to get started")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            } else {
                Text("No matches")
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var linkList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredLinks.enumerated()), id: \.element.id) { index, link in
                        WebLinkRowView(
                            link: link,
                            isSelected: index == selectedIndex,
                            isEditing: editingLinkID == link.id,
                            editName: $editName,
                            editURL: $editURL,
                            onEdit: { startEditing(link) },
                            onDelete: { store.delete(link) },
                            onSaveEdit: { saveEdit(link) },
                            onCancelEdit: { cancelEditing() }
                        )
                        .id(link.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIndex = index
                            if editingLinkID != nil { cancelEditing() }
                            openLink(link)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .onChange(of: selectedIndex) { newValue in
                if scrollTrigger, let item = filteredLinks[safe: newValue] {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(item.id)
                    }
                    scrollTrigger = false
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if showAddRow {
                HStack(spacing: 6) {
                    TextField("Name", text: $addName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 100)
                    TextField("URL", text: $addURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 160)
                    Button("Save") {
                        saveNew()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                    Button("Cancel") {
                        cancelNew()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
                .padding(.leading, 4)
            } else {
                Button(action: { showAddRow = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add Link")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }

            Spacer()

            if !store.links.isEmpty {
                Text("\(filteredLinks.count) of \(store.links.count)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Color(NSColor.controlBackgroundColor)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.primary.opacity(0.15)),
                    alignment: .top
                )
        )
    }

    private func openLink(_ link: WebLink) {
        guard let url = URL(string: link.resolvedURL) else { return }
        NSWorkspace.shared.open(url)
        store.recordOpen(link)
    }

    private func startEditing(_ link: WebLink) {
        editingLinkID = link.id
        editName = link.name
        editURL = link.url
    }

    private func saveEdit(_ link: WebLink) {
        let trimmedName = editName.trimmingCharacters(in: .whitespaces)
        let trimmedURL = editURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }
        var updated = link
        updated.name = trimmedName
        updated.url = trimmedURL
        store.update(updated)
        editingLinkID = nil
    }

    private func cancelEditing() {
        editingLinkID = nil
        editName = ""
        editURL = ""
    }

    private func saveNew() {
        let trimmedName = addName.trimmingCharacters(in: .whitespaces)
        let trimmedURL = addURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else { return }
        store.add(name: trimmedName, url: trimmedURL)
        addName = ""
        addURL = ""
        showAddRow = false
        selectedIndex = 0
    }

    private func cancelNew() {
        addName = ""
        addURL = ""
        showAddRow = false
    }
}

struct WebLinkRowView: View {
    let link: WebLink
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editName: String
    @Binding var editURL: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundColor(.accentColor.opacity(0.7))
                .frame(width: 20)

            if isEditing {
                TextField("Name", text: $editName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 120)
                TextField("URL", text: $editURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 140)
                Button("Save") { onSaveEdit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                Button("Cancel") { onCancelEdit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text(link.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(link.displayURL)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)

                if link.visitCount > 0 {
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("\(link.visitCount)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }

            Spacer(minLength: 0)

            if isHovered && !isEditing {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary.opacity(0.6))
                    .help("Edit")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary.opacity(0.6))
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
