import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import GlassCount

func makeTempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("GlassCountTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

func calendar(_ tz: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!
    return c
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0, tz: String = "UTC") -> Date {
    calendar(tz).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
}

/// Writes a synthetic image of the given pixel size. Returns nil if the encoder isn't available (e.g. HEIC).
@discardableResult
func writeImage(to url: URL, type: UTType, width: Int, height: Int, alpha: Bool = false) -> Bool {
    let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return false }
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.3, alpha: alpha ? 0.5 : 1)); ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    guard let img = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, img, nil)
    return CGImageDestinationFinalize(dest)
}

func pixelSize(of url: URL) -> (Int, Int)? {
    guard let s = CGImageSourceCreateWithURL(url as CFURL, nil),
          let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
          let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return (w, h)
}
