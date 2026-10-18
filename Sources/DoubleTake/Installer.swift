import AppKit

/// Knows where DoubleTake belongs: the app in /Applications, the CLI in /usr/local/bin.
@MainActor
enum Installer {
    static let bundleID = "io.github.chase81698.DoubleTake"
    static let applicationsURL = URL(fileURLWithPath: "/Applications/DoubleTake.app")
    static let cliPath = "/usr/local/bin/doubletake"
    private static let declinedMoveKey = "declinedMoveToApplications"

    /// The .app bundle this process belongs to, if any (works through the CLI symlink too).
    static var appBundleURL: URL? {
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let app = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return app.pathExtension == "app" ? app : nil
    }

    static var installedAppURL: URL? {
        if FileManager.default.fileExists(atPath: applicationsURL.path) { return applicationsURL }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static var executablePath: String? {
        appBundleURL?.appendingPathComponent("Contents/MacOS/DoubleTake").path
    }

    static var isInApplications: Bool {
        guard let app = appBundleURL?.path else { return false }
        return app.hasPrefix("/Applications/") || app.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    static var isCLIInstalled: Bool {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: cliPath) else { return false }
        return dest == executablePath
    }

    // MARK: - Move to /Applications

    /// Offers to move the app into /Applications when it's launched from anywhere else
    /// (Downloads, a build folder…). Returns true if the app is relaunching from there.
    static func offerMoveIfNeeded() -> Bool {
        guard let app = appBundleURL, !isInApplications,
              !UserDefaults.standard.bool(forKey: declinedMoveKey) else { return false }

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Move DoubleTake to your Applications folder?"
        alert.informativeText = "DoubleTake lives in Applications so it can start at login and keep its permissions."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: declinedMoveKey)
        }
        guard response == .alertFirstButtonReturn else { return false }

        do {
            try copyApp(from: app, to: applicationsURL)
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = "Couldn't move DoubleTake to Applications."
            failure.runModal()
            return false
        }
        try? FileManager.default.trashItem(at: app, resultingItemURL: nil)
        relaunch(at: applicationsURL)
        return true
    }

    private static func copyApp(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.trashItem(at: destination, resultingItemURL: nil)
            }
            try fm.copyItem(at: source, to: destination)
        } catch {
            // /Applications isn't writable for this user: ask for an admin password.
            try runAsAdmin("rm -rf \(quoted(destination.path)) && cp -R \(quoted(source.path)) \(quoted(destination.path))")
        }
    }

    private static func relaunch(at url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \(quoted(url.path))"]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Command line tool

    /// Links /usr/local/bin/doubletake to this app's executable, asking for an admin
    /// password if /usr/local/bin isn't writable.
    static func installCLI() throws {
        guard let exe = executablePath else {
            throw CLIError("Run this from DoubleTake.app, not a bare build.")
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: "/usr/local/bin", withIntermediateDirectories: true)
            if (try? fm.destinationOfSymbolicLink(atPath: cliPath)) != nil || fm.fileExists(atPath: cliPath) {
                try fm.removeItem(atPath: cliPath)
            }
            try fm.createSymbolicLink(atPath: cliPath, withDestinationPath: exe)
        } catch {
            try runAsAdmin("mkdir -p /usr/local/bin && ln -sf \(quoted(exe)) \(quoted(cliPath))")
        }
    }

    static func uninstallCLI() throws {
        let fm = FileManager.default
        guard (try? fm.destinationOfSymbolicLink(atPath: cliPath)) != nil || fm.fileExists(atPath: cliPath) else { return }
        do {
            try fm.removeItem(atPath: cliPath)
        } catch {
            try runAsAdmin("rm -f \(quoted(cliPath))")
        }
    }

    // MARK: - Helpers

    private static func runAsAdmin(_ command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            throw CLIError(error[NSAppleScript.errorMessage] as? String ?? "Administrator command failed.")
        }
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension CLIError: LocalizedError {
    var errorDescription: String? { message }
}
