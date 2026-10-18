import AppKit
import DoubleTakeCore
import os

private let log = Logger(subsystem: "io.github.chase81698.DoubleTake", category: "actions")

/// Performs a shortcut's action.
@MainActor
enum ActionRunner {
    /// Runs `action`. `completion` receives nil on success or an error message.
    static func run(_ action: Action, completion: ((String?) -> Void)? = nil) {
        let done = completion ?? { error in
            guard let error else { return }
            log.error("Action failed: \(error, privacy: .public)")
            NSSound.beep()
        }
        switch action.type {
        case .system:
            runSystem(action.system, done)
        case .openApp:
            openApp(action.target, toggle: action.toggleApp, done)
        case .openURL:
            openURL(action.target, done)
        case .shellScript:
            runProcess("/bin/zsh", ["-lc", action.script], done)
        case .appleScript:
            runProcess("/usr/bin/osascript", ["-e", action.script], done)
        case .runShortcut:
            runProcess("/usr/bin/shortcuts", ["run", action.target], done)
        case .keystroke:
            guard let k = action.keystroke else { return done("No keystroke recorded.") }
            SyntheticInput.keystroke(k)
            done(nil)
        case .menuItem:
            let path = action.target.split(separator: ">").map { String($0) }
            done(MenuClicker.click(path: path) ? nil : "Couldn't find “\(action.target)” in the front app's menus.")
        }
    }

