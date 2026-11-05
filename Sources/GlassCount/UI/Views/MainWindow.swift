import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDelete: UUID?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let store = model.store
        let bg = store.settings.background
        CachedImage(fileName: bg.imageFileName, maxPixel: 2560) { image in
            ZStack {
                BackgroundLayer(settings: bg, image: image)
                dashboard(store: store)
                    .environment(\.hasPhotoBackground, image != nil)
                    .environment(\.colorScheme, image != nil ? .dark : colorSchemeFallback)
            }
        }
        .task {
            model.widgetWindowControl = { show in
                if show { openWindow(id: "widget") } else { dismissWindow(id: "widget") }
            }
            model.syncDesktopWidget()
        }
        .sheet(item: Binding(get: { model.editor }, set: { model.editor = $0 })) { target in
            EventEditorView(target: target)
                .environment(model)
        }
        .sheet(isPresented: Binding(get: { model.showBackgroundSheet }, set: { model.showBackgroundSheet = $0 })) {
            BackgroundSheet().environment(model)
        }
        .confirmationDialog("Delete this countdown?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { id in
            Button("Delete", role: .destructive) { delete(id) }
            Button("Cancel", role: .cancel) {}
        } message: { id in
            Text("“\(store.event(id: id)?.title ?? "")” will be removed. This can’t be undone.")
        }
        .alert("GlassCount", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil; store.clearStatusMessage() } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }

    @Environment(\.colorScheme) private var colorSchemeFallback

    private func delete(_ id: UUID) {
        model.store.delete(id: id)
        model.cleanupImages()
    }

    @ViewBuilder
    private func dashboard(store: AppStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeaderBar()
                if store.events.isEmpty {
                    EmptyStateView()
                } else {
                    if let featured = store.featuredEvent {
                        FeaturedCountdownCard(event: featured, detail: store.settings.detail,
                                              onEdit: { model.editor = .edit(featured.id) },
                                              onDelete: { pendingDelete = featured.id })
                    }
                    let others = store.events.filter { $0.id != store.featuredEvent?.id }
                    if !others.isEmpty {
                        Text("Upcoming").font(.title3.weight(.semibold)).padding(.leading, 4)
                        GlassGroup(spacing: 20) {
                            FlowLayout(spacing: 16) {
                                ForEach(others) { event in
                                    CountdownCard(event: event, detail: store.settings.detail,
                                                  onEdit: { model.editor = .edit(event.id) },
                                                  onDelete: { pendingDelete = event.id },
                                                  onDuplicate: { store.duplicate(id: event.id) },
                                                  onFeature: { store.setFeatured(id: event.id) },
                                                  onMove: { delta in move(event.id, delta: delta, within: others) },
                                                  onResize: { w, h in store.setCardSize(id: event.id, width: w, height: h) })
                                    .dropDestination(for: String.self) { items, _ in
                                        guard let s = items.first, let dragged = UUID(uuidString: s) else { return false }
                                        store.moveEvent(id: dragged, onto: event.id)
                                        return true
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)      // clears the hidden-title-bar traffic lights
            .padding(.bottom, 28)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }

    private func move(_ id: UUID, delta: Int, within list: [CountdownEvent]) {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard list.indices.contains(j) else { return }
        model.store.moveEvent(id: id, onto: list[j].id)
    }
}

struct HeaderBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Text("GlassCount")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            Spacer()
            GlassGroup(spacing: 12) {
                HStack(spacing: 10) {
                    Button { model.editor = .new } label: { Label("Add Countdown", systemImage: "plus") }
                        .glassButtonStyle(prominent: true)
                        .accessibilityIdentifier("addCountdown")
                    Button { model.showBackgroundSheet = true } label: { Label("Background", systemImage: "photo") }
                        .glassButtonStyle()
                        .help("Customize background")
                        .accessibilityIdentifier("customizeBackground")
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                        .glassButtonStyle()
                        .help("Settings")
                        .accessibilityIdentifier("openSettings")
                }
                .labelStyle(.titleAndIcon)
                .controlSize(.large)
            }
        }
    }
}

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.secondary)
            Text("No countdowns yet").font(.title2.weight(.semibold))
            Text("Add your first event and GlassCount will keep count of the days, hours, minutes and seconds.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            Button { model.editor = .new } label: { Label("Add Countdown", systemImage: "plus") }
                .glassButtonStyle(prominent: true)
                .controlSize(.large)
        }
        .padding(48)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 36)
        .padding(.top, 40)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emptyState")
    }
}
