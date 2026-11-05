import SwiftUI
import AppKit

/// Built-in backdrop (one of `DefaultBackgroundStyle`). Adapts to light / dark.
struct DefaultBackground: View {
    var style: DefaultBackgroundStyle = .aurora
    @Environment(\.colorScheme) private var scheme

    private func c(_ v: [Double], _ a: Double = 1) -> Color { Color(red: v[0], green: v[1], blue: v[2]).opacity(a) }

    var body: some View {
        let dark = scheme == .dark
        let p = dark ? style.palette.dark : style.palette.light
        ZStack {
            LinearGradient(colors: [c(p[0]), c(p[1])], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Radial gradients, not blurred shapes: a large Gaussian blur is rasterised on the CPU on every redraw.
            RadialGradient(colors: [c(p[2], 0.45), .clear], center: UnitPoint(x: 0.15, y: 0.05), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [c(p[3], 0.40), .clear], center: UnitPoint(x: 0.9, y: 0.95), startRadius: 0, endRadius: 560)
        }
        .ignoresSafeArea()
    }
}

/// Loads a stored image through the shared cache and hands it to `content` (nil while loading/missing).
struct CachedImage<Content: View>: View {
    @Environment(AppModel.self) private var model
    let fileName: String?
    let maxPixel: Int
    @ViewBuilder var content: (NSImage?) -> Content
    @State private var image: NSImage?

    var body: some View {
        content(image)
            .task(id: fileName) {
                guard let fileName else { image = nil; return }
                if let hit = model.imageCache.cached(fileName: fileName, maxPixel: maxPixel) { image = hit; return }
                image = await model.imageCache.image(fileName: fileName, maxPixel: maxPixel)
            }
    }
}

/// Custom image → blur → dim, over the default backdrop. Pure presentation.
struct BackgroundLayer: View {
    let settings: BackgroundSettings
    let image: NSImage?

    var body: some View {
        ZStack {
            DefaultBackground(style: settings.defaultStyle)
            if let image {
                GeometryReader { geo in
                    let blurScale = 1 + settings.blur / 300   // hides transparent blur edges
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: settings.fit == .fill ? .fill : .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(settings.blur > 0 ? blurScale : 1)
                        .blur(radius: settings.blur)
                        .opacity(settings.opacity)
                        .clipped()
                }
                Color.black.opacity(settings.dimming)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
