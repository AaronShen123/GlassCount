import SwiftUI
import AppKit

/// Holds the hosting NSWindow and the observers that implement placement rules.
@MainActor
final class WidgetWindowController {
    weak var window: NSWindow?
    var onPlaced: ((CGPoint) -> Void)?
    private var moveObserver: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    private var snapping = false

    func attach(_ w: NSWindow) {
        guard window !== w else { return }
        window = w
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.movedByUser() }
        }
    }

    /// Wait until the user stops dragging, then snap to the grid inside the visible screen area.
    private func movedByUser() {
        guard !snapping else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.snapToPlacement(animated: true) }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    func snapToPlacement(animated: Bool) {
        guard let w = window, let vis = (w.screen ?? NSScreen.main)?.visibleFrame else { return }
        let inset = DesktopWidgetView.inset
        let card = w.frame.insetBy(dx: inset, dy: inset)
        let snapped = WidgetPlacement.resolve(card: card, in: vis, avoiding: Self.otherDesktopWidgets(screen: w.screen ?? NSScreen.main, excluding: w))
        let target = snapped.insetBy(dx: -inset, dy: -inset)
        snapping = true
        if target != w.frame { w.setFrame(target, display: true, animate: animated) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.snapping = false }
        onPlaced?(target.origin)
    }

    /// Best effort: rects (Cocoa coords) of other processes' desktop-level windows that look like widgets.
    /// Uses the public window list (bounds only; no Screen Recording permission needed). Large windows
    /// (Finder's desktop, wallpaper, Dock) are ignored. Not verified against system widgets on every macOS version.
    static func otherDesktopWidgets(screen: NSScreen?, excluding w: NSWindow) -> [CGRect] {
        guard let screen, let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ignoredOwners: Set<String> = ["Finder", "Dock", "WindowServer", "Window Server", "SystemUIServer"]
        let me = ProcessInfo.processInfo.processIdentifier
        var out: [CGRect] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer < 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != me,
                  let owner = info[kCGWindowOwnerName as String] as? String, !ignoredOwners.contains(owner),
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: dict) else { continue }
            // CG coordinates: origin top-left of the primary display → Cocoa: origin bottom-left.
            let rect = CGRect(x: cg.minX, y: primary.frame.height - cg.maxY, width: cg.width, height: cg.height)
            guard rect.intersects(screen.frame),
                  rect.width * rect.height < screen.frame.width * screen.frame.height * 0.5, rect.width > 40, rect.height > 40
            else { continue }
            out.append(rect)
        }
        return out
    }

    /// Resizes keeping the top-left corner fixed, then re-applies the placement rules.
    func setPreset(_ p: WidgetPreset, animated: Bool) {
        guard let w = window else { return }
        let inset = DesktopWidgetView.inset
        let content = NSRect(x: 0, y: 0, width: p.size.width + 2 * inset, height: p.size.height + 2 * inset)
        let size = w.frameRect(forContentRect: content).size
        let top = w.frame.maxY
        snapping = true
        w.setFrame(NSRect(x: w.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true, animate: animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.snapping = false }
        snapToPlacement(animated: animated)
    }

    /// First placement: restore the saved origin if it is still on a screen, else the top-right corner.
    func restore(origin: [Double]?, preset: WidgetPreset) {
        guard let w = window else { return }
        let inset = DesktopWidgetView.inset
        let size = NSSize(width: preset.size.width + 2 * inset, height: preset.size.height + 2 * inset)
        var o = CGPoint.zero
        if let origin, origin.count == 2, NSScreen.screens.contains(where: { $0.visibleFrame.contains(CGPoint(x: origin[0] + 20, y: origin[1] + 20)) }) {
            o = CGPoint(x: origin[0], y: origin[1])
        } else if let vis = NSScreen.main?.visibleFrame {
            o = CGPoint(x: vis.maxX - size.width - 24, y: vis.maxY - size.height - 24)
        }
        w.setFrame(NSRect(origin: o, size: size), display: true)
        snapToPlacement(animated: false)
    }

    deinit { if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) } }
}

/// Small glass card that sits on the desktop. Fixed sizes (Small/Medium/Large) and grid placement,
/// in the spirit of system widgets. The window is the source of truth for size.
struct DesktopWidgetView: View {
    static let inset: CGFloat = 12
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var hovering = false
    @State private var controller = WidgetWindowController()
    @State private var dragStart: (mouse: NSPoint, size: CGSize)?
    @State private var previewPreset: WidgetPreset?

    private var preset: WidgetPreset { previewPreset ?? model.store.settings.widgetPreset }

