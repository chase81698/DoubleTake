import AppKit
import DoubleTakeCore
import Observation

/// Updates DoubleTake from its GitHub releases. Checking for updates is the only time DoubleTake
/// connects to the internet: it asks GitHub for the latest release and, if that's newer,
/// downloads the release's DoubleTake.zip (the same file install.sh uses) and its signature.
/// Nothing is installed unless the signature proves the zip came from the maintainer's release key.
@MainActor
enum Updater {
    static let repo = "chase81698/DoubleTake"

    #if DEBUG
    /// Debug builds can read releases from somewhere else via DOUBLETAKE_UPDATE_URL, to test the updater.
    /// Release builds always ask GitHub.
    private static let testFeed = ProcessInfo.processInfo.environment["DOUBLETAKE_UPDATE_URL"].flatMap(URL.init(string:))
    #else
    private static let testFeed: URL? = nil
    #endif

    static var latestReleaseURL: URL {
        testFeed ?? URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }

    static var currentVersion: AppVersion? { AppVersion(CLI.version) }

    /// Unsigned (ad-hoc) builds lose their Input Monitoring and Accessibility approvals whenever the app is replaced.
    static let isAdHocSigned: Bool = {
        guard let app = Installer.appBundleURL else { return true }
        return (try? shell("/usr/bin/codesign", "-dv", app.path))?.contains("Signature=adhoc") ?? true
    }()

    // MARK: - Steps

