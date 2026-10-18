import DoubleTakeCore
import Foundation

/// Ready-made shortcuts, including the double-tap options macOS used to offer.
enum Presets {
    struct Preset: Identifiable {
        let title: String
        let make: () -> Shortcut
        var id: String { title }
    }

    struct Group: Identifiable {
        let title: String
        let presets: [Preset]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Classic Dictation", presets: [
            preset("Press fn Twice", "Dictation", .tap(KeyCode.function), .dictation),
            preset("Press Control Twice", "Dictation", .tap(KeyCode.control, eitherSide: true), .dictation),
            preset("Press Left ⌘ Twice", "Dictation", .tap(KeyCode.command), .dictation),
            preset("Press Right ⌘ Twice", "Dictation", .tap(KeyCode.rightCommand), .dictation),
            preset("Press Either ⌘ Twice", "Dictation", .tap(KeyCode.command, eitherSide: true), .dictation),
        ]),
        Group(title: "Classic Siri", presets: [
            preset("Press Left ⌘ Twice", "Siri", .tap(KeyCode.command), .siri),
            preset("Press Right ⌘ Twice", "Siri", .tap(KeyCode.rightCommand), .siri),
            preset("Press Either ⌘ Twice", "Siri", .tap(KeyCode.command, eitherSide: true), .siri),
        ]),
        Group(title: "Popular", presets: [
            preset("Double-tap ⌥ → Spotlight", "Spotlight", .tap(KeyCode.option, eitherSide: true), .spotlight),
            preset("Double-tap ⌃ → Mission Control", "Mission Control", .tap(KeyCode.control, eitherSide: true), .missionControl),
            preset("Double-tap Right ⇧ → Emoji & Symbols", "Emoji & Symbols", .tap(KeyCode.rightShift), .emojiPicker),
            preset("Double-tap Esc → Show Desktop", "Show Desktop", .tap(KeyCode.escape), .showDesktop),
            preset("Triple-tap Right ⌥ → Lock Screen", "Lock Screen", .tap(KeyCode.rightOption, count: 3), .lockScreen),
            preset("⌃ + ⌥ Together → Play / Pause", "Play / Pause", .combo([.control, .option], []), .playPause),
            Preset(title: "⌃⌥T → Open Terminal") {
                var action = Action()
                action.type = .openApp
                action.target = "/System/Applications/Utilities/Terminal.app"
                action.toggleApp = true
                return Shortcut(name: "Terminal", triggers: [.combo([.control, .option], [17])], action: action)
            },
        ]),
    ]

    /// What a fresh install starts with.
    static func defaults() -> [Shortcut] {
        var siri = groups[1].presets[1].make()
        siri.enabled = false
        var spotlight = groups[2].presets[0].make()
        spotlight.enabled = false
        var terminal = groups[2].presets[6].make()
        terminal.enabled = false
        return [groups[0].presets[0].make(), siri, spotlight, terminal]
    }

    private static func preset(_ title: String, _ name: String, _ trigger: Trigger, _ action: SystemAction) -> Preset {
        Preset(title: title) {
            var t = trigger
            t.id = UUID()
            return Shortcut(name: name, triggers: [t], action: .system(action))
        }
    }
}
