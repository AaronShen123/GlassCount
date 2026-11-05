import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BackgroundImportError: LocalizedError, Equatable {
    case fileNotReadable
    case unsupportedType(String)
    case fileTooLarge(Int64)
    case imageTooLarge(Int, Int)
    case decodeFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotReadable: return "The file could not be opened."
        case .unsupportedType(let t): return "“\(t)” is not supported. Choose a JPEG, PNG or HEIC image."
        case .fileTooLarge(let b): return "The file is too large (\(ByteCountFormatter.string(fromByteCount: b, countStyle: .file)))."
        case .imageTooLarge(let w, let h): return "The image dimensions (\(w)×\(h)) are too large."
        case .decodeFailed: return "The image is damaged or could not be decoded."
        case .writeFailed(let m): return "The image could not be saved: \(m)"
        }
    }
}

/// Imports user photos into the app's own Application Support folder.
/// The user's original file is only ever read, never modified or deleted.
struct BackgroundImageStore: Sendable {
    static let maxFileBytes: Int64 = 150 * 1024 * 1024
    static let maxSourcePixels = 400_000_000
    /// Longest edge of the stored display representation.
    static let maxStoredPixelSize = 3200
    static let allowedTypes: [UTType] = [.jpeg, .png, .heic]

    let directory: URL

    /// Imports and returns the stored file name. Runs off the main thread.
    func importImage(from source: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) { try self.importSync(from: source) }.value
    }

    func importSync(from source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: source.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value else { throw BackgroundImportError.fileNotReadable }
        if size > Self.maxFileBytes { throw BackgroundImportError.fileTooLarge(size) }

        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(source as CFURL, opts) else {
            // Not an image at all (e.g. a text file renamed to .jpg).
            throw BackgroundImportError.unsupportedType(source.lastPathComponent)
        }
        // Sniff the real content type: the extension is not trusted.
        guard let uti = CGImageSourceGetType(src) as String?, let type = UTType(uti),
              Self.allowedTypes.contains(where: { type.conforms(to: $0) }) else {
            throw BackgroundImportError.unsupportedType(source.lastPathComponent)
        }
        guard CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { throw BackgroundImportError.decodeFailed }
        if w * h > Self.maxSourcePixels { throw BackgroundImportError.imageTooLarge(w, h) }

        // Downsampled decode: never materialises the full-size bitmap.
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxStoredPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else {
            throw BackgroundImportError.decodeFailed
        }

        let hasAlpha: Bool = {
            switch image.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: return false; default: return true }
        }()
        let outType: UTType = hasAlpha ? .png : .jpeg
        let name = UUID().uuidString + (hasAlpha ? ".png" : ".jpg")
        let final = directory.appendingPathComponent(name)
        let temp = directory.appendingPathComponent(name + ".tmp")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, outType.identifier as CFString, 1, nil) else {
                throw BackgroundImportError.writeFailed("could not create destination")
            }
            let destOpts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.88]
            CGImageDestinationAddImage(dest, image, destOpts as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw BackgroundImportError.writeFailed("encoding failed") }
            try FileManager.default.moveItem(at: temp, to: final)
        } catch let e as BackgroundImportError {
            try? FileManager.default.removeItem(at: temp); throw e
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw BackgroundImportError.writeFailed(error.localizedDescription)
        }
        return name
    }

    /// URL of a stored image, or nil when the file has gone missing.
    func url(for fileName: String?) -> URL? {
        guard let fileName, Self.isStoredName(fileName) else { return nil }
        let u = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// Deletes our own copy only.
    func remove(fileName: String?) {
        guard let fileName, Self.isStoredName(fileName) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    /// Removes app-created copies that nothing references any more.
    func removeUnreferenced(keeping referenced: Set<String>) {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for item in items where Self.isStoredName(item) && !referenced.contains(item) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(item))
        }
    }

    /// Only names we generated (UUID + jpg/png) are ever touched; blocks path traversal.
    static func isStoredName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, ["jpg", "png"].contains(parts[1]) else { return false }
        return UUID(uuidString: String(parts[0])) != nil
    }
}
