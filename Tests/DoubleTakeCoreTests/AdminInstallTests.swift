import Foundation
import Testing
@testable import DoubleTakeCore

/// Runs the real approval command in a temporary folder, owned by the current user instead of root.
@Suite struct AdminInstallTests {
    let base: String
    let installer: AdminInstall

    init() throws {
        base = NSTemporaryDirectory() + "AdminInstallTests \(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: base + "/sudoers.d", withIntermediateDirectories: true)
        var installer = AdminInstall(rootDirectory: base + "/Application Support/DoubleTake",
                                     directory: base + "/Application Support/DoubleTake/me",
                                     sudoersPath: base + "/sudoers.d/doubletake-me", sudoersUser: "me")
        installer.owner = NSUserName()
        installer.group = "staff"
        self.installer = installer
    }

    func run(_ command: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func contents(_ path: String) -> String? {
        FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func installsExactlyTheApprovedText() throws {
        let script = "#!/bin/zsh\necho 'it'\\''s' \"$HOME\" `whoami` $(id -u); rm -rf \"/tmp/x y\" \\\n"
        let command = try installer.command(installing: [("a.sh", script)], keeping: [], removing: [])
        #expect(!command.contains("whoami"), "script text should travel encoded, not as shell code")
        #expect(try run(command) == 0)

        #expect(contents(installer.path("a.sh")) == script)
        let mode = try FileManager.default.attributesOfItem(atPath: installer.path("a.sh"))[.posixPermissions] as? Int
        #expect(mode == 0o755)
        // The app reads approvals as the user, so every folder on the way must be readable.
        for folder in [base + "/Application Support", installer.rootDirectory, installer.directory] {
            let folderMode = try FileManager.default.attributesOfItem(atPath: folder)[.posixPermissions] as? Int
            #expect(folderMode == 0o755, "\(folder)")
        }
        let sudoers = try #require(contents(installer.sudoersPath))
        #expect(sudoers.contains("me ALL=(root) NOPASSWD: \(installer.path("a.sh").replacingOccurrences(of: " ", with: "\\ "))\n"))
        #expect(!FileManager.default.fileExists(atPath: installer.sudoersPath + ".new"))
    }

    @Test func keepsAndRemovesOtherApprovals() throws {
        #expect(try run(try installer.command(installing: [("a.sh", "echo a\n"), ("c.sh", "echo c\n")], keeping: [], removing: [])) == 0)
        #expect(try run(try installer.command(installing: [("b.sh", "echo b\n")], keeping: ["a.sh"], removing: ["c.sh"])) == 0)

        #expect(contents(installer.path("a.sh")) == "echo a\n")
        #expect(contents(installer.path("b.sh")) == "echo b\n")
        #expect(!FileManager.default.fileExists(atPath: installer.path("c.sh")))
        let rules = try #require(contents(installer.sudoersPath)).split(separator: "\n").filter { !$0.hasPrefix("#") }
        #expect(rules.count == 2)
        #expect(rules.allSatisfy { $0.hasSuffix("a.sh") || $0.hasSuffix("b.sh") })
    }

    @Test(arguments: ["me ALL=(ALL) ALL\n#", "me\nroot", "", "#", "#12x", "#+5", "#-1", "a b", "a,b", "-me", ".me"])
    func refusesUnsafeUsers(_ user: String) {
        var broken = installer
        broken.sudoersUser = user
        #expect(throws: AdminInstall.InvalidName.self) {
            try broken.command(installing: [("a.sh", "echo a\n")], keeping: [], removing: [])
        }
    }

    @Test(arguments: ["../evil.sh", "a b.sh", "A.SH", "a.sh\nme ALL=(ALL) ALL", ".hidden.sh", "-rf"])
    func refusesUnsafeFileNames(_ name: String) {
        #expect(throws: AdminInstall.InvalidName.self) {
            try installer.command(installing: [(name, "echo a\n")], keeping: [], removing: [])
        }
        #expect(throws: AdminInstall.InvalidName.self) {
            try installer.command(installing: [("a.sh", "echo a\n")], keeping: [name], removing: [])
        }
        #expect(throws: AdminInstall.InvalidName.self) {
            try installer.command(installing: [("a.sh", "echo a\n")], keeping: [], removing: [name])
        }
    }

    @Test func acceptsRealUsersAndApprovalNames() throws {
        for user in ["chase", "first.last", "_svc", "#501"] {
            var ok = installer
            ok.sudoersUser = user
            _ = try ok.command(installing: [("\(UUID().uuidString.lowercased()).sh", "echo\n")], keeping: [], removing: [])
        }
    }
}
