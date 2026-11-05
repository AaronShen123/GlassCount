import SwiftUI
import AppKit

/// Popover for the menu bar item. Its countdown only ticks while the popover is on screen.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let store = model.store
        VStack(alignment: .leading, spacing: 12) {
            if let e = store.featuredEvent {
                LiveCountdown(target: e.targetDate, showsSeconds: store.settings.detail.effectiveSeconds) { b, _ in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(e.title, systemImage: e.iconName).font(.headline).foregroundStyle(e.colorToken.color)
                        let d = store.settings.detail
                        Text(b.isExpired ? "Happened \(CountdownFormatter.compact(b, detail: d))"
                                         : "\(CountdownFormatter.days(b))d \(CountdownFormatter.twoDigits(b.hours))"
                                           + (d.showMinutes ? ":\(CountdownFormatter.twoDigits(b.minutes))" : "h")
                                           + (d.effectiveSeconds ? ":\(CountdownFormatter.twoDigits(b.seconds))" : ""))
                            .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(e.targetDate.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(cornerRadius: 20, tint: e.colorToken.color.opacity(0.10))
            } else {
                Text("No countdowns yet").foregroundStyle(.secondary).padding(.vertical, 8)
            }

            if store.events.count > 1 {
                Text("FEATURE").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    ForEach(store.events) { event in
                        Button { store.setFeatured(id: event.id) } label: {
                            HStack {
                                Image(systemName: store.featuredEvent?.id == event.id ? "checkmark" : event.iconName)
                                    .frame(width: 18)
                                Text(event.title).lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                    }
                }
            }

            Divider()
            HStack {
                Button("Open GlassCount") { openMain() }.glassButtonStyle(prominent: true)
                Button { model.store.updateSettings { $0.showDesktopWidget.toggle() }; model.syncDesktopWidget() } label: { Image(systemName: "rectangle.on.rectangle") }
                    .glassButtonStyle().help("Toggle desktop widget").accessibilityLabel("Toggle desktop widget")
                Button("New…") { model.editor = .new; openMain() }.glassButtonStyle()
                Spacer()
                Button { NSApp.activate(ignoringOtherApps: true); openSettings() } label: { Image(systemName: "gearshape") }
                    .glassButtonStyle().accessibilityLabel("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .glassButtonStyle().accessibilityLabel("Quit GlassCount")
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
