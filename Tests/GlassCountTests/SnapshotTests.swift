import Testing
import SwiftUI
import AppKit
@testable import GlassCount

/// Offscreen render of the real views to PNG (only when GC_SNAPSHOT_DIR is set). Layout check only —
/// window-server effects such as live Liquid Glass sampling are not reproduced offscreen.
@MainActor
@Suite("Snapshots")
struct SnapshotTests {
    func render<V: View>(_ view: V, size: CGSize, name: String, dir: String) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    @Test func renderScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["GC_SNAPSHOT_DIR"] else { return }
        var opts = LaunchOptions(); opts.dataDirectory = makeTempDir(); opts.seedDemo = true; opts.systemNotifications = false
        let model = AppModel(options: opts)
        let ev = model.store.events
        model.store.setCardSize(id: ev[1].id, width: 420, height: 230)
        render(MainWindow().environment(model), size: CGSize(width: 1000, height: 760), name: "main-light", dir: dir)
        render(MainWindow().environment(model).preferredColorScheme(.dark), size: CGSize(width: 1000, height: 760), name: "main-dark", dir: dir)
        render(MainWindow().environment(model), size: CGSize(width: 660, height: 700), name: "main-narrow", dir: dir)
        render(BackgroundSheet().environment(model), size: CGSize(width: 500, height: 700), name: "background-sheet", dir: dir)
        render(DesktopWidgetView().environment(model), size: CGSize(width: 260, height: 160), name: "desktop-widget", dir: dir)
        render(EventEditorView(target: .new).environment(model), size: CGSize(width: 480, height: 640), name: "editor", dir: dir)
        var empty = LaunchOptions(); empty.dataDirectory = makeTempDir(); empty.systemNotifications = false
        render(MainWindow().environment(AppModel(options: empty)), size: CGSize(width: 900, height: 600), name: "empty", dir: dir)
    }
}
