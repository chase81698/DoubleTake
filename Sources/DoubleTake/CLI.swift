import AppKit
import DoubleTakeCore

/// The `doubletake` command line tool. It edits the same config file the app uses;
/// the running app notices and reloads within a moment.
@MainActor
enum CLI {
    /// Whether this launch is a CLI invocation rather than the app starting.
    static func shouldRun(_ arguments: [String]) -> Bool {
        let invokedAs = (arguments.first.map { ($0 as NSString).lastPathComponent }) ?? ""
        let args = userArguments(arguments)
        // Any argument means a command (unknown ones get an error, not a second app).
        return invokedAs == "doubletake" || !args.isEmpty
    }

    /// Drops the flags macOS and Xcode add when launching an app.
    private static func userArguments(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var skipNext = false
        for arg in arguments.dropFirst() {
            if skipNext { skipNext = false; continue }
            if arg.hasPrefix("-psn_") || arg == Entry.backgroundFlag { continue }
            if arg.hasPrefix("-NS") || arg.hasPrefix("-Apple") { skipNext = true; continue }
            result.append(arg)
        }
        return result
    }

    static func run(_ arguments: [String]) -> Int32 {
        let args = Arguments(userArguments(arguments))
        let command = args.positional.isEmpty ? "help" : args.positional.removeFirst()
        do {
            try dispatch(command, args)
            return 0
        } catch let error as CLIError {
            printError(error.message)
            return 1
        } catch let error as Spec.ParseError {
            printError(error.description)
            return 1
        } catch {
            printError(error.localizedDescription)
            return 1
        }
    }

