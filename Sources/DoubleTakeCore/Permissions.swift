/// Which shortcuts need "Custom actions" (and so the Accessibility permission).
///
/// Without Custom actions DoubleTake only watches the keyboard (Input Monitoring). That's enough to notice
/// taps and combos and to open apps, run scripts and so on. Anything that has to press keys, click menus or
/// hold keys back needs Accessibility, which macOS calls control of the computer.
extension SystemAction {
    public var needsCustomActions: Bool {
        switch self {
        // These work by pressing keys or clicking a menu item.
        case .dictation, .spotlight, .lockScreen, .emojiPicker, .playPause, .nextTrack, .previousTrack,
             .accessibilityShortcuts:
            return true
        // These open apps, run tools or AppleScript; mute and volume fall back to AppleScript's `set volume`.
        case .siri, .missionControl, .appExpose, .showDesktop, .apps, .sleepDisplay, .screenSaver, .screenshot,
             .toggleDarkMode, .toggleMute, .volumeUp, .volumeDown, .hideOthers, .quitFrontApp:
            return false
        }
    }
}

extension Action {
    public var needsCustomActions: Bool {
        switch type {
        case .keystroke, .menuItem: return true
        case .system: return system.needsCustomActions
        case .openApp, .openURL, .shellScript, .appleScript, .runShortcut: return false
        }
    }
}

extension Trigger {
    /// Combos of two or more ordinary keys (J + K) hold the first key back, which needs Custom actions.
    public var needsCustomActions: Bool { kind == .combo && keys.count >= 2 }

    /// Whether the trigger's ordinary key still reaches the front app when DoubleTake can only watch
    /// (⌃⌥T types ⌃⌥T into the front app too, and a double-tapped Esc sends both presses).
    public var passesKeyThroughWithoutCustomActions: Bool {
        switch kind {
        case .tap: return isComplete && !KeyCode.isModifier(keyCode)
        case .combo: return !keys.isEmpty
        }
    }
}

extension Shortcut {
    public var needsCustomActions: Bool { action.needsCustomActions || triggers.contains(where: \.needsCustomActions) }
}
