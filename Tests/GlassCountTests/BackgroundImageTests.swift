import Testing
import Foundation
import UniformTypeIdentifiers
import CryptoKit
@testable import GlassCount

@Suite("Background images")
struct BackgroundImageTests {
    func makeStore() -> (BackgroundImageStore, URL, URL) {
        let root = makeTempDir()
        let src = root.appendingPathComponent("sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        return (BackgroundImageStore(directory: root.appendingPathComponent("Backgrounds")), src, root)
    }
    func sha(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }

    @Test func importsJPEGAndPNG() async throws {
        let (store, src, _) = makeStore()
        let jpg = src.appendingPathComponent("a.jpg"), png = src.appendingPathComponent("b.png")
        #expect(writeImage(to: jpg, type: .jpeg, width: 800, height: 600))
        #expect(writeImage(to: png, type: .png, width: 400, height: 400))
        let n1 = try await store.importImage(from: jpg), n2 = try await store.importImage(from: png)
        #expect(BackgroundImageStore.isStoredName(n1) && BackgroundImageStore.isStoredName(n2))
        #expect(store.url(for: n1) != nil && store.url(for: n2) != nil)
        #expect(pixelSize(of: store.url(for: n1)!)! == (800, 600))
    }

    @Test func importsHEICWhenSystemCanEncodeIt() async throws {
        let (store, src, _) = makeStore()
        let heic = src.appendingPathComponent("c.heic")
        guard writeImage(to: heic, type: .heic, width: 640, height: 480) else {
            Issue.record("HEIC encoding unavailable on this machine — HEIC import not exercised")
            return
        }
        let name = try await store.importImage(from: heic)
        #expect(store.url(for: name) != nil)
    }

    @Test func rejectsUnsupportedAndFakeImages() async throws {
        let (store, src, _) = makeStore()
        let txt = src.appendingPathComponent("notes.txt"); try "hello".write(to: txt, atomically: true, encoding: .utf8)
        let fake = src.appendingPathComponent("fake.jpg"); try "this is text".write(to: fake, atomically: true, encoding: .utf8)
        let gif = src.appendingPathComponent("anim.gif")
        #expect(writeImage(to: gif, type: .gif, width: 50, height: 50))
        for bad in [txt, fake, gif] {
            await #expect(throws: BackgroundImportError.self) { _ = try await store.importImage(from: bad) }
        }
        await #expect(throws: BackgroundImportError.self) { _ = try await store.importImage(from: src.appendingPathComponent("missing.png")) }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path))?.isEmpty ?? true)
    }

    @Test func rejectsCorruptedImage() async throws {
        let (store, src, _) = makeStore()
        let good = src.appendingPathComponent("good.jpg")
        #expect(writeImage(to: good, type: .jpeg, width: 1200, height: 900))
        var data = try Data(contentsOf: good)
        data.removeSubrange((data.count / 3)...)                     // truncate the JPEG body
        let bad = src.appendingPathComponent("corrupt.jpg"); try data.write(to: bad)
        // A truncated JPEG may decode partially or fail; it must never crash and must never leave a broken file behind.
        do {
            let name = try await store.importImage(from: bad)
            #expect(pixelSize(of: store.url(for: name)!) != nil)
        } catch {
            #expect(error is BackgroundImportError)
            #expect((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path))?.filter { !$0.hasSuffix(".tmp") }.isEmpty ?? true)
        }
        // Header-only garbage after a valid JPEG signature:
        let junk = src.appendingPathComponent("junk.jpg"); try Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]).write(to: junk)
        await #expect(throws: BackgroundImportError.self) { _ = try await store.importImage(from: junk) }
    }

    @Test func largeImagesAreDownsampled() async throws {
        let (store, src, _) = makeStore()
        let big = src.appendingPathComponent("big.jpg")
        #expect(writeImage(to: big, type: .jpeg, width: 8000, height: 6000))     // 48 MP
        let clock = ContinuousClock()
        var name = ""
        let elapsed = try await clock.measure { name = try await store.importImage(from: big) }
        let (w, h) = pixelSize(of: store.url(for: name)!)!
        #expect(max(w, h) <= BackgroundImageStore.maxStoredPixelSize)
        #expect(abs(Double(w) / Double(h) - 8000.0 / 6000.0) < 0.01)
        print("PERF import 48MP JPEG → \(w)x\(h): \(elapsed)")
    }

    @Test func alphaPNGKeepsAlpha() async throws {
        let (store, src, _) = makeStore()
        let p = src.appendingPathComponent("alpha.png")
        #expect(writeImage(to: p, type: .png, width: 200, height: 200, alpha: true))
        let name = try await store.importImage(from: p)
        #expect(name.hasSuffix(".png"))
    }

    @Test func originalIsNeverModifiedOrDeleted() async throws {
        let (store, src, _) = makeStore()
        let p = src.appendingPathComponent("orig.jpg")
        #expect(writeImage(to: p, type: .jpeg, width: 500, height: 500))
        let before = try sha(p)
        let name = try await store.importImage(from: p)
        store.remove(fileName: name)
        store.removeUnreferenced(keeping: [])
        #expect(FileManager.default.fileExists(atPath: p.path))
        #expect(try sha(p) == before)
        #expect(store.url(for: name) == nil)
    }

    @Test func replacementAndRemoval() async throws {
        let (store, src, _) = makeStore()
        let p = src.appendingPathComponent("x.jpg"); #expect(writeImage(to: p, type: .jpeg, width: 300, height: 300))
        let first = try await store.importImage(from: p)
        let second = try await store.importImage(from: p)
        #expect(first != second)
        store.removeUnreferenced(keeping: [second])          // replacing → old copy cleaned, new kept
        #expect(store.url(for: first) == nil && store.url(for: second) != nil)
        store.remove(fileName: second)
        #expect(store.url(for: second) == nil)
    }

    @MainActor @Test func missingStoredFileIsHandled() async throws {
        let (store, _, _) = makeStore()
        #expect(store.url(for: "\(UUID().uuidString).jpg") == nil)
        #expect(store.url(for: nil) == nil)
        store.remove(fileName: "\(UUID().uuidString).jpg")      // no crash
        let cache = BackgroundImageCache(store: store)
        #expect(await cache.image(fileName: "\(UUID().uuidString).jpg", maxPixel: 100) == nil)
    }

    @Test func pathTraversalNamesAreIgnored() throws {
        let (store, _, root) = makeStore()
        let victim = root.appendingPathComponent("victim.txt"); try "keep".write(to: victim, atomically: true, encoding: .utf8)
        store.remove(fileName: "../victim.txt")
        store.remove(fileName: "../../etc/hosts")
        #expect(FileManager.default.fileExists(atPath: victim.path))
        #expect(!BackgroundImageStore.isStoredName("../a.jpg") && !BackgroundImageStore.isStoredName("notauuid.jpg"))
    }

    @MainActor
    @Test func cacheReturnsDownsampledImage() async throws {
        let (store, src, _) = makeStore()
        let p = src.appendingPathComponent("c.jpg"); #expect(writeImage(to: p, type: .jpeg, width: 2000, height: 1000))
        let name = try await store.importImage(from: p)
        let cache = BackgroundImageCache(store: store)
        let img = await cache.image(fileName: name, maxPixel: 500)
        #expect(img != nil)
        let cg = img!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        #expect(max(cg.width, cg.height) <= 500 && cg.width == 500)
        #expect(cache.cached(fileName: name, maxPixel: 500) != nil)
    }
}