    private static func dispatch(_ command: String, _ args: Arguments) throws {
        switch command {
        case "help", "--help", "-h":
            print(args.flag("llm") ? Help.llm : Help.short)
        case "version", "--version":
            print(version)
        case "list":
            try list(args)
        case "show":
            let config = try loadConfig()
            let s = config.shortcuts[try find(args.positional.first, in: config)]
            if args.flag("json") { try printJSON(s) } else { printDetail(s) }
        case "add":
            try add(args)
        case "edit":
            try edit(args)
        case "remove", "delete":
            try mutate { config in
                let i = try find(args.positional.first, in: config)
                let removed = config.shortcuts.remove(at: i)
                return "Removed “\(removed.name)”."
            }
        case "enable", "disable":
            let on = command == "enable"
            try mutate { config in
                let i = try find(args.positional.first, in: config)
                config.shortcuts[i].enabled = on
                return "\(on ? "Enabled" : "Disabled") “\(config.shortcuts[i].name)”."
            }
        case "run":
            let config = try loadConfig()
            let s = config.shortcuts[try find(args.positional.first, in: config)]
            try runAction(s.action)
            print("Ran “\(s.name)”.")
        case "presets":
            try presets(args)
        case "add-preset":
            try addPreset(args)
        case "actions":
            try actions(args)
        case "keys":
            try keys(args)
        case "settings":
            try settings(args)
        case "status":
            try status(args)
        case "export":
            let data = try loadConfig().encoded()
            if let path = args.positional.first {
                try data.write(to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
                print("Exported to \(path).")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
        case "import":
            try importConfig(args)
        case "open":
            if NSRunningApplication.runningApplications(withBundleIdentifier: Installer.bundleID).isEmpty {
                guard let app = Installer.appBundleURL ?? Installer.installedAppURL else {
                    throw CLIError("DoubleTake.app isn't installed. Run install.sh first.")
                }
                NSWorkspace.shared.open(app)
            } else {
                DistributedNotificationCenter.default().postNotificationName(
                    AppDelegate.showWindowNotification, object: nil, userInfo: nil, deliverImmediately: true)
            }
        case "quit":
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: Installer.bundleID)
            running.forEach { $0.terminate() }
            print(running.isEmpty ? "DoubleTake isn't running." : "Quit DoubleTake.")
        case "install-cli":
            try Installer.installCLI()
            print("Installed \(Installer.cliPath).")
        case "uninstall-cli":
            try Installer.uninstallCLI()
            print("Removed \(Installer.cliPath).")
        default:
            throw CLIError("Unknown command “\(command)”. Run `doubletake help`.")
        }
        let unused = args.unusedOptions
        if !unused.isEmpty {
            printError("warning: ignored option(s): \(unused.map { "--\($0)" }.joined(separator: ", "))")
        }
    }

    static var version: String {
        // Read the plist directly: Bundle.main doesn't find it when run through the /usr/local/bin symlink.
        let plist = Installer.appBundleURL?.appendingPathComponent("Contents/Info.plist")
        return plist.flatMap { NSDictionary(contentsOf: $0)?["CFBundleShortVersionString"] as? String } ?? "dev"
    }

    // MARK: - Commands

    private static func list(_ args: Arguments) throws {
        let config = try loadConfig()
        if args.flag("json") { return try printJSON(config.shortcuts) }
        guard !config.shortcuts.isEmpty else { return print("No shortcuts. Add one with `doubletake add`.") }
        for s in config.shortcuts {
            let triggers = s.triggers.map(Spec.format).joined(separator: ", ")
            print("\(s.enabled ? "●" : "○") \(s.shortID)  \(s.name)  [\(triggers)]  → \(s.action.summary)")
        }
        if !config.settings.isEnabled { print("\n(DoubleTake is turned off. `doubletake settings --on` to turn it on.)") }
    }

    private static func add(_ args: Arguments) throws {
        guard let name = args.positional.first, !name.isEmpty else {
            throw CLIError("Usage: doubletake add <name> --trigger <trigger> <action option>. See `doubletake help`.")
        }
        let triggers = try args.values("trigger").map(Spec.parseTrigger)
        guard !triggers.isEmpty else { throw CLIError("Give at least one --trigger, e.g. --trigger double:fn") }
        guard let action = try parseAction(args) else {
            throw CLIError("Give an action, e.g. --system dictation, --app Safari, --shell 'say hi'. See `doubletake actions`.")
        }
        let disabled = args.flag("disabled")
        try mutate { config in
            guard config.index(of: name) == nil || args.flag("allow-duplicate") else {
                throw CLIError("A shortcut named “\(name)” already exists. Use `doubletake edit` or pick another name.")
            }
            let s = Shortcut(name: name, enabled: !disabled, triggers: triggers, action: action)
            config.shortcuts.append(s)
            return "Added “\(name)” (\(s.shortID)): \(triggers.map(Spec.format).joined(separator: ", ")) → \(action.summary)"
                + conflictNote(s, in: config)
        }
    }

    private static func edit(_ args: Arguments) throws {
        let newTriggers = try args.values("trigger").map(Spec.parseTrigger)
        let addedTriggers = try args.values("add-trigger").map(Spec.parseTrigger)
        let action = try parseAction(args)
        let newName = args.value("name")
        let enable = args.flag("enable")
        let disable = args.flag("disable")
        try mutate { config in
            let i = try find(args.positional.first, in: config)
            var s = config.shortcuts[i]
            if let newName { s.name = newName }
            if !newTriggers.isEmpty { s.triggers = newTriggers }
            s.triggers += addedTriggers
            if let action { s.action = action }
            if enable { s.enabled = true }
            if disable { s.enabled = false }
            config.shortcuts[i] = s
            return "Updated “\(s.name)”: \(s.triggers.map(Spec.format).joined(separator: ", ")) → \(s.action.summary)"
                + conflictNote(s, in: config)
        }
    }

    private static func presets(_ args: Arguments) throws {
        let all = Presets.groups.flatMap { g in g.presets.map { (group: g.title, preset: $0) } }
        if args.flag("json") {
            let items = all.enumerated().map { i, p in
                let s = p.preset.make()
                return ["number": "\(i + 1)", "group": p.group, "title": p.preset.title,
                        "trigger": s.triggers.map(Spec.format).joined(separator: ","), "action": s.action.summary]
            }
            return try printJSON(items)
        }
        var group = ""
        for (i, p) in all.enumerated() {
            if p.group != group {
                group = p.group
                print("\n\(group)")
            }
            print("  \(i + 1). \(p.preset.title)")
        }
        print("\nAdd one with `doubletake add-preset <number>`.")
    }

    private static func addPreset(_ args: Arguments) throws {
        let all = Presets.groups.flatMap(\.presets)
        guard let n = args.positional.first.flatMap(Int.init), (1...all.count).contains(n) else {
            throw CLIError("Usage: doubletake add-preset <number>. Run `doubletake presets` for the list.")
        }
        try mutate { config in
            var s = all[n - 1].make()
            if args.flag("disabled") { s.enabled = false }
            config.shortcuts.append(s)
            return "Added “\(s.name)” (\(s.shortID)): \(s.triggers.map(Spec.format).joined(separator: ", ")) → \(s.action.summary)"
                + conflictNote(s, in: config)
        }
    }

    private static func actions(_ args: Arguments) throws {
        if args.flag("json") {
            return try printJSON(SystemAction.allCases.map { ["name": $0.rawValue, "title": $0.title] })
        }
        print(Help.actions)
        print("\nBuilt-in actions for --system:")
        for group in SystemAction.groups {
            print("  \(group.title): " + group.actions.map(\.rawValue).joined(separator: ", "))
        }
    }

    private static func keys(_ args: Arguments) throws {
        if args.flag("json") {
            return try printJSON(Spec.keys.map { ["names": $0.names.joined(separator: ","), "code": "\($0.code)"] })
        }
        print("Key names (US layout). Join with + for combos: ctrl+opt+t, j+k.\n")
        print("Modifiers: cmd, opt, ctrl, shift, fn (in double: taps these mean either side)")
        print("           left-cmd, right-cmd, left-opt, right-opt, left-ctrl, right-ctrl, left-shift, right-shift")
        let modifierCodes = Set([KeyCode.command, KeyCode.rightCommand, KeyCode.shift, KeyCode.rightShift, KeyCode.option,
                                 KeyCode.rightOption, KeyCode.control, KeyCode.rightControl, KeyCode.function])
        print("Keys:      " + Spec.keys.filter { !modifierCodes.contains($0.code) }.map { $0.names[0] }.joined(separator: " "))
        print("Any other key: key<code>, e.g. key105 (macOS virtual key code)")
    }

    private static func settings(_ args: Arguments) throws {
        let interval = try args.value("interval").map { v -> Double in
            guard let d = Double(v), (0.1...1.0).contains(d) else { throw CLIError("--interval is seconds between 0.1 and 1.0") }
            return d
        }
        let window = try args.value("chord-window").map { v -> Double in
            guard let d = Double(v), (0.01...0.5).contains(d) else { throw CLIError("--chord-window is seconds between 0.01 and 0.5") }
            return d
        }
        let on = args.flag("on"), off = args.flag("off")
        if interval != nil || window != nil || on || off {
            try mutate { config in
                if let interval { config.settings.doubleTapInterval = interval }
                if let window { config.settings.chordWindow = window }
                if on { config.settings.isEnabled = true }
                if off { config.settings.isEnabled = false }
                return "Settings saved."
            }
        }
        let s = try loadConfig().settings
        if args.flag("json") { return try printJSON(s) }
        print("enabled:       \(s.isEnabled ? "on" : "off")")
        print("interval:      \(s.doubleTapInterval)s  (longest gap between taps)")
        print("chord-window:  \(s.chordWindow)s  (how close together keys count as simultaneous)")
    }

    private static func status(_ args: Arguments) throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Installer.bundleID).first
        let reported = (try? Data(contentsOf: ConfigFile.statusURL)).flatMap { try? JSONDecoder().decode(AppStatus.self, from: $0) }
        let live = running != nil && reported?.pid == running?.processIdentifier
        let config = (try? ConfigFile.load()) ?? nil
        let info: [String: String] = [
            "version": version,
            "appRunning": running != nil ? "yes" : "no",
            "accessibilityGranted": live ? (reported!.accessibilityGranted ? "yes" : "no") : "unknown",
            "listening": live ? (reported!.listening ? "yes" : "no") : "no",
            "enabled": config.map { $0.settings.isEnabled ? "yes" : "no" } ?? "yes",
            "shortcuts": "\(config?.shortcuts.count ?? 0) (\(config?.shortcuts.filter(\.enabled).count ?? 0) enabled)",
            "app": (running?.bundleURL ?? Installer.installedAppURL)?.path ?? "not installed",
            "config": ConfigFile.url.path,
            "cli": FileManager.default.fileExists(atPath: Installer.cliPath) ? Installer.cliPath : "not installed",
        ]
        if args.flag("json") { return try printJSON(info) }
        for key in ["version", "appRunning", "accessibilityGranted", "listening", "enabled", "shortcuts", "app", "config", "cli"] {
            print("\(key):".padding(toLength: 22, withPad: " ", startingAt: 0) + info[key]!)
        }
        if running == nil { print("\nStart the app with `doubletake open`; shortcuts only work while it runs.") }
        if live, reported?.accessibilityGranted == false {
            print("\nGrant Accessibility access in System Settings › Privacy & Security › Accessibility.")
        }
    }

    private static func importConfig(_ args: Arguments) throws {
        guard let path = args.positional.first else { throw CLIError("Usage: doubletake import <file.json> [--replace]") }
        let data = path == "-" ? FileHandle.standardInput.readDataToEndOfFile()
            : try Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        let incoming: ConfigFile
        if let config = try? ConfigFile.decode(data) , !config.shortcuts.isEmpty || data.first == UInt8(ascii: "{") {
            incoming = config
        } else {
            // Also accept a bare array of shortcuts.
            incoming = ConfigFile(shortcuts: try JSONDecoder().decode([Shortcut].self, from: data))
        }
        let replace = args.flag("replace")
        try mutate { config in
            if replace {
                config = incoming
                return "Replaced config with \(incoming.shortcuts.count) shortcut(s)."
            }
            let existing = Set(config.shortcuts.map(\.id))
            let added = incoming.shortcuts.map { s -> Shortcut in
                var s = s
                if existing.contains(s.id) { s.id = UUID() }
                return s
            }
            config.shortcuts += added
            return "Imported \(added.count) shortcut(s)."
        }
    }

    // MARK: - Actions

    private static func parseAction(_ args: Arguments) throws -> Action? {
        var action = Action()
        var found: [String] = []
        if let v = args.value("system") {
            let wanted = v.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
            guard let s = SystemAction.allCases.first(where: { $0.rawValue.lowercased() == wanted }) else {
                throw CLIError("Unknown built-in action “\(v)”. Run `doubletake actions`.")
            }
            action.type = .system
            action.system = s
            found.append("system")
        }
        if let v = args.value("app") {
            guard let path = resolveApp(v) else { throw CLIError("Couldn't find an app called “\(v)”.") }
            action.type = .openApp
            action.target = path
            action.toggleApp = args.flag("toggle")
            found.append("app")
        }
        if let v = args.value("url") {
            action.type = .openURL
            action.target = v
            found.append("url")
        }
        if let v = args.value("shell") {
            action.type = .shellScript
            action.script = v
            found.append("shell")
        }
        if let v = args.value("applescript") {
            action.type = .appleScript
            action.script = v
            found.append("applescript")
        }
        if let v = args.value("shortcut") {
            action.type = .runShortcut
            action.target = v
            found.append("shortcut")
        }
        if let v = args.value("keystroke") {
            action.type = .keystroke
            action.keystroke = try Spec.parseKeystroke(v)
            found.append("keystroke")
        }
        if let v = args.value("menu") {
            action.type = .menuItem
            action.target = v
            found.append("menu")
        }
        if found.count > 1 {
            throw CLIError("Pick one action; got \(found.map { "--\($0)" }.joined(separator: " and ")).")
        }
        return found.isEmpty ? nil : action
    }

    private static func resolveApp(_ value: String) -> String? {
        let expanded = (value as NSString).expandingTildeInPath
        if expanded.hasSuffix(".app"), FileManager.default.fileExists(atPath: expanded) { return expanded }
        if value.contains("."), !value.hasSuffix(".app"),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) {
            return url.path
        }
        let name = value.hasSuffix(".app") ? value : value + ".app"
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    "/Applications/Utilities", "~/Applications", "/System/Library/CoreServices"]
        for dir in dirs {
            let path = ((dir as NSString).expandingTildeInPath as NSString).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        // Case-insensitive match as a last resort.
        for dir in dirs {
            let base = (dir as NSString).expandingTildeInPath
            if let match = (try? FileManager.default.contentsOfDirectory(atPath: base))?
                .first(where: { $0.lowercased() == name.lowercased() }) {
                return (base as NSString).appendingPathComponent(match)
            }
        }
        return nil
    }

    private static func runAction(_ action: Action) throws {
        var result: String??
        ActionRunner.run(action) { result = .some($0) }
        let deadline = Date().addingTimeInterval(60)
        while result == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        guard let outcome = result else { throw CLIError("Timed out waiting for the action to finish.") }
        if let error = outcome { throw CLIError(error) }
    }

    // MARK: - Helpers

    private static func loadConfig() throws -> ConfigFile {
        if let config = try ConfigFile.load() { return config }
        // First use: write the defaults so their ids stay stable between commands.
        let config = ConfigFile(shortcuts: Presets.defaults())
        try config.save()
        return config
    }

    private static func mutate(_ change: (inout ConfigFile) throws -> String) throws {
        var config = try loadConfig()
        let message = try change(&config)
        try config.save()
        print(message)
    }

    private static func find(_ query: String?, in config: ConfigFile) throws -> Int {
        guard let query else { throw CLIError("Name the shortcut (or give its id from `doubletake list`).") }
        guard let i = config.index(of: query) else {
            throw CLIError("No shortcut matches “\(query)”. Run `doubletake list`.")
        }
        return i
    }

    private static func conflictNote(_ s: Shortcut, in config: ConfigFile) -> String {
        guard s.enabled else { return "" }
        let clashes = config.shortcuts.filter { other in
            other.id != s.id && other.enabled && other.triggers.contains { o in s.triggers.contains { $0.overlaps(o) } }
        }
        return clashes.isEmpty ? "" : "\nwarning: shares a trigger with \(clashes.map { "“\($0.name)”" }.joined(separator: ", ")); only one will run."
    }

    private static func printDetail(_ s: Shortcut) {
        print("name:     \(s.name)")
        print("id:       \(s.id.uuidString.lowercased())")
        print("enabled:  \(s.enabled ? "yes" : "no")")
        print("triggers: \(s.triggers.map(Spec.format).joined(separator: ", "))")
        print("action:   \(s.action.summary)")
        switch s.action.type {
        case .shellScript, .appleScript: print("script:\n\(s.action.script)")
        case .openApp: print("app:      \(s.action.target)\(s.action.toggleApp ? " (toggle)" : "")")
        case .keystroke: print("keys:     \(s.action.keystroke.map(Spec.format) ?? "-")")
        default: break
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data(("doubletake: " + message + "\n").utf8))
    }
}

