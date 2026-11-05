import SwiftUI

// All Liquid Glass / Material access is confined to this file.
//
// Real Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.glass` button styles) needs the macOS 26 SDK
// (Swift 6.2+ compiler) and macOS 26+ at runtime. On older SDKs/OSes the code falls back to
// `ultraThinMaterial` + a hairline highlight + soft shadow.
// NOTE: the `#if compiler(>=6.2)` branches could NOT be compiled in the authoring environment
// (Command Line Tools with the macOS 15.5 SDK) — see KNOWN_ISSUES.md.

enum GlassSupport {
    /// True only when compiled with the Liquid Glass SDK *and* running on macOS 26+.
    static var isLiquidGlassActive: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}

private struct PhotoBackgroundKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True when a user photo is behind the content (switches to dark tinting for legibility).
    var hasPhotoBackground: Bool {
        get { self[PhotoBackgroundKey.self] }
        set { self[PhotoBackgroundKey.self] = newValue }
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    var interactive: Bool
    @Environment(\.hasPhotoBackground) private var photo

    private var effectiveTint: Color? { tint ?? (photo ? Color.black.opacity(0.28) : nil) }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            fallback(content, shape)
        }
        #else
        fallback(content, shape)
        #endif
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let t = effectiveTint { g = g.tint(t) }
        if interactive { g = g.interactive() }
        return g
    }
    #endif

    @ViewBuilder
    private func fallback(_ content: Content, _ shape: RoundedRectangle) -> some View {
        content
            .background {
                // Shadow lives on a static shape, not on the (ticking) content, so it isn't re-blurred every second.
                shape.fill(Color.black.opacity(0.001)).shadow(color: .black.opacity(0.16), radius: 18, y: 8)
                shape.fill(.ultraThinMaterial)
                if let t = effectiveTint { shape.fill(t.opacity(photo ? 1 : 0.10)) }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.06), .white.opacity(0.22)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            }
    }
}

extension View {
    /// Applies a Liquid Glass surface (or the Material fallback) in a continuous rounded rectangle.
    func glassSurface(cornerRadius: CGFloat = 28, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    /// `.glass` / `.glassProminent` button style on macOS 26+, bordered styles otherwise.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            legacyButton(prominent)
        }
        #else
        legacyButton(prominent)
        #endif
    }

    @ViewBuilder
    private func legacyButton(_ prominent: Bool) -> some View {
        if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
    }
}

/// Groups neighbouring glass elements so they blend and morph together (`GlassEffectContainer` on macOS 26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
