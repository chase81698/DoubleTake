import Carbon.HIToolbox
import DoubleTakeCore

/// Human-readable names for keys, triggers and actions.
enum KeyNames {
    private static let special: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 117: "Forward Delete", 76: "Enter",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        114: "Help", 57: "Caps Lock",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
        65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Clear", 75: "Keypad /", 78: "Keypad -",
        81: "Keypad =", 82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4",
        87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
        KeyCode.command: "Left ⌘", KeyCode.rightCommand: "Right ⌘",
        KeyCode.shift: "Left ⇧", KeyCode.rightShift: "Right ⇧",
        KeyCode.option: "Left ⌥", KeyCode.rightOption: "Right ⌥",
        KeyCode.control: "Left ⌃", KeyCode.rightControl: "Right ⌃",
        KeyCode.function: "fn",
    ]

    static func name(_ keyCode: UInt16) -> String {
        if let s = special[keyCode] { return s }
        if let c = character(for: keyCode), !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return c.uppercased()
        }
        return "Key \(keyCode)"
    }

    static func familyName(_ family: Modifiers) -> String {
        switch family {
        case .command: return "⌘ Command"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .shift: return "⇧ Shift"
        default: return "fn"
        }
    }

    /// The name of a tap trigger's key, e.g. "Right ⌘" or "⌘ Command (either side)".
    static func tapKeyName(_ t: Trigger) -> String {
        if t.eitherSide, KeyCode.hasSides(t.keyCode), let family = KeyCode.family(of: t.keyCode) {
            return familyName(family)
        }
        return name(t.keyCode)
    }

    static func comboName(_ modifiers: Modifiers, _ keys: [UInt16]) -> String {
        let keyNames = keys.map(name)
        if keyNames.isEmpty { return modifiers.symbols.trimmingCharacters(in: .whitespaces) + " together" }
        if keyNames.count == 1 { return modifiers.symbols + keyNames[0] }
        let joined = keyNames.joined(separator: " + ")
        return modifiers.isEmpty ? joined : modifiers.symbols + " " + joined
    }

    static func summary(_ t: Trigger) -> String {
        guard t.isComplete else { return "Not set" }
        switch t.kind {
        case .tap: return "\(t.tapCount == 3 ? "Triple" : "Double")-tap \(tapKeyName(t))"
        case .combo: return comboName(t.modifiers, t.keys)
        }
    }

    static func summary(_ s: Shortcut) -> String {
        let triggers = s.triggers.filter(\.isComplete)
        guard !triggers.isEmpty else { return "No trigger" }
        return triggers.map(summary).joined(separator: ", ")
    }

    static func keystrokeName(_ k: Keystroke?) -> String? {
        guard let k else { return nil }
        return k.modifiers.symbols + name(k.keyCode)
    }

    /// The character a key types in the current keyboard layout.
    private static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
            ?? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

extension ActionType {
    var title: String {
        switch self {
        case .system: return "Built-in Action"
        case .openApp: return "Open App"
        case .openURL: return "Open URL or File"
        case .shellScript: return "Run Shell Script"
        case .appleScript: return "Run AppleScript"
        case .runShortcut: return "Run Shortcut"
        case .keystroke: return "Send Keystroke"
        case .menuItem: return "Click Menu Item"
        }
    }
}

extension SystemAction {
    var title: String {
        switch self {
        case .dictation: return "Start Dictation"
        case .siri: return "Siri"
        case .spotlight: return "Spotlight"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .apps: return "Apps (Launchpad)"
        case .lockScreen: return "Lock Screen"
        case .sleepDisplay: return "Sleep Display"
        case .screenSaver: return "Start Screen Saver"
        case .screenshot: return "Screenshot"
        case .emojiPicker: return "Emoji & Symbols"
        case .toggleDarkMode: return "Toggle Dark Mode"
        case .toggleMute: return "Mute / Unmute"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .accessibilityShortcuts: return "Accessibility Shortcuts"
        case .hideOthers: return "Hide Other Apps"
        case .quitFrontApp: return "Quit Front App"
        }
    }

    static let groups: [(title: String, actions: [SystemAction])] = [
        ("Voice", [.dictation, .siri]),
        ("Windows & Desktop", [.spotlight, .missionControl, .appExpose, .showDesktop, .apps, .hideOthers, .quitFrontApp]),
        ("System", [.lockScreen, .sleepDisplay, .screenSaver, .screenshot, .emojiPicker, .toggleDarkMode, .accessibilityShortcuts]),
        ("Media", [.playPause, .nextTrack, .previousTrack, .toggleMute, .volumeUp, .volumeDown]),
    ]
}

extension Action {
    var summary: String {
        switch type {
        case .system: return system.title
        case .openApp:
            let name = (target as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            return name.isEmpty ? "Open app" : "Open \(name)"
        case .openURL: return target.isEmpty ? "Open URL" : "Open \(target)"
        case .shellScript: return "Run shell script"
        case .appleScript: return "Run AppleScript"
        case .runShortcut: return target.isEmpty ? "Run Shortcut" : "Run “\(target)”"
        case .keystroke: return KeyNames.keystrokeName(keystroke).map { "Press \($0)" } ?? "Send keystroke"
        case .menuItem: return target.isEmpty ? "Click menu item" : "Click \(target)"
        }
    }
}
