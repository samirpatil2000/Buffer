import Foundation
import Combine

class WebLinkStore: ObservableObject {
    @Published var links: [WebLink] = []

    private let fileManager = FileManager.default
    private let saveQueue = DispatchQueue(label: "com.buffer.weblinks.save", qos: .utility)

    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Buffer", isDirectory: true)
    }

    private var fileURL: URL {
        storageDirectory.appendingPathComponent("weblinks.json")
    }

    init() {
        ensureDirectoriesExist()
        load()
    }

    func add(name: String, url: String) {
        let maxOrder = links.map(\.sortOrder).max() ?? 0
        let link = WebLink(name: name, url: url, sortOrder: maxOrder + 1)
        DispatchQueue.main.async { [weak self] in
            self?.links.append(link)
            self?.persist()
        }
    }

    func update(_ link: WebLink) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let index = self.links.firstIndex(where: { $0.id == link.id }) else { return }
            self.links[index] = link
            self.persist()
        }
    }

    func delete(_ link: WebLink) {
        DispatchQueue.main.async { [weak self] in
            self?.links.removeAll { $0.id == link.id }
            self?.persist()
        }
    }

    func recordOpen(_ link: WebLink) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let index = self.links.firstIndex(where: { $0.id == link.id }) else { return }
            self.links[index].lastOpenedAt = Date()
            self.links[index].visitCount += 1
            self.persist()
        }
    }

    private func ensureDirectoriesExist() {
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode([WebLink].self, from: data)
            self.links = loaded
        } catch {
            print("[Buffer] Failed to load web links: \(error)")
        }
    }

    private func persist() {
        let items = links
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(items)
                try data.write(to: self.fileURL)
            } catch {
                print("[Buffer] Failed to save web links: \(error)")
            }
        }
    }
}