    static func latestRelease() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DoubleTake/\(CLI.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await fetch { try await URLSession.shared.data(for: request) }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 404: throw UpdateError("No DoubleTake release was found on GitHub.")
        case 403, 429: throw UpdateError("GitHub is limiting requests right now. Try again in a while.")
        case let code: throw UpdateError("GitHub answered with an error (HTTP \(code)).")
        }
        do {
            return try JSONDecoder().decode(Release.self, from: data)
        } catch {
            throw UpdateError("GitHub's answer didn't look like a DoubleTake release.")
        }
    }

    /// Downloads and unpacks a release, checking it's signed with the release key and is a newer,
    /// intact DoubleTake. Returns the unpacked DoubleTake.app in a temporary folder.
    static func download(_ release: Release) async throws -> URL {
        guard let archive = release.archive else {
            throw UpdateError("The \(release.tag) release on GitHub has no \(Release.archiveName) to install.")
        }
        guard let signature = release.signature else {
            throw UpdateError("The \(release.tag) release on GitHub isn't signed, so it wasn't installed.")
        }
        guard testFeed != nil || [archive, signature].allSatisfy({ Release.isTrustedDownload($0.downloadURL, repo: repo) }) else {
            throw UpdateError("The \(release.tag) release points somewhere other than DoubleTake's GitHub releases, so it wasn't installed.")
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoubleTake-Update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            let (file, response) = try await fetch { try await URLSession.shared.download(from: archive.downloadURL) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError("Couldn't download \(Release.archiveName) from GitHub.")
            }
            let zip = work.appendingPathComponent(Release.archiveName)
            try FileManager.default.moveItem(at: file, to: zip)
            let (signatureData, signatureResponse) = try await fetch { try await URLSession.shared.data(from: signature.downloadURL) }
            guard (signatureResponse as? HTTPURLResponse)?.statusCode == 200,
                  UpdateSignature.isValid(String(decoding: signatureData, as: UTF8.self), for: try Data(contentsOf: zip)) else {
                throw UpdateError("The download isn't signed with DoubleTake's release key, so it wasn't installed.")
            }
            try shell("/usr/bin/ditto", "-x", "-k", zip.path, work.path)

            let app = work.appendingPathComponent("DoubleTake.app")
            let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            guard info?["CFBundleIdentifier"] as? String == Installer.bundleID else {
                throw UpdateError("The download isn't DoubleTake.")
            }
            guard let version = (info?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
                  currentVersion.map({ version > $0 }) ?? true else {
                throw UpdateError("The download isn't newer than the DoubleTake you have.")
            }
            do {
                try shell("/usr/bin/codesign", "--verify", "--deep", "--strict", app.path)
            } catch {
                throw UpdateError("The download is damaged (its code signature doesn't check out).")
            }
            _ = try? shell("/usr/bin/xattr", "-dr", "com.apple.quarantine", app.path)
            return app
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    /// Replaces this copy of DoubleTake.app with `newApp`, asking for an administrator password
    /// only if the user can't write there. Returns where the app now lives.
    @discardableResult
    static func install(_ newApp: URL) throws -> URL {
        guard let target = Installer.appBundleURL else {
            throw UpdateError("Run DoubleTake from DoubleTake.app to update it.")
        }
        defer { try? FileManager.default.removeItem(at: newApp.deletingLastPathComponent()) }
        let resetPermission = isAdHocSigned
        // Copy next to the old app first, then swap, so a failed copy leaves the old app in place.
        let staging = target.deletingLastPathComponent().appendingPathComponent(".DoubleTake-update.app")
        let q = Installer.quoted
        let command = "set -e; rm -rf \(q(staging.path)); /usr/bin/ditto \(q(newApp.path)) \(q(staging.path)); "
            + "rm -rf \(q(target.path)); mv \(q(staging.path)) \(q(target.path))"
        do {
            try shell("/bin/sh", "-c", command)
        } catch {
            try Installer.runAsAdmin(command)
        }
        if resetPermission {
            // The old approval no longer matches the new build; clear it so macOS asks again cleanly.
            for service in ["ListenEvent", "Accessibility"] {
                _ = try? shell("/usr/bin/tccutil", "reset", service, Installer.bundleID)
            }
        }
        return target
    }

    // MARK: - Helpers

    private static func fetch<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as URLError {
            throw UpdateError("Couldn't reach GitHub: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private static func shell(_ tool: String, _ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Drives updates from the app: the Check for Updates button in General, and the optional
/// check when the app opens.
@Observable
@MainActor
final class UpdateController {
    static let shared = UpdateController()

    enum Phase: Equatable {
        case idle, checking, upToDate
        case downloading(AppVersion), installing(AppVersion)
        case failed(String)
    }

    private(set) var phase = Phase.idle

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    /// The Check for Updates button: installs a newer release right away, then reopens.
    func checkAndInstall() async {
        guard !isBusy else { return }
        phase = .checking
        do {
            let release = try await Updater.latestRelease()
            guard let version = release.version, Updater.currentVersion.map({ version > $0 }) ?? true else {
                phase = .upToDate
                return
            }
            try await install(release, version: version)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// When the app opens with the setting on: offers a newer release, and stays quiet otherwise.
    func checkOnLaunch() async {
        guard !isBusy, let release = try? await Updater.latestRelease(), let version = release.version,
              let current = Updater.currentVersion, version > current else { return }

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "DoubleTake \(version) is available"
        var details = "You have \(current). DoubleTake downloads the update from GitHub, installs it, and reopens."
        if Updater.isAdHocSigned {
            details += " macOS then asks you to allow DoubleTake's keyboard access again."
        }
        if let notes = release.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            details += "\n\n" + (notes.count > 600 ? String(notes.prefix(600)) + "…" : notes)
        }
        alert.informativeText = details
        alert.addButton(withTitle: "Install and Reopen")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try await install(release, version: version)
        } catch {
            phase = .failed(error.localizedDescription)
            let failure = NSAlert(error: error)
            failure.messageText = "Couldn't update DoubleTake."
            failure.runModal()
        }
    }

    private func install(_ release: Release, version: AppVersion) async throws {
        phase = .downloading(version)
        let app = try await Updater.download(release)
        phase = .installing(version)
        let installed = try Updater.install(app)
        Installer.relaunch(at: installed)
    }
}
