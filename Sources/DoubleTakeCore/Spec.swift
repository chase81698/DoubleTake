import Foundation

/// Plain-text names for keys, triggers and keystrokes, used by the command line.
///
/// Triggers:   double:fn   triple:right-cmd   double:cmd (either side)   double:esc
///             ctrl+opt+t  cmd+shift+k  j+k  ctrl+opt (modifiers alone, pressed together)
/// Keystrokes: cmd+shift+t   ctrl+cmd+q   f5
public enum Spec {
    public struct ParseError: Error, CustomStringConvertible {
        public let description: String
        init(_ description: String) { self.description = description }
    }

    /// Key names on a US (ANSI) keyboard layout, first name is canonical.
    public static let keys: [(names: [String], code: UInt16)] = {
        var table: [(names: [String], code: UInt16)] = [
            (["a"], 0), (["s"], 1), (["d"], 2), (["f"], 3), (["h"], 4), (["g"], 5), (["z"], 6), (["x"], 7),
            (["c"], 8), (["v"], 9), (["b"], 11), (["q"], 12), (["w"], 13), (["e"], 14), (["r"], 15),
            (["y"], 16), (["t"], 17), (["1"], 18), (["2"], 19), (["3"], 20), (["4"], 21), (["6"], 22),
            (["5"], 23), (["=", "equal"], 24), (["9"], 25), (["7"], 26), (["-", "minus"], 27), (["8"], 28),
            (["0"], 29), (["]", "right-bracket"], 30), (["o"], 31), (["u"], 32), (["[", "left-bracket"], 33),
            (["i"], 34), (["p"], 35), (["return"], 36), (["l"], 37), (["j"], 38), (["'", "quote"], 39),
            (["k"], 40), ([";", "semicolon"], 41), (["\\", "backslash"], 42), ([",", "comma"], 43),
            (["/", "slash"], 44), (["n"], 45), (["m"], 46), ([".", "period"], 47), (["tab"], 48),
            (["space"], 49), (["`", "grave", "backtick"], 50), (["delete", "backspace"], 51),
            (["esc", "escape"], 53), (["enter", "keypad-enter"], 76), (["forward-delete"], 117),
            (["home"], 115), (["end"], 119), (["page-up"], 116), (["page-down"], 121), (["help"], 114),
            (["left"], 123), (["right"], 124), (["down"], 125), (["up"], 126),
            (["left-cmd", "cmd", "command", "left-command"], KeyCode.command),
            (["right-cmd", "right-command"], KeyCode.rightCommand),
            (["left-shift", "shift"], KeyCode.shift), (["right-shift"], KeyCode.rightShift),
            (["left-opt", "opt", "option", "alt", "left-option", "left-alt"], KeyCode.option),
            (["right-opt", "right-option", "right-alt"], KeyCode.rightOption),
            (["left-ctrl", "ctrl", "control", "left-control"], KeyCode.control),
            (["right-ctrl", "right-control"], KeyCode.rightControl),
            (["fn", "globe", "function"], KeyCode.function),
        ]
        let fKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        for (i, code) in fKeys.enumerated() { table.append((["f\(i + 1)"], code)) }
        for (i, code) in [82, 83, 84, 85, 86, 87, 88, 89, 91, 92].enumerated() {
            table.append((["keypad-\(i)"], UInt16(code)))
        }
        return table
    }()

    /// Generic modifier names, which mean "either side".
    private static let familyNames: [String: Modifiers] = [
        "cmd": .command, "command": .command, "⌘": .command,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "ctrl": .control, "control": .control, "⌃": .control,
        "shift": .shift, "⇧": .shift,
        "fn": .function, "globe": .function, "function": .function,
    ]

    public static func code(for name: String) -> UInt16? {
        let n = name.lowercased()
        return keys.first { $0.names.contains(n) }?.code
    }

    public static func name(for code: UInt16) -> String {
        keys.first { $0.code == code }?.names[0] ?? "key\(code)"
    }

    private static func keyCode(_ name: String) throws -> UInt16 {
        if let code = code(for: name) { return code }
        if name.hasPrefix("key"), let raw = UInt16(name.dropFirst(3)) { return raw }
        throw ParseError("Unknown key “\(name)”. Run `doubletake keys` to see key names.")
    }

    private static func familyName(_ m: Modifiers) -> String {
        switch m {
        case .command: return "cmd"
        case .option: return "opt"
        case .control: return "ctrl"
        case .shift: return "shift"
        default: return "fn"
        }
    }

    private static func modifierParts(_ m: Modifiers) -> [String] {
        [Modifiers.command, .control, .option, .shift, .function].filter(m.contains).map(familyName)
    }

    // MARK: - Triggers

    public static func parseTrigger(_ spec: String) throws -> Trigger {
        let s = spec.trimmingCharacters(in: .whitespaces).lowercased()
        for (prefix, count) in [("double:", 2), ("triple:", 3)] where s.hasPrefix(prefix) {
            let key = String(s.dropFirst(prefix.count))
            if let family = familyNames[key], family != .function {
                // A bare modifier name means either side.
                let code = try keyCode(key)
                return .tap(code, count: count, eitherSide: true)
            }
            return .tap(try keyCode(key), count: count)
        }
        guard !s.contains(":") else {
            throw ParseError("Unknown trigger “\(spec)”. Taps start with double: or triple:, combos look like ctrl+opt+t.")
        }
        var modifiers: Modifiers = []
        var keys: [UInt16] = []
        for part in s.split(separator: "+").map(String.init) {
            if let family = familyNames[part] {
                modifiers.insert(family)
            } else {
                let code = try keyCode(part)
                if let family = KeyCode.family(of: code) {
                    modifiers.insert(family)
                } else if !keys.contains(code) {
                    keys.append(code)
                }
            }
        }
        let trigger = Trigger.combo(modifiers, keys)
        guard trigger.isComplete else {
            throw ParseError("“\(spec)” needs a key, or at least two modifiers. Use double:\(s) for a double tap.")
        }
        return trigger
    }

    public static func format(_ t: Trigger) -> String {
        switch t.kind {
        case .tap:
            let prefix = t.tapCount == 3 ? "triple:" : "double:"
            guard t.isComplete else { return prefix + "?" }
            if t.eitherSide, KeyCode.hasSides(t.keyCode), let family = KeyCode.family(of: t.keyCode) {
                return prefix + familyName(family)
            }
            return prefix + name(for: t.keyCode)
        case .combo:
            return (modifierParts(t.modifiers) + t.keys.map(name)).joined(separator: "+")
        }
    }

    // MARK: - Keystrokes

    public static func parseKeystroke(_ spec: String) throws -> Keystroke {
        var modifiers: Modifiers = []
        var key: UInt16?
        for part in spec.trimmingCharacters(in: .whitespaces).lowercased().split(separator: "+").map(String.init) {
            if let family = familyNames[part] {
                modifiers.insert(family)
            } else {
                guard key == nil else { throw ParseError("A keystroke has one key plus modifiers, like cmd+shift+t.") }
                key = try keyCode(part)
            }
        }
        guard let key else { throw ParseError("“\(spec)” has no key. Example: cmd+shift+t.") }
        return Keystroke(modifiers: modifiers, keyCode: key)
    }

    public static func format(_ k: Keystroke) -> String {
        (modifierParts(k.modifiers) + [name(for: k.keyCode)]).joined(separator: "+")
    }
}
