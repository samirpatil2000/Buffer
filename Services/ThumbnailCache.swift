import AppKit

/// Centralized, bounded memory cache for image thumbnails.
/// Replaces unconstrained row storage so off-screen thumbnails are purged under memory pressure.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    
    private let cache = NSCache<NSUUID, NSImage>()
    
    private init() {
        cache.countLimit = 60 // Keep at most 60 thumbnails in memory
        cache.totalCostLimit = 10 * 1024 * 1024 // 10 MB maximum memory cost
    }
    
    func image(for id: UUID) -> NSImage? {
        cache.object(forKey: id as NSUUID)
    }
    
    func setImage(_ image: NSImage, for id: UUID) {
        // Approximate cost in bytes: width * height * 4 bytes per pixel
        let cost = max(1024, Int(image.size.width * image.size.height * 4))
        cache.setObject(image, forKey: id as NSUUID, cost: cost)
    }
    
    func removeImage(for id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }
    
    func clear() {
        cache.removeAllObjects()
    }
}
