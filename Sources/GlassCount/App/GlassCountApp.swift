import SwiftUI

@main
struct GlassCountApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let m = AppModel(options: LaunchOptions.parse(CommandLine.arguments))
        _model = State(initialValue: m)
        AppDelegate.model = m
    }

    var body: some Scene {
        Window("GlassCount", id: "main") {
            MainWindow()
                .environment(model)
                .preferredColorScheme(model.store.settings.appearance.colorScheme)
                .frame(minWidth: 640, minHeight: 520)
        }
        .defaultSize(width: 1000, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Countdown") { model.editor = .new }.keyboardShortcut("n")
            }
        }

        Window("Desktop Widget", id: "widget") {
            DesktopWidgetView()
                .environment(model)
                .preferredColorScheme(model.store.settings.appearance.colorScheme)
        }
        .windowStyle(.plain)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra(isInserted: Binding(
            get: { model.store.settings.showMenuBarItem },
            set: { v in
                guard v != model.store.settings.showMenuBarItem else { return }
                model.store.updateSettings { $0.showMenuBarItem = v }
            })) {
            MenuBarContent()
                .environment(model)
                .preferredColorScheme(model.store.settings.appearance.colorScheme)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(model.store.settings.appearance.colorScheme)
        }
    }
}
