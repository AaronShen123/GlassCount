import AppKit
import ImageIO

/// Decoded, display-sized images. Cost-limited so many events cannot balloon memory.
final class BackgroundImageCache: @unchecked Sendable {
    private let cache = NSCache<NSString, NSImage>()
    private let store: BackgroundImageStore

    init(store: BackgroundImageStore, costLimitBytes: Int = 120 * 1024 * 1024) {
        self.store = store
        cache.totalCostLimit = costLimitBytes
    }

    func cached(fileName: String, maxPixel: Int) -> NSImage? {
        cache.object(forKey: key(fileName, maxPixel))
    }

    /// Loads (decoding off the main thread) at most `maxPixel` on the long edge. Nil if missing/undecodable.
    @MainActor func image(fileName: String, maxPixel: Int) async -> NSImage? {
        if let hit = cached(fileName: fileName, maxPixel: maxPixel) { return hit }
        guard let url = store.url(for: fileName) else { return nil }
        let cgImage: CGImage? = await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return cg
        }.value
        let img = cgImage.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        if let img, let cgImage {
            cache.setObject(img, forKey: key(fileName, maxPixel), cost: cgImage.width * cgImage.height * 4)
        }
        return img
    }

    func evict(fileName: String) {
        // NSCache has no key enumeration; clearing is cheap and only happens on replace/remove.
        cache.removeAllObjects()
    }

    private func key(_ f: String, _ m: Int) -> NSString { "\(f)@\(m)" as NSString }
}
