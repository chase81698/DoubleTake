import AppKit
import DoubleTakeCore

/// Listens to the system-wide key stream through a CGEvent tap and feeds it to the engine
/// (or to a recorder while the user is recording a trigger).
final class EventTap {
    let engine: Engine
    var isEnabled = true {
        didSet { if !isEnabled { engine.reset() } }
    }
    var recorder: KeyRecorder?
    var onRecorded: ((KeyRecorder.Result) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var nextToken = 0
    private var stash: [Int: CGEvent] = [:]
    private var fnDown = false

    var isRunning: Bool { tap != nil }
    /// Watch-only taps (Input Monitoring) can't stop a key reaching the front app.
    private(set) var isListenOnly = false
    private var localMonitor: Any?
    /// Recording ends on the tap's copy of a key press, before the window gets it; keep the window from seeing it too.
    private var holdLocalKeysUntil: TimeInterval = 0

    init(engine: Engine) {
        self.engine = engine
        engine.onReplay = { [weak self] in self?.replay($0) }
        engine.onDeadlineChange = { [weak self] in self?.schedule($0) }
    }

    /// Installs the tap: watch-only with Input Monitoring, or able to block keys with Accessibility
    /// (Custom actions). Fails until the app has the matching permission.
    @discardableResult
    func start(listenOnly: Bool) -> Bool {
        if tap != nil, isListenOnly != listenOnly { stop() }
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: listenOnly ? .listenOnly : .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        isListenOnly = listenOnly
        engine.canHoldKeys = !listenOnly
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        CGEvent.tapEnable(tap: tap, enable: true)
        // A watch-only tap can't keep keys out of DoubleTake's own window while recording a trigger, so do that here.
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, isListenOnly,
                      recorder != nil || ProcessInfo.processInfo.systemUptime < holdLocalKeysUntil else { return event }
                return nil
            }
        }
        return true
    }

    func stop() {
        guard let tap else { return }
        engine.reset()
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        stash = [:]
    }

    fileprivate func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        // Our own synthetic and replayed events go straight through.
        if event.getIntegerValueField(.eventSourceUserData) == SyntheticInput.marker { return pass }
        guard let e = decode(type: type, event: event) else { return pass }

        if let recorder {
            if e.kind == .mouseDown { return pass }
            if let result = recorder.handle(e) {
                self.recorder = nil
                holdLocalKeysUntil = ProcessInfo.processInfo.systemUptime + 0.5
                DispatchQueue.main.async { self.onRecorded?(result) }
            }
            // Keep keys from typing into the window while recording.
            return e.kind == .flagsChanged ? pass : nil
        }
        guard isEnabled else { return pass }

        if e.kind != .mouseDown, let copy = event.copy() {
            stash[e.token] = copy
            stash[e.token - 64] = nil
        }
        return engine.handle(e) == .pass ? pass : nil
    }

    private static let sideMasks: [UInt16: UInt64] = [
        KeyCode.control: 0x0001, KeyCode.shift: 0x0002, KeyCode.rightShift: 0x0004,
        KeyCode.command: 0x0008, KeyCode.rightCommand: 0x0010, KeyCode.option: 0x0020,
        KeyCode.rightOption: 0x0040, KeyCode.rightControl: 0x2000,
    ]

    private func decode(type: CGEventType, event: CGEvent) -> KeyEvent? {
        let kind: KeyEventKind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: kind = .mouseDown
        default: return nil
        }
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        var isDown = false
        if kind == .flagsChanged {
            if keyCode == KeyCode.function {
                isDown = flags.contains(.maskSecondaryFn)
                fnDown = isDown
            } else if keyCode == KeyCode.capsLock {
                isDown = flags.contains(.maskAlphaShift)
            } else if let mask = Self.sideMasks[keyCode], let family = KeyCode.family(of: keyCode) {
                let raw = flags.rawValue
                if raw & mask != 0 {
                    isDown = true
                } else {
                    // Some virtual keyboards don't report sides; fall back to the family flag.
                    let sides = Self.sideMasks.filter { KeyCode.family(of: $0.key) == family }.values.reduce(0, |)
                    isDown = raw & sides == 0 && flags.contains(Self.cgFlag(for: family))
                }
            }
        }

        // The system sets the Fn flag on arrow and function keys too, so track the real key instead.
        var modifiers: Modifiers = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if fnDown { modifiers.insert(.function) }

        nextToken += 1
        return KeyEvent(
            kind: kind,
            keyCode: keyCode,
            modifiers: modifiers,
            isDown: isDown,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            time: ProcessInfo.processInfo.systemUptime,
            token: nextToken
        )
    }

    private static func cgFlag(for family: Modifiers) -> CGEventFlags {
        switch family {
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .shift: return .maskShift
        case .command: return .maskCommand
        default: return .maskSecondaryFn
        }
    }

    private func replay(_ events: [KeyEvent]) {
        for e in events {
            guard let original = stash.removeValue(forKey: e.token), let copy = original.copy() else { continue }
            copy.setIntegerValueField(.eventSourceUserData, value: SyntheticInput.marker)
            copy.post(tap: .cghidEventTap)
        }
    }

    private func schedule(_ deadline: TimeInterval?) {
        timer?.invalidate()
        timer = nil
        guard let deadline else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.engine.tick(now: ProcessInfo.processInfo.systemUptime)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue().process(type: type, event: event)
}
