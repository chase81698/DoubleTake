import AppKit
import DoubleTakeCore
import Observation
import ServiceManagement

@Observable
@MainActor
final class AppState {
    var shortcuts: [Shortcut] = [] {
        didSet {
            engine.shortcuts = shortcuts
            save()
        }
    }
    var settings = AppSettings() {
        didSet {
            applySettings()
            save()
        }
    }
    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { updateLoginItem() }
    }
    private(set) var isTrusted = false
    private(set) var recordingID: UUID?
    private(set) var lastFired: (name: String, date: Date)?
    /// Whether the window should open at launch (first run or missing permission).
    private(set) var needsAttention = false

    @ObservationIgnored let engine = Engine()
    @ObservationIgnored let tap: EventTap
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var lastSavedData: Data?
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    static let configURL = ConfigFile.url

    init() {
        tap = EventTap(engine: engine)
        load()
        engine.onFire = { [weak self] shortcut in
            // Leave the event tap callback before doing any real work.
            DispatchQueue.main.async {
                self?.lastFired = (shortcut.name, Date())
                ActionRunner.run(shortcut.action)
            }
        }
        applySettings()
        engine.shortcuts = shortcuts
        checkPermission(prompt: false)
        needsAttention = needsAttention || !isTrusted
        watchConfig()
        writeStatus()
    }

    // MARK: - Permission

    func requestPermission() {
        checkPermission(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func checkPermission(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted != isTrusted {
            isTrusted = trusted
            writeStatus()
        }
        if isTrusted, tap.start() {
            writeStatus()
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else if permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkPermission(prompt: false) }
            }
        }
    }

    // MARK: - Recording

    func startRecording(id: UUID, mode: KeyRecorder.Mode, completion: @escaping (KeyRecorder.Result) -> Void) {
        tap.recorder = KeyRecorder(mode: mode)
        recordingID = id
        tap.onRecorded = { [weak self] result in
            self?.recordingID = nil
            completion(result)
        }
    }

    func cancelRecording() {
        tap.recorder = nil
        recordingID = nil
    }

    // MARK: - Shortcuts

    func shortcut(withID id: UUID) -> Shortcut? {
        shortcuts.first { $0.id == id }
    }

    func update(_ shortcut: Shortcut) {
        guard let i = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        shortcuts[i] = shortcut
    }

    func remove(_ id: UUID) {
        shortcuts.removeAll { $0.id == id }
    }

    /// Names of other enabled shortcuts that respond to the same input as `trigger`.
    func conflicts(for trigger: Trigger, in shortcut: Shortcut) -> [String] {
        guard shortcut.enabled, trigger.isComplete else { return [] }
        return shortcuts.filter { other in
            other.id != shortcut.id && other.enabled && other.triggers.contains { $0.isComplete && $0.overlaps(trigger) }
        }.map(\.name)
    }

    func restoreDefaults() {
        shortcuts = Presets.defaults()
        settings = AppSettings()
    }

    // MARK: - Settings & persistence

    private func applySettings() {
        engine.doubleTapInterval = settings.doubleTapInterval
        engine.chordWindow = settings.chordWindow
        tap.isEnabled = settings.isEnabled
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin { launchAtLogin = actual }
    }

    private func load() {
        do {
            if let config = try ConfigFile.load() {
                apply(config)
                lastSavedData = try? Data(contentsOf: Self.configURL)
                return
            }
        } catch {
            // Keep the unreadable file for the user to fix rather than overwriting it.
            let backup = Self.configURL.appendingPathExtension("broken")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: Self.configURL, to: backup)
        }
        shortcuts = Presets.defaults()
        needsAttention = true
    }

    private func apply(_ config: ConfigFile) {
        isLoading = true
        defer { isLoading = false }
        if settings != config.settings { settings = config.settings }
        if shortcuts != config.shortcuts { shortcuts = config.shortcuts }
    }

    private func save() {
        guard !isLoading else { return }
        do {
            let config = ConfigFile(settings: settings, shortcuts: shortcuts)
            try config.save()
            lastSavedData = try config.encoded()
        } catch {
            NSSound.beep()
        }
    }

    /// Picks up edits made by the CLI (or by hand) while the app is running.
    private func watchConfig() {
        let dir = ConfigFile.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.configChangedOnDisk() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func configChangedOnDisk() {
        guard let data = try? Data(contentsOf: Self.configURL), data != lastSavedData,
              let config = try? ConfigFile.decode(data) else { return }
        lastSavedData = data
        apply(config)
    }

    private func writeStatus() {
        let status = AppStatus(pid: ProcessInfo.processInfo.processIdentifier, accessibilityGranted: isTrusted,
                               listening: tap.isRunning, appPath: Bundle.main.bundlePath)
        guard let data = try? JSONEncoder().encode(status) else { return }
        try? FileManager.default.createDirectory(at: ConfigFile.directory, withIntermediateDirectories: true)
        try? data.write(to: ConfigFile.statusURL, options: .atomic)
    }
}