struct CLIError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Minimal `--option value` / `--flag` parser. Options may repeat.
final class Arguments {
    var positional: [String] = []
    private var options: [String: [String]] = [:]
    private var flags: Set<String> = []
    private var used: Set<String> = []

    private static let flagNames: Set<String> = [
        "json", "llm", "disabled", "enable", "disable", "toggle", "replace", "on", "off", "allow-duplicate",
    ]

    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("--"), arg.count > 2 {
                let name = String(arg.dropFirst(2)).lowercased()
                if let eq = name.firstIndex(of: "=") {
                    options[String(name[..<eq]), default: []].append(String(name[name.index(after: eq)...]))
                } else if Self.flagNames.contains(name) || i + 1 >= args.count {
                    flags.insert(name)
                } else {
                    i += 1
                    options[name, default: []].append(args[i])
                }
            } else {
                positional.append(arg)
            }
            i += 1
        }
    }

    func flag(_ name: String) -> Bool {
        used.insert(name)
        return flags.contains(name)
    }

    func value(_ name: String) -> String? {
        used.insert(name)
        return options[name]?.last
    }

    func values(_ name: String) -> [String] {
        used.insert(name)
        return options[name] ?? []
    }

    var unusedOptions: [String] {
        (Set(options.keys).union(flags)).subtracting(used).sorted()
    }
}
