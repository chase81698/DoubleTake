import Foundation

/// Modifier key families, independent of which side of the keyboard was used.
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let function = Modifiers(rawValue: 1 << 0)
    public static let control = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
    public static let command = Modifiers(rawValue: 1 << 4)

    public var count: Int { rawValue.nonzeroBitCount }

    /// Symbols in the order macOS displays them, e.g. "⌃⌥⇧⌘".
    public var symbols: String {
        var s = ""
        if contains(.function) { s += "fn " }
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// macOS virtual key codes for the modifier keys.
public enum KeyCode {
    public static let command: UInt16 = 55
    public static let rightCommand: UInt16 = 54
    public static let shift: UInt16 = 56
    public static let rightShift: UInt16 = 60
    public static let option: UInt16 = 58
    public static let rightOption: UInt16 = 61
    public static let control: UInt16 = 59
    public static let rightControl: UInt16 = 62
    public static let function: UInt16 = 63
    public static let capsLock: UInt16 = 57
    /// Placeholder for a trigger that has not been recorded yet.
    public static let unset: UInt16 = .max

    public static let space: UInt16 = 49
    public static let escape: UInt16 = 53

    /// The modifier family a key belongs to, or nil for ordinary keys (and Caps Lock).
    public static func family(of keyCode: UInt16) -> Modifiers? {
        switch keyCode {
        case command, rightCommand: return .command
        case shift, rightShift: return .shift
        case option, rightOption: return .option
        case control, rightControl: return .control
        case function: return .function
        default: return nil
        }
    }

    public static func isModifier(_ keyCode: UInt16) -> Bool { family(of: keyCode) != nil }

    /// Whether the key has distinct left and right variants.
    public static func hasSides(_ keyCode: UInt16) -> Bool {
        guard let f = family(of: keyCode) else { return false }
        return f != .function
    }
}

public enum TriggerKind: String, Codable, CaseIterable, Sendable {
    /// Tap one key two or three times in quick succession.
    case tap
    /// Press several keys together (modifiers plus zero or more keys).
    case combo
}

public struct Trigger: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: TriggerKind = .tap

    // .tap
    public var keyCode: UInt16 = KeyCode.unset
    /// For modifier keys: accept the left or right key, not just the recorded one.
    public var eitherSide = false
    public var tapCount = 2

    // .combo
    public var modifiers: Modifiers = []
    public var keys: [UInt16] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(TriggerKind.self, forKey: .kind) ?? .tap
        keyCode = try c.decodeIfPresent(UInt16.self, forKey: .keyCode) ?? KeyCode.unset
        eitherSide = try c.decodeIfPresent(Bool.self, forKey: .eitherSide) ?? false
        tapCount = try c.decodeIfPresent(Int.self, forKey: .tapCount) ?? 2
        modifiers = try c.decodeIfPresent(Modifiers.self, forKey: .modifiers) ?? []
        keys = try c.decodeIfPresent([UInt16].self, forKey: .keys) ?? []
    }

    public static func tap(_ keyCode: UInt16, count: Int = 2, eitherSide: Bool = false) -> Trigger {
        var t = Trigger()
        t.kind = .tap
        t.keyCode = keyCode
        t.tapCount = count
        t.eitherSide = eitherSide
        return t
    }

    public static func combo(_ modifiers: Modifiers, _ keys: [UInt16]) -> Trigger {
        var t = Trigger()
        t.kind = .combo
        t.modifiers = modifiers
        t.keys = keys
        return t
    }

    /// Whether the trigger has been given keys yet.
    public var isComplete: Bool {
        switch kind {
        case .tap: return keyCode != KeyCode.unset
        case .combo: return !keys.isEmpty || modifiers.count >= 2
        }
    }

    /// Whether two triggers would respond to the same input.
    public func overlaps(_ other: Trigger) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .tap:
            guard tapCount == other.tapCount else { return false }
            if keyCode == other.keyCode { return true }
            guard let f = KeyCode.family(of: keyCode), f == KeyCode.family(of: other.keyCode) else { return false }
            return eitherSide || other.eitherSide
        case .combo:
            return modifiers == other.modifiers && Set(keys) == Set(other.keys)
        }
    }
}

public enum ActionType: String, Codable, CaseIterable, Sendable {
    case system, openApp, openURL, shellScript, appleScript, runShortcut, keystroke, menuItem
}

public enum SystemAction: String, Codable, CaseIterable, Sendable {
    case dictation, siri, spotlight, missionControl, appExpose, showDesktop, apps
    case lockScreen, sleepDisplay, screenSaver, screenshot, emojiPicker
    case toggleDarkMode, toggleMute, volumeUp, volumeDown, playPause, nextTrack, previousTrack
    case accessibilityShortcuts, hideOthers, quitFrontApp
}

public struct Keystroke: Codable, Hashable, Sendable {
    public var modifiers: Modifiers
    public var keyCode: UInt16
    public init(modifiers: Modifiers, keyCode: UInt16) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }
}

public struct Action: Codable, Hashable, Sendable {
    public var type: ActionType = .system
    public var system: SystemAction = .dictation
    /// App path, URL / file path, Shortcut name or menu path, depending on `type`.
    public var target = ""
    public var script = ""
    public var keystroke: Keystroke?
    /// For `.openApp`: hide the app instead if it is already frontmost.
    public var toggleApp = false
    /// For `.shellScript`: run as root. The user approves the script once and it then runs
    /// without a password until its text changes.
    public var runAsAdmin = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(ActionType.self, forKey: .type) ?? .system
        system = try c.decodeIfPresent(SystemAction.self, forKey: .system) ?? .dictation
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? ""
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        keystroke = try c.decodeIfPresent(Keystroke.self, forKey: .keystroke)
        toggleApp = try c.decodeIfPresent(Bool.self, forKey: .toggleApp) ?? false
        runAsAdmin = try c.decodeIfPresent(Bool.self, forKey: .runAsAdmin) ?? false
    }

    public static func system(_ s: SystemAction) -> Action {
        var a = Action()
        a.type = .system
        a.system = s
        return a
    }
}

public struct Shortcut: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var enabled = true
    public var triggers: [Trigger]
    public var action: Action

    public init(name: String, enabled: Bool = true, triggers: [Trigger], action: Action) {
        self.name = name
        self.enabled = enabled
        self.triggers = triggers
        self.action = action
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        triggers = try c.decodeIfPresent([Trigger].self, forKey: .triggers) ?? []
        action = try c.decodeIfPresent(Action.self, forKey: .action) ?? Action()
    }

    /// The first eight characters of the id, enough to address it from the command line.
    public var shortID: String { String(id.uuidString.prefix(8)).lowercased() }
}
