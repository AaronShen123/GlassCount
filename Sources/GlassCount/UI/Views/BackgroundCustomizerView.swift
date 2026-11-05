import SwiftUI

/// Shared by the sheet (header button) and the Settings › Background tab.
struct BackgroundCustomizerView: View {
    @Environment(AppModel.self) private var model
    @State private var showImporter = false
    @State private var isImporting = false

    var body: some View {
        let store = model.store
        let bg = store.settings.background
        VStack(alignment: .leading, spacing: 16) {
            CachedImage(fileName: bg.imageFileName, maxPixel: 900) { img in
                ZStack {
                    BackgroundLayer(settings: bg, image: img).clipped()
                    if img == nil {
                        Text(bg.imageFileName == nil ? "Default background" : "Image file is missing")
                            .font(.caption).padding(6).background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.2)))
            }

            if bg.imageFileName != nil, model.backgrounds.url(for: bg.imageFileName) == nil {
                Label("The stored background image is missing. Choose a new one or restore the default.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }

            HStack {
                Button { showImporter = true } label: {
                    Label(bg.imageFileName == nil ? "Choose Image…" : "Replace Image…", systemImage: "photo.on.rectangle")
                }
                .disabled(isImporting)
                .accessibilityIdentifier("chooseBackground")
                Button("Remove", role: .destructive) { model.removeGlobalBackground() }
                    .disabled(bg.imageFileName == nil)
                Spacer()
                if isImporting { ProgressView().controlSize(.small) }
                Button("Restore Default") { model.restoreDefaultBackground() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Built-in backgrounds").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 10), count: 5), alignment: .leading, spacing: 10) {
                    ForEach(DefaultBackgroundStyle.allCases, id: \.self) { style in
                        Button {
                            store.updateSettings { $0.background.defaultStyle = style }
                        } label: {
                            DefaultBackground(style: style)
                                .frame(width: 64, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(bg.defaultStyle == style ? Color.accentColor : .white.opacity(0.25), lineWidth: bg.defaultStyle == style ? 2.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .help(style.title)
                        .accessibilityLabel("\(style.title) background")
                        .accessibilityAddTraits(bg.defaultStyle == style ? .isSelected : [])
                    }
                }
                Text("Shown when no photo is set.").font(.caption2).foregroundStyle(.secondary)
            }

            Picker("Image fit", selection: Binding(get: { bg.fit }, set: { v in store.updateSettings { $0.background.fit = v } })) {
                ForEach(BackgroundFit.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(bg.imageFileName == nil)

            slider("Blur", value: Binding(get: { bg.blur }, set: { v in store.updateSettings { $0.background.blur = v } }),
                   range: BackgroundSettings.blurRange, format: { "\(Int($0)) pt" })
            slider("Dimming", value: Binding(get: { bg.dimming }, set: { v in store.updateSettings { $0.background.dimming = v } }),
                   range: BackgroundSettings.dimRange, format: { $0.formatted(.percent.precision(.fractionLength(0))) })
            slider("Image opacity", value: Binding(get: { bg.opacity }, set: { v in store.updateSettings { $0.background.opacity = v } }),
                   range: BackgroundSettings.opacityRange, format: { $0.formatted(.percent.precision(.fractionLength(0))) })
            Text("Your original photo is never modified. GlassCount keeps its own resized copy in Application Support.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: BackgroundImageStore.allowedTypes) { result in
            guard case .success(let url) = result else { return }
            isImporting = true
            Task {
                await model.importAsGlobalBackground(url)
                isImporting = false
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(title)
            Text(format(value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
        }
        .disabled(model.store.settings.background.imageFileName == nil)
    }
}

struct BackgroundSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Background").font(.title2.weight(.semibold))
            BackgroundCustomizerView()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }
        .padding(24)
        .frame(width: 500)
    }
}
