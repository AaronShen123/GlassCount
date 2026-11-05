import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettingsView().tabItem { Label("Notifications", systemImage: "bell") }
            BackgroundCustomizerView().padding(24).tabItem { Label("Background", systemImage: "photo") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 470)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.store.settings
        Form {
            Picker("Appearance", selection: Binding(get: { s.appearance }, set: { v in model.store.updateSettings { $0.appearance = v } })) {
                ForEach(AppearancePreference.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Section("Countdown") {
                Toggle("Show minutes", isOn: Binding(get: { s.showMinutes }, set: { v in model.store.updateSettings { $0.showMinutes = v } }))
                    .accessibilityIdentifier("showMinutesToggle")
                Toggle("Show seconds", isOn: Binding(get: { s.showSeconds }, set: { v in model.store.updateSettings { $0.showSeconds = v } }))
                    .disabled(!s.showMinutes)
                    .accessibilityIdentifier("showSecondsToggle")
                Text("Days and hours are always shown. Hiding seconds also stops the once-a-second refresh.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Show in menu bar", isOn: Binding(get: { s.showMenuBarItem }, set: { v in model.store.updateSettings { $0.showMenuBarItem = v } }))
            Toggle("Show desktop widget", isOn: Binding(get: { s.showDesktopWidget }, set: { v in model.store.updateSettings { $0.showDesktopWidget = v }; model.syncDesktopWidget() }))
                .accessibilityIdentifier("desktopWidgetToggle")
            Picker("Menu bar shows", selection: Binding(get: { s.menuBarDisplay }, set: { v in model.store.updateSettings { $0.menuBarDisplay = v } })) {
                ForEach(MenuBarDisplay.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .disabled(!s.showMenuBarItem)
        }
        .formStyle(.grouped)
    }
}

private struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let n = model.store.settings.notifications
        Form {
            Section {
                Toggle("Enable reminders", isOn: Binding(get: { n.enabled }, set: { v in Task { await model.setRemindersEnabled(v) } }))
                    .accessibilityIdentifier("remindersToggle")
                statusRow
            }
            Section("Remind me") {
                ForEach(ReminderOffset.allCases.sorted { $0.sortKey < $1.sortKey }, id: \.self) { offset in
                    Toggle(offset.title, isOn: Binding(
                        get: { n.offsets.contains(offset) },
                        set: { on in model.store.updateSettings { if on { $0.notifications.offsets.insert(offset) } else { $0.notifications.offsets.remove(offset) } } }))
                }
            }
            .disabled(!n.enabled)
            Section {
                if let r = model.lastSync, n.enabled {
                    Text("Scheduled reminders: \(r.added + r.unchanged)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.refreshAuthorization() }
    }

    @ViewBuilder private var statusRow: some View {
        switch model.notificationAuth {
        case .denied:
            HStack {
                Label("Notifications are blocked for GlassCount.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Spacer()
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                }
            }
        case .unavailable:
            Label("Notifications require the packaged GlassCount.app.", systemImage: "info.circle").foregroundStyle(.secondary)
        case .notDetermined:
            Text("macOS will ask for permission when you turn this on.").font(.caption).foregroundStyle(.secondary)
        case .authorized:
            Label("Allowed by macOS", systemImage: "checkmark.circle").foregroundStyle(.secondary).font(.caption)
        }
    }
}

private struct AboutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            LabeledContent("Glass rendering", value: GlassSupport.isLiquidGlassActive ? "Liquid Glass" : "Material fallback")
            LabeledContent("Data folder") {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.dataDirectory]) }
            }
            Text(model.dataDirectory.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Everything stays on this Mac. GlassCount makes no network connections.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
