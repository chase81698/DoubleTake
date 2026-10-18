import AppKit
import SwiftUI

struct DoubleTakeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(state)
        } label: {
            Image(systemName: state.settings.isEnabled && state.isTrusted ? "hand.tap.fill" : "hand.tap")
        }

        Window("DoubleTake", id: "main") {
            MainView()
                .environment(state)
        }
        .defaultLaunchBehavior(state.needsAttention ? .presented : .suppressed)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 600)
    }
}

struct MenuContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state
        Toggle("DoubleTake Enabled", isOn: $state.settings.isEnabled)
        if !state.isTrusted {
            Button("Grant Accessibility Access…") { state.requestPermission() }
        }
        Divider()
        let active = state.shortcuts.filter(\.enabled)
        if active.isEmpty {
            Text("No shortcuts enabled")
        } else {
            Section("Run Now") {
                ForEach(active) { s in
                    Button("\(s.name)  —  \(KeyNames.summary(s))") { ActionRunner.run(s.action) }
                }
            }
        }
        Divider()
        Button("Open DoubleTake…") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Button("Quit DoubleTake") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Installer.offerMoveIfNeeded()
    }
}
