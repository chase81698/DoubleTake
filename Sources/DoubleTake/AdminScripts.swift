import AppKit
import DoubleTakeCore

/// Lets shell actions run as root without a password every time.
///
/// Approving installs a root-owned copy of each "Run as administrator" script, plus a sudoers
/// rule that lets this user run exactly those files with `sudo -n`. Because the copies are
/// owned by root, nothing running as the user can change what they do; editing a script in
/// DoubleTake makes it unapproved again until the user re-enters their password.
@MainActor
enum AdminScripts {
    /// Set by the app. Unapproved scripts then ask to be approved; from the CLI they just fail.
    static var canPromptForApproval = false

    private static let root = "/Library/Application Support/DoubleTake/AdminScripts"

    /// Usernames go into file names and sudoers, so keep them to safe characters.
    private static var userKey: String {
        String(NSUserName().map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
    }

    private static var userDirectory: String { "\(root)/\(userKey)" }
    /// sudo ignores files in sudoers.d whose names contain a dot.
    static var sudoersPath: String { "/private/etc/sudoers.d/doubletake-\(userKey)" }

    static func path(for id: UUID) -> String {
        "\(userDirectory)/\(id.uuidString.lowercased()).sh"
    }

    private static func fileContents(_ script: String) -> String {
        "#!/bin/zsh\n# Installed by DoubleTake. Runs as root without a password. Edit it in DoubleTake.\n\(script)\n"
    }

    /// Whether this exact script is installed and owned by root.
    static func isApproved(id: UUID, script: String) -> Bool {
        let path = path(for: id)
        guard let data = FileManager.default.contents(atPath: path),
              String(decoding: data, as: UTF8.self) == fileContents(script),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0 else { return false }
        return FileManager.default.fileExists(atPath: sudoersPath)
    }

    static func adminShortcuts(in shortcuts: [Shortcut]) -> [Shortcut] {
        shortcuts.filter { $0.action.type == .shellScript && $0.action.runAsAdmin }
    }

    static func approvedCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: userDirectory))?.filter { $0.hasSuffix(".sh") }.count ?? 0
    }

    /// Installs every "Run as administrator" script in the saved config and removes any others,
    /// after one password prompt.
    static func approveAll() throws {
        let shortcuts = adminShortcuts(in: (try ConfigFile.load())?.shortcuts ?? [])
        guard !shortcuts.isEmpty else { return try revokeAll() }

        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("doubletake-approve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }

        var lines = ["# Managed by DoubleTake: lets \(NSUserName()) run their approved DoubleTake scripts as root."]
        var installs: [String] = []
        for s in shortcuts {
            let name = "\(s.id.uuidString.lowercased()).sh"
            try fileContents(s.action.script).write(to: stage.appendingPathComponent(name), atomically: true, encoding: .utf8)
            let target = path(for: s.id)
            lines.append("\(sudoersUser) ALL=(root) NOPASSWD: \(target.replacingOccurrences(of: " ", with: "\\ "))")
            installs.append("/usr/bin/install -m 755 -o root -g wheel \(quoted(stage.appendingPathComponent(name).path)) \(quoted(target))")
        }
        let sudoers = stage.appendingPathComponent("sudoers")
        try (lines.joined(separator: "\n") + "\n").write(to: sudoers, atomically: true, encoding: .utf8)

        let command = (["set -e",
                        "/bin/mkdir -p \(quoted(root))",
                        "/usr/sbin/chown root:wheel \(quoted(root)) && /bin/chmod 755 \(quoted(root))",
                        "/bin/rm -rf \(quoted(userDirectory))",
                        "/usr/bin/install -d -m 755 -o root -g wheel \(quoted(userDirectory))"]
                       + installs
                       + ["/usr/sbin/visudo -cqf \(quoted(sudoers.path))",
                          "/usr/bin/install -m 440 -o root -g wheel \(quoted(sudoers.path)) \(quoted(sudoersPath))"])
            .joined(separator: "; ")
        try runAsAdmin(command, prompt: "DoubleTake wants to let \(shortcuts.count) approved script\(shortcuts.count == 1 ? "" : "s") run as administrator without asking again.")
    }

    /// Removes every approval (scripts and sudoers rule).
    static func revokeAll() throws {
        guard FileManager.default.fileExists(atPath: userDirectory) || FileManager.default.fileExists(atPath: sudoersPath) else { return }
        try runAsAdmin("/bin/rm -f \(quoted(sudoersPath)); /bin/rm -rf \(quoted(userDirectory))",
                       prompt: "DoubleTake wants to remove its administrator access.")
    }

    /// Runs an approved script, or (in the app) offers to approve it first.
    static func run(id: UUID, name: String, script: String, _ done: @escaping (String?) -> Void) {
        if isApproved(id: id, script: script) {
            return ActionRunner.runProcess("/usr/bin/sudo", ["-n", path(for: id)], done)
        }
        guard canPromptForApproval else {
            return done("“\(name)” runs as administrator and isn't approved yet (or was edited). Run `doubletake approve` or approve it in the app.")
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Allow “\(name)” to run as administrator?"
        alert.informativeText = "Enter your password once and this script runs as root without asking again. If the script is changed, DoubleTake asks again."
        let preview = NSTextField(wrappingLabelWithString: script)
        preview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        preview.preferredMaxLayoutWidth = 420
        preview.frame.size = preview.fittingSize
        alert.accessoryView = preview
        alert.addButton(withTitle: "Approve and Run")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return done(nil) }
        do {
            try approveAll()
        } catch {
            return done(error.localizedDescription)
        }
        guard isApproved(id: id, script: script) else { return done("Approval didn't take effect.") }
        ActionRunner.runProcess("/usr/bin/sudo", ["-n", path(for: id)], done)
    }

    // MARK: - Helpers

    private static var sudoersUser: String {
        let name = NSUserName()
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." } ? name : "#\(getuid())"
    }

    private static func runAsAdmin(_ command: String, prompt: String) throws {
        let escape = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let source = "do shell script \"\(escape(command))\" with prompt \"\(escape(prompt))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            throw CLIError(code == -128 ? "Cancelled." : (error[NSAppleScript.errorMessage] as? String ?? "Administrator command failed."))
        }
    }

    private static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
