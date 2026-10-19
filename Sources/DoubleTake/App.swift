import AppKit
import SwiftUI

/// DoubleTake runs in the background with no menu bar item or Dock icon. Its window opens
/// when you launch the app (from Applications, Spotlight or `doubletake open`), and it keeps
/// listening after you close the window. Launched at login, it starts hidden.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Posted (distributed) to ask the running copy to show its window.
    static let showWindowNotification = Notification.Name("io.github.chase81698.DoubleTake.showWindow")

    private let launchedInBackground: Bool
    private var state: AppState?
    private var window: NSWindow?

    init(launchedInBackground: Bool) {
        self.launchedInBackground = launchedInBackground
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        AdminScripts.canPromptForApproval = true
        if !launchedInBackground, Installer.offerMoveIfNeeded() { return }

        let state = AppState()
        self.state = state
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showWindowNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showWindow() }
        }
        if !launchedInBackground || state.needsAttention {
            showWindow()
        }
        if state.settings.checkForUpdatesOnLaunch {
            Task { await UpdateController.shared.checkOnLaunch() }
        }
    }

    /// Double-clicking the app while it's already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func showWindow() {
        guard let state else { return }
        if window == nil {
            let hosting = NSHostingController(rootView: MainView().environment(state))
            hosting.sizingOptions = [.minSize]
            let w = NSWindow(contentViewController: hosting)
            w.title = "DoubleTake"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 860, height: 600))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("DoubleTakeMain")
            window = w
        }
        // Show in the Dock and app switcher only while the window is open.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        state?.cancelRecording()
        NSApp.setActivationPolicy(.accessory)
    }

    /// ⌘Q from the menu asks first, since quitting stops every shortcut.
    /// (Quit requests from the CLI or installer skip this.)
    @objc private func confirmQuit(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Quit DoubleTake?"
        alert.informativeText = "Your shortcuts stop working until you open DoubleTake again. Closing the window keeps them running."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        } else {
            window?.close()
        }
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "DoubleTake")
        app.addItem(withTitle: "About DoubleTake", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide DoubleTake", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        let quit = app.addItem(withTitle: "Quit DoubleTake…", action: #selector(confirmQuit(_:)), keyEquivalent: "q")
        quit.target = self
        main.addItem(withTitle: "DoubleTake", action: nil, keyEquivalent: "").submenu = app

        // Text fields need these for copy, paste and undo to work.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        return main
    }
}
