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
        "\(userDirectory)/\(fileName(for: id))"
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

    /// Approves exactly these scripts, the ones the user was just shown, after one password prompt.
    /// Scripts approved earlier stay approved; approvals for shortcuts that no longer run as
    /// administrator are dropped. The text approved is the text passed in, never re-read from the
    /// config file, so nothing can change a script between the user seeing it and it becoming root.
    static func approve(_ scripts: [(id: UUID, name: String, script: String)]) throws {
        guard !scripts.isEmpty else { return }
        let fm = FileManager.default
        let names = Set(scripts.map { fileName(for: $0.id) })
        let stillAdmin = Set(adminShortcuts(in: (try? ConfigFile.load())?.shortcuts ?? []).map { fileName(for: $0.id) })
        // Earlier approvals are root-owned files; keep them unless their shortcut stopped running as admin.
        let existing = ((try? fm.contentsOfDirectory(atPath: userDirectory)) ?? []).filter { name in
            name.hasSuffix(".sh") && !names.contains(name)
                && ((try? fm.attributesOfItem(atPath: "\(userDirectory)/\(name)"))?[.ownerAccountID] as? NSNumber)?.intValue == 0
        }
        let keep = existing.filter { stillAdmin.contains($0) }
        let remove = existing.filter { !stillAdmin.contains($0) }

        let command = try installer.command(installing: scripts.map { (fileName(for: $0.id), fileContents($0.script)) },
                                        keeping: keep, removing: remove)
        let prompt = scripts.count == 1
            ? "DoubleTake wants to let “\(scripts[0].name)” run as administrator without asking again."
            : "DoubleTake wants to let \(scripts.count) scripts run as administrator without asking again."
        try runAsAdmin(command, prompt: prompt)
    }

    private static var installer: AdminInstall {
        AdminInstall(rootDirectory: root, directory: userDirectory, sudoersPath: sudoersPath, sudoersUser: sudoersUser)
    }

    private static func fileName(for id: UUID) -> String { "\(id.uuidString.lowercased()).sh" }

    /// Removes every approval (scripts and sudoers rule).
    static func revokeAll() throws {
        guard FileManager.default.fileExists(atPath: userDirectory) || FileManager.default.fileExists(atPath: sudoersPath) else { return }
        try runAsAdmin(removalCommand, prompt: "DoubleTake wants to remove its administrator access.")
    }

    /// Root command that removes this user's approvals, and the shared folder once no one has any.
    static var removalCommand: String {
        "/bin/rm -f \(quoted(sudoersPath)) \(quoted(sudoersPath + ".new")); /bin/rm -rf \(quoted(userDirectory)); "
            + "/bin/rmdir \(quoted(root)) \(quoted((root as NSString).deletingLastPathComponent)) 2>/dev/null || true"
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
            try approve([(id, name, script)])
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