    private static func runSystem(_ action: SystemAction, _ done: @escaping (String?) -> Void) {
        let missionControl = "/System/Applications/Mission Control.app"
        switch action {
        case .dictation:
            done(MenuClicker.click(path: ["Start Dictation"]) ? nil : "The front app has no Start Dictation menu item.")
        case .siri:
            openApp("/System/Applications/Siri.app", toggle: false, done)
        case .spotlight:
            SyntheticInput.keystroke(Keystroke(modifiers: .command, keyCode: KeyCode.space))
            done(nil)
        case .missionControl:
            openApp(missionControl, toggle: false, done)
        case .appExpose:
            runProcess("\(missionControl)/Contents/MacOS/Mission Control", ["2"], done)
        case .showDesktop:
            runProcess("\(missionControl)/Contents/MacOS/Mission Control", ["1"], done)
        case .apps:
            openApp("/System/Applications/Apps.app", toggle: false, done)
        case .lockScreen:
            SyntheticInput.keystroke(Keystroke(modifiers: [.control, .command], keyCode: 12)) // ⌃⌘Q
            done(nil)
        case .sleepDisplay:
            runProcess("/usr/bin/pmset", ["displaysleepnow"], done)
        case .screenSaver:
            openApp("/System/Library/CoreServices/ScreenSaverEngine.app", toggle: false, done)
        case .screenshot:
            openApp("/System/Applications/Utilities/Screenshot.app", toggle: false, done)
        case .emojiPicker:
            SyntheticInput.keystroke(Keystroke(modifiers: [.control, .command], keyCode: KeyCode.space))
            done(nil)
        case .toggleDarkMode:
            runProcess("/usr/bin/osascript", ["-e",
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"], done)
        case .toggleMute:
            SyntheticInput.mediaKey(7)
            done(nil)
        case .volumeUp:
            SyntheticInput.mediaKey(0)
            done(nil)
        case .volumeDown:
            SyntheticInput.mediaKey(1)
            done(nil)
        case .playPause:
            SyntheticInput.mediaKey(16)
            done(nil)
        case .nextTrack:
            SyntheticInput.mediaKey(17)
            done(nil)
        case .previousTrack:
            SyntheticInput.mediaKey(18)
            done(nil)
        case .accessibilityShortcuts:
            SyntheticInput.keystroke(Keystroke(modifiers: [.option, .command], keyCode: 96)) // ⌥⌘F5
            done(nil)
        case .hideOthers:
            let front = NSWorkspace.shared.frontmostApplication
            for app in NSWorkspace.shared.runningApplications
            where app != front && app.activationPolicy == .regular {
                app.hide()
            }
            done(nil)
        case .quitFrontApp:
            guard let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current,
                  front.bundleIdentifier != "com.apple.finder" else { return done("Nothing to quit.") }
            front.terminate()
            done(nil)
        }
    }

    private static func openApp(_ path: String, toggle: Bool, _ done: @escaping (String?) -> Void) {
        guard !path.isEmpty else { return done("No app chosen.") }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if toggle, let front = NSWorkspace.shared.frontmostApplication,
           front.bundleURL?.standardizedFileURL == url.standardizedFileURL {
            front.hide()
            return done(nil)
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async { done(error?.localizedDescription) }
        }
    }

    private static func openURL(_ target: String, _ done: @escaping (String?) -> Void) {
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL?
        if t.hasPrefix("/") || t.hasPrefix("~") {
            url = URL(fileURLWithPath: (t as NSString).expandingTildeInPath)
        } else if t.contains("://") || t.hasPrefix("mailto:") {
            url = URL(string: t)
        } else {
            url = URL(string: "https://" + t)
        }
        guard let url, !t.isEmpty else { return done("Not a valid URL or path.") }
        done(NSWorkspace.shared.open(url) ? nil : "Couldn't open \(t).")
    }

    private static func runProcess(_ path: String, _ arguments: [String], _ done: @escaping (String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let buffer = OutputBuffer()
        errors.fileHandleForReading.readabilityHandler = { buffer.append($0.availableData) }
        process.terminationHandler = { p in
            errors.fileHandleForReading.readabilityHandler = nil
            buffer.append(errors.fileHandleForReading.readDataToEndOfFile())
            let status = p.terminationStatus
            let message = buffer.text.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                done(status == 0 ? nil : (message.isEmpty ? "Exited with status \(status)." : message))
            }
        }
        do {
            try process.run()
        } catch {
            done(error.localizedDescription)
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Posts keyboard events on the user's behalf.
enum SyntheticInput {
    /// Stamped on every event we post so our own tap ignores it.
    static let marker: Int64 = 0x4454_4B45

    static func keystroke(_ k: Keystroke) {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = marker
        let flags = cgFlags(k.modifiers)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: k.keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// Presses a media/system key (NX_KEYTYPE_* code), such as play/pause or mute.
    static func mediaKey(_ key: Int) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: (key << 16) | (state << 8), data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static func cgFlags(_ m: Modifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if m.contains(.control) { flags.insert(.maskControl) }
        if m.contains(.option) { flags.insert(.maskAlternate) }
        if m.contains(.shift) { flags.insert(.maskShift) }
        if m.contains(.command) { flags.insert(.maskCommand) }
        if m.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}

/// Finds and presses a menu item in the frontmost app through the Accessibility API.
enum MenuClicker {
    /// `path` is either a full path ("Edit", "Start Dictation") or just an item's title.
    static func click(path: [String]) -> Bool {
        let targets = path.map(normalize).filter { !$0.isEmpty }
        guard !targets.isEmpty, let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let menuBar = element(axApp, kAXMenuBarAttribute) else { return false }
        let found = targets.count == 1 ? search(menuBar, for: targets[0], depth: 0) : walk(menuBar, targets)
        guard let item = found else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private static func walk(_ menuBar: AXUIElement, _ targets: [String]) -> AXUIElement? {
        var current = menuBar
        for target in targets {
            let candidates = items(of: current)
            guard let next = candidates.first(where: { title($0) == target })
                ?? candidates.first(where: { title($0).hasPrefix(target) }) else { return nil }
            current = next
        }
        return current
    }

    private static func search(_ element: AXUIElement, for target: String, depth: Int) -> AXUIElement? {
        for child in items(of: element) {
            let t = title(child)
            if depth > 0, t == target || t.hasPrefix(target) { return child }
            if depth < 4, let found = search(child, for: target, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Menu bar items and menu items keep their entries inside a single AXMenu child.
    private static func items(of element: AXUIElement) -> [AXUIElement] {
        let children = elements(element, kAXChildrenAttribute)
        if string(element, kAXRoleAttribute) == kAXMenuBarRole { return children }
        guard let menu = children.first(where: { string($0, kAXRoleAttribute) == kAXMenuRole }) else { return [] }
        return elements(menu, kAXChildrenAttribute)
    }

    private static func title(_ element: AXUIElement) -> String {
        normalize(string(element, kAXTitleAttribute) ?? "")
    }

    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        value(element, attribute) as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }
}
