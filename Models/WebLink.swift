import Foundation

struct WebLink: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var url: String
    var sortOrder: Int
    var createdAt: Date
    var lastOpenedAt: Date?
    var visitCount: Int

    init(id: UUID = UUID(), name: String, url: String, sortOrder: Int = 0, createdAt: Date = Date(), lastOpenedAt: Date? = nil, visitCount: Int = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.visitCount = visitCount
    }

    var displayURL: String {
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return String(url.dropFirst(url.hasPrefix("https://") ? 8 : 7))
        }
        return url
    }

    var isValidURL: Bool {
        guard !url.isEmpty else { return false }
        let lower = url.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return true }
        return url.contains(".")
    }

    var resolvedURL: String {
        if url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://") {
            return url
        }
        return "https://" + url
    }
}