    var body: some View {
        GeometryReader { geo in
            card(size: CGSize(width: max(geo.size.width - 2 * Self.inset, 1), height: max(geo.size.height - 2 * Self.inset, 1)))
                .padding(Self.inset)
        }
        .background(DesktopWindowConfigurator { window in
            controller.attach(window)
            controller.onPlaced = { origin in
                model.store.updateSettings { $0.widgetOrigin = [Double(origin.x), Double(origin.y)] }
            }
            controller.restore(origin: model.store.settings.widgetOrigin, preset: model.store.settings.widgetPreset)
        })
        .onChange(of: model.store.settings.widgetPreset) { _, new in
            if dragStart == nil { controller.setPreset(new, animated: true) }
        }
    }

    // MARK: Card

    @ViewBuilder
    private func card(size: CGSize) -> some View {
        let scale = (min(size.width, size.height) / 160).clamped(to: 0.8...2.0)
        let showDate = size.width >= 300
        let showProgress = size.height >= 300
        Group {
            if let e = model.store.featuredEvent {
                LiveCountdown(target: e.targetDate, showsSeconds: false) { b, now in
                    VStack(alignment: .leading, spacing: 8 * scale) {
                        Label(e.title, systemImage: e.iconName)
                            .font(.system(size: 16 * scale, weight: .semibold)).lineLimit(1).foregroundStyle(e.colorToken.color)
                        if b.isExpired {
                            Text("It’s here!").font(.system(size: 28 * scale, weight: .bold, design: .rounded))
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(CountdownFormatter.days(b)).font(.system(size: 44 * scale, weight: .semibold, design: .rounded)).monospacedDigit()
                                Text(b.totalDays == 1 ? "day" : "days").font(.system(size: 15 * scale)).foregroundStyle(.secondary)
                            }
                            .lineLimit(1).minimumScaleFactor(0.4)
                            Text("\(b.hours)h \(CountdownFormatter.twoDigits(b.minutes))m")
                                .font(.system(size: 15 * scale).monospacedDigit()).foregroundStyle(.secondary)
                        }
                        if showDate {
                            Text(e.targetDate.formatted(date: .complete, time: .omitted))
                                .font(.system(size: 13 * scale)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if showProgress, let p = CountdownEngine.progress(start: e.startDate, target: e.targetDate, now: now) {
                            Spacer(minLength: 0)
                            ProgressView(value: p).tint(e.colorToken.color)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(e.title), \(CountdownFormatter.spoken(b))")
                }
            } else {
                Label("No countdowns", systemImage: "hourglass").foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .dark)
        .environment(\.hasPhotoBackground, true)
        .glassSurface(cornerRadius: 26)
        .overlay(alignment: .topTrailing) {
            Button {
                model.store.updateSettings { $0.showDesktopWidget = false }
                dismissWindow(id: "widget")
            } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).padding(8)
                .opacity(hovering ? 1 : 0).help("Close desktop widget").accessibilityLabel("Close desktop widget")
        }
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .contextMenu {
            Picker("Size", selection: Binding(get: { model.store.settings.widgetPreset },
                                              set: { v in model.store.updateSettings { $0.widgetPreset = v } })) {
                ForEach(WidgetPreset.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Button("Close Widget") { model.store.updateSettings { $0.showDesktopWidget = false }; dismissWindow(id: "widget") }
        }
        .onHover { hovering = $0 }
    }

    // MARK: Resize handle: snaps to the nearest fixed size

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .rotationEffect(.degrees(90))
            .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            .padding(10).contentShape(Rectangle())
            .opacity(hovering || dragStart != nil ? 1 : 0)
            .help("Drag to change size (Small / Medium / Large)").accessibilityLabel("Resize desktop widget")
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        guard let w = controller.window else { return }
                        if dragStart == nil {
                            dragStart = (NSEvent.mouseLocation, model.store.settings.widgetPreset.size)
                            _ = w
                        }
                        guard let d = dragStart else { return }
                        let m = NSEvent.mouseLocation
                        let free = CGSize(width: d.size.width + (m.x - d.mouse.x), height: d.size.height - (m.y - d.mouse.y))
                        let target = WidgetPreset.nearest(to: free)
                        if target != previewPreset {
                            previewPreset = target
                            controller.setPreset(target, animated: true)   // live snap preview
                        }
                    }
                    .onEnded { _ in
                        if let p = previewPreset { model.store.updateSettings { $0.widgetPreset = p } }
                        previewPreset = nil; dragStart = nil
                    })
    }
}

/// Turns the hosting window into a borderless, transparent, draggable desktop-level window.
private struct DesktopWindowConfigurator: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.isMovableByWindowBackground = true
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.styleMask.remove(.resizable)    // size only changes through the fixed presets
            w.standardWindowButton(.closeButton)?.isHidden = true
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            onWindow(w)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
