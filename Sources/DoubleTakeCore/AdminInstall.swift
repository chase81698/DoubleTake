import Foundation

/// Builds the one shell command that approves "Run as administrator" scripts. It runs as root after the
/// user enters their password.
///
/// Every script's text and the sudoers rule travel inside the command itself (base64), and are written
/// straight into root-owned locations. Nothing is staged in a folder the user's account can write to,
/// so nothing running as the user can swap in different content between approval and install.
public struct AdminInstall: Sendable {
    /// Root-owned folder holding every user's approved scripts.
    public var rootDirectory: String
    /// This user's folder inside it; every approved script is a file here.
    public var directory: String
    /// The sudoers.d file that lets this user run exactly those files as root.
    public var sudoersPath: String
    /// The user as sudoers names them (a plain name, or #uid).
    public var sudoersUser: String
    /// Owner and group for everything written (root:wheel, except in tests).
    public var owner = "root"
    public var group = "wheel"

    public init(rootDirectory: String, directory: String, sudoersPath: String, sudoersUser: String) {
        self.rootDirectory = rootDirectory
        self.directory = directory
        self.sudoersPath = sudoersPath
        self.sudoersUser = sudoersUser
    }

    public struct InvalidName: Error, CustomStringConvertible {
        public let name: String
        public var description: String { "Refusing to write “\(name)” into a sudoers rule." }
    }

    /// The command that installs `scripts` (file name → contents), removes `remove` (file names), and
    /// rewrites the sudoers rule to cover exactly `scripts` plus `keep` (already-approved file names left as they are).
    /// Throws if the user or a file name has characters that could change the meaning of the sudoers rule.
    public func command(installing scripts: [(name: String, contents: String)], keeping keep: [String],
                        removing remove: [String]) throws -> String {
        let allowed = (keep + scripts.map(\.name)).sorted()
        try Self.check(sudoersUser, allowed: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.", orUID: true)
        for name in allowed + remove {
            try Self.check(name, allowed: "abcdefghijklmnopqrstuvwxyz0123456789-.", orUID: false)
        }
        var sudoers = "# Managed by DoubleTake: lets \(sudoersUser) run their approved DoubleTake scripts as root.\n"
        for name in allowed {
            sudoers += "\(sudoersUser) ALL=(root) NOPASSWD: \(path(name).replacingOccurrences(of: " ", with: "\\ "))\n"
        }
        // sudo ignores sudoers.d files whose names contain a dot, so the staged copy is inert until renamed.
        let stagedSudoers = sudoersPath + ".new"
        var steps = [
            "set -e",
            "umask 022",
            "/bin/mkdir -p \(q(rootDirectory))",
            "/usr/sbin/chown \(owner):\(group) \(q(rootDirectory))",
            "/bin/chmod 755 \(q(rootDirectory))",
            "/usr/bin/install -d -m 755 -o \(owner) -g \(group) \(q(directory))",
        ]
        steps += remove.map { "/bin/rm -f \(q(path($0)))" }
        for script in scripts {
            let staged = path(script.name) + ".new"
            steps += [
                "/bin/rm -f \(q(staged))",
                "/usr/bin/printf %s \(q(Data(script.contents.utf8).base64EncodedString())) | /usr/bin/base64 -D > \(q(staged))",
                "/usr/sbin/chown \(owner):\(group) \(q(staged))",
                "/bin/chmod 755 \(q(staged))",
                "/bin/mv -f \(q(staged)) \(q(path(script.name)))",
            ]
        }
        steps += [
            "/bin/rm -f \(q(stagedSudoers))",
            "/usr/bin/printf %s \(q(Data(sudoers.utf8).base64EncodedString())) | /usr/bin/base64 -D > \(q(stagedSudoers))",
            "/usr/sbin/chown \(owner):\(group) \(q(stagedSudoers))",
            "/bin/chmod 440 \(q(stagedSudoers))",
            "/usr/sbin/visudo -cqf \(q(stagedSudoers))",
            "/bin/mv -f \(q(stagedSudoers)) \(q(sudoersPath))",
        ]
        return steps.joined(separator: "; ")
    }

    public func path(_ name: String) -> String { "\(directory)/\(name)" }

    private static func check(_ name: String, allowed: String, orUID: Bool) throws {
        let isUID = orUID && name.first == "#" && name.count > 1 && name.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
        guard isUID || (!name.isEmpty && !name.hasPrefix(".") && !name.hasPrefix("-") && name.allSatisfy(allowed.contains)) else {
            throw InvalidName(name: name)
        }
    }

    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
