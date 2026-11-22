import Foundation
import AppKit

/// Errors that can occur during history export or import operations.
enum HistoryBackupError: LocalizedError, Equatable {
    case noExportableItems
    case invalidFileFormat
    case fileReadFailed(String)
    case storeUnavailable

    var errorDescription: String? {
        switch self {
        case .noExportableItems:
            return "No text history items available to export."
        case .invalidFileFormat:
            return "Unrecognized or corrupted history file format. Please select a valid Buffer JSON export."
        case .fileReadFailed(let reason):
            return "Failed to read backup file: \(reason)"
        case .storeUnavailable:
            return "Clipboard store is unavailable."
        }
    }
}

/// Result summary of an import operation.
struct HistoryImportResult: Equatable {
    let importedCount: Int
    let skippedDuplicateCount: Int

    var summaryMessage: String {
        if importedCount == 0 && skippedDuplicateCount == 0 {
            return "No valid text items found in the selected file."
        }
        if skippedDuplicateCount > 0 {
            let itemWord = importedCount == 1 ? "item" : "items"
            let dupWord = skippedDuplicateCount == 1 ? "item" : "items"
            return "Imported \(importedCount) new \(itemWord) (\(skippedDuplicateCount) duplicate \(dupWord) skipped)."
        }
        let itemWord = importedCount == 1 ? "item" : "items"
        return "Successfully imported \(importedCount) text \(itemWord)."
    }
}

/// Manages exporting and importing text clipboard history.
final class HistoryBackupService {
    static let shared = HistoryBackupService()

    private let defaultExportFilename = "buffer-text-history.json"

    private init() {}

    // MARK: - Core Pure Logic

    /// Filters items that are pure inline text (no images and not file-backed).
    func filterExportableItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter(\.isExportableText)
    }

    /// Decodes and validates items from raw JSON data, supporting both envelope and flat-array formats.
    func parseAndSanitizeItems(from data: Data) throws -> [ClipboardItem] {
        let decoder = JSONDecoder.iso8601Decoder

        let candidates: [ClipboardItem]
        if let payload = try? decoder.decode(HistoryExportPayload.self, from: data) {
            candidates = payload.items
        } else if let rawArray = try? decoder.decode([ClipboardItem].self, from: data) {
            candidates = rawArray
        } else {
            throw HistoryBackupError.invalidFileFormat
        }

        // Strictly keep valid inline text items only
        return candidates.filter(\.isExportableText)
    }

    /// Prepares exportable JSON data from the given clipboard items.
    func encodePayload(for items: [ClipboardItem]) throws -> Data {
        let exportable = filterExportableItems(from: items)
        guard !exportable.isEmpty else {
            throw HistoryBackupError.noExportableItems
        }

        let payload = HistoryExportPayload(items: exportable)
        let encoder = JSONEncoder.prettyISO8601Encoder
        return try encoder.encode(payload)
    }

    /// Executes smart merge against existing text contents: skips duplicates and sanitizes new items.
    func smartMerge(
        candidates: [ClipboardItem],
        existingTexts: Set<String>
    ) -> (itemsToInsert: [ClipboardItem], skippedCount: Int) {
        var seenTexts = existingTexts
        var itemsToInsert: [ClipboardItem] = []
        var skippedCount = 0

        for candidate in candidates {
            guard let text = candidate.textContent else { continue }
            if seenTexts.contains(text) {
                skippedCount += 1
            } else {
                seenTexts.insert(text)
                itemsToInsert.append(sanitizeImportedItem(candidate))
            }
        }

        return (itemsToInsert, skippedCount)
    }

    /// Sanitizes an imported item by assigning a fresh UUID and ensuring it is strictly inline text.
    func sanitizeImportedItem(_ item: ClipboardItem) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .text,
            timestamp: item.timestamp,
            sourceApp: item.sourceApp,
            textContent: item.textContent,
            textFilename: nil,
            imageFilename: nil,
            isPinned: item.isPinned,
            isBookmarked: item.isBookmarked,
            tags: item.tags,
            ocrText: nil,
            isTruncated: item.isTruncated,
            originalSizeBytes: item.originalSizeBytes,
            rtfData: item.rtfData,
            htmlData: item.htmlData,
            rtfdData: nil,
            imageFilenames: [],
            language: item.language,
            links: item.links,
            remoteImageMap: [:],
            storedHasRichText: item.storedHasRichText
        )
    }

    // MARK: - Panel Orchestration

    /// Exports inline text items to a user-selected JSON file.
    func exportTextHistory(
        items: [ClipboardItem],
        presentingWindow: NSWindow?,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        let exportable = filterExportableItems(from: items)
        guard !exportable.isEmpty else {
            completion(.failure(HistoryBackupError.noExportableItems))
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Export Text History"
        savePanel.prompt = "Export"
        savePanel.nameFieldStringValue = defaultExportFilename
        if #available(macOS 11.0, *) {
            savePanel.allowedContentTypes = [.json]
        } else {
            savePanel.allowedFileTypes = ["json"]
        }
        savePanel.canCreateDirectories = true

        let onCompletion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let targetURL = savePanel.url, let self = self else { return }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try self.encodePayload(for: exportable)
                    try data.write(to: targetURL, options: .atomic)
                    DispatchQueue.main.async {
                        completion(.success(exportable.count))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        }

        if let window = presentingWindow {
            savePanel.beginSheetModal(for: window, completionHandler: onCompletion)
        } else {
            savePanel.begin(completionHandler: onCompletion)
        }
    }

    /// Imports text history from a user-selected JSON file with smart merge.
    func importTextHistory(
        into store: ClipboardStore,
        presentingWindow: NSWindow?,
        completion: @escaping (Result<HistoryImportResult, Error>) -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Text History"
        openPanel.prompt = "Import"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        if #available(macOS 11.0, *) {
            openPanel.allowedContentTypes = [.json]
        } else {
            openPanel.allowedFileTypes = ["json"]
        }

        let onCompletion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let fileURL = openPanel.url, let self = self else { return }

            let existingTexts = Set(store.items.compactMap(\.textContent))

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                do {
                    let data = try Data(contentsOf: fileURL)
                    let candidates = try self.parseAndSanitizeItems(from: data)
                    let (itemsToInsert, skippedCount) = self.smartMerge(candidates: candidates, existingTexts: existingTexts)

                    guard !itemsToInsert.isEmpty else {
                        DispatchQueue.main.async {
                            completion(.success(HistoryImportResult(
                                importedCount: 0,
                                skippedDuplicateCount: skippedCount
                            )))
                        }
                        return
                    }

                    DatabaseManager.shared.insertBatch(itemsToInsert) {
                        store.mergeImportedItems(itemsToInsert)
                        completion(.success(HistoryImportResult(
                            importedCount: itemsToInsert.count,
                            skippedDuplicateCount: skippedCount
                        )))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        }

        if let window = presentingWindow {
            openPanel.beginSheetModal(for: window, completionHandler: onCompletion)
        } else {
            openPanel.begin(completionHandler: onCompletion)
        }
    }
}

// MARK: - JSON Encoding / Decoding Helpers

private extension JSONEncoder {
    static var prettyISO8601Encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601Decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
