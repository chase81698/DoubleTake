import Foundation

public enum KeyEventKind: Sendable {
    case keyDown, keyUp, flagsChanged, mouseDown
}

/// A keyboard (or mouse-down) event, already decoded from the raw system event.
public struct KeyEvent: Sendable {
    public var kind: KeyEventKind
    public var keyCode: UInt16
    /// Modifier families held after this event.
    public var modifiers: Modifiers
    /// For `.flagsChanged`: whether the key named by `keyCode` is now down.
    public var isDown: Bool
    public var isRepeat: Bool
    /// Seconds on a monotonic clock.
    public var time: TimeInterval
    /// Opaque id the event tap uses to find the original event again for replay.
    public var token: Int

    public init(kind: KeyEventKind, keyCode: UInt16 = 0, modifiers: Modifiers = [], isDown: Bool = false,
                isRepeat: Bool = false, time: TimeInterval, token: Int = 0) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isDown = isDown
        self.isRepeat = isRepeat
        self.time = time
        self.token = token
    }
}

public enum Verdict: Sendable {
    case pass, swallow
}

/// Matches the live key stream against the configured shortcuts.
///
/// The engine is a pure state machine: the caller feeds it events and the current time,
/// and it reports what to do through its verdicts and callbacks. It never touches the
/// system, so it can be tested with synthetic events.
public final class Engine {
    public var shortcuts: [Shortcut] = [] {
        didSet { rebuild() }
    }
    /// Longest gap allowed between taps of a double/triple tap.
    public var doubleTapInterval: TimeInterval = 0.3
    /// How long to hold back a key that may be the start of a multi-key combo like J + K.
    public var chordWindow: TimeInterval = 0.08
    /// Longest a modifier may be held and still count as a tap.
    public var maxTapHold: TimeInterval = 0.4
    /// Longest a modifier-only combo (e.g. ⌃⌥) may be held and still fire on release.
    public var maxModifierComboHold: TimeInterval = 1.0

    public var onFire: (Shortcut) -> Void = { _ in }
    /// Events the engine held back and now wants re-posted, in order.
    public var onReplay: ([KeyEvent]) -> Void = { _ in }
    /// The time at which `tick(now:)` should next be called, or nil for never.
    public var onDeadlineChange: (TimeInterval?) -> Void = { _ in }

    private struct Tap {
        var keyCode: UInt16
        var end: TimeInterval
    }

    private struct LonePress {
        var keyCode: UInt16
        var start: TimeInterval
        var interrupted = false
    }

    private struct PendingFire {
        var shortcut: Shortcut
        var deadline: TimeInterval
    }

    private var active: [(shortcut: Shortcut, trigger: Trigger)] = []
    private var taps: [Tap] = []
    private var lonePress: LonePress?
    private var pending: PendingFire?
    private var held: [KeyEvent] = []
    private var heldDeadline: TimeInterval?
    private var swallowed: Set<UInt16> = []
    private var mods: Modifiers = []
    private var comboStart: TimeInterval = 0
    private var comboPeak: Modifiers = []
    private var comboInterrupted = false
    private var lastDeadline: TimeInterval?

    public init() {}

    public func handle(_ e: KeyEvent) -> Verdict {
        let verdict: Verdict
        switch e.kind {
        case .keyDown: verdict = keyDown(e)
        case .keyUp: verdict = keyUp(e)
        case .flagsChanged: verdict = flagsChanged(e)
        case .mouseDown:
            mouseDown()
            verdict = .pass
        }
        publishDeadline()
        return verdict
    }

    public func tick(now: TimeInterval) {
        if let d = heldDeadline, now >= d {
            flushHeld()
        }
        if let p = pending, now >= p.deadline {
            pending = nil
            taps = []
            onFire(p.shortcut)
        }
        publishDeadline()
    }

    /// Drops all in-flight state, replaying anything held back.
    public func reset() {
        flushHeld()
        taps = []
        lonePress = nil
        pending = nil
        comboInterrupted = true
        publishDeadline()
    }

    // MARK: - Event handling

    private func keyDown(_ e: KeyEvent) -> Verdict {
        let k = e.keyCode
        if e.isRepeat {
            return swallowed.contains(k) || held.contains { $0.keyCode == k } ? .swallow : .pass
        }
        lonePress?.interrupted = true
        comboInterrupted = true

        var flushed: [KeyEvent] = []
        if !held.isEmpty {
            let keys = held.map(\.keyCode) + [k]
            if let s = comboMatch(e.modifiers, keys) {
                held = []
                heldDeadline = nil
                swallowed.formUnion(keys)
                taps = []
                onFire(s)
                return .swallow
            }
            if comboPrefix(e.modifiers, keys) {
                held.append(e)
                return .swallow
            }
            flushed = held
            held = []
            heldDeadline = nil
        }

        let verdict = freshKeyDown(e)
        guard !flushed.isEmpty else { return verdict }
        // Replay the held keys and this one together so they stay in order.
        onReplay(flushed + (verdict == .pass ? [e] : []))
        return .swallow
    }

    private func freshKeyDown(_ e: KeyEvent) -> Verdict {
        let k = e.keyCode
        if pending != nil, taps.last?.keyCode != k {
            resolvePending()
        }
        if let s = comboMatch(e.modifiers, [k]) {
            taps = []
            swallowed.insert(k)
            onFire(s)
            return .swallow
        }
        if comboPrefix(e.modifiers, [k]) {
            held = [e]
            heldDeadline = e.time + chordWindow
            return .swallow
        }
        guard e.modifiers.isEmpty else {
            taps = []
            return .pass
        }
        if let last = taps.last, last.keyCode != k {
            taps = []
        }
        if registerTap(k, start: e.time, end: e.time) {
            swallowed.insert(k)
            return .swallow
        }
        return .pass
    }

    private func keyUp(_ e: KeyEvent) -> Verdict {
        let k = e.keyCode
        if swallowed.remove(k) != nil {
            return .swallow
        }
        if held.contains(where: { $0.keyCode == k }) {
            // Released before the combo completed: let it through as typed.
            let events = held + [e]
            held = []
            heldDeadline = nil
            onReplay(events)
            return .swallow
        }
        return .pass
    }

    private func flagsChanged(_ e: KeyEvent) -> Verdict {
        let k = e.keyCode
        let before = mods
        mods = e.modifiers

        if before.isEmpty, !mods.isEmpty {
            comboStart = e.time
            comboPeak = mods
            comboInterrupted = false
        } else {
            comboPeak.formUnion(mods)
        }
        if !before.isEmpty, mods.isEmpty, !comboInterrupted, comboPeak.count >= 2,
           e.time - comboStart <= maxModifierComboHold, let s = modifierComboMatch(comboPeak) {
            taps = []
            lonePress = nil
            onFire(s)
            return flushingHeld(e)
        }

        guard let family = KeyCode.family(of: k) else { return flushingHeld(e) }

        if e.isDown {
            if pending != nil, let last = taps.last, KeyCode.family(of: last.keyCode) != family {
                resolvePending()
            }
            if before.isEmpty {
                lonePress = LonePress(keyCode: k, start: e.time)
            } else {
                lonePress = nil
                taps = []
            }
        } else if let p = lonePress, p.keyCode == k {
            lonePress = nil
            if !p.interrupted, e.time - p.start <= maxTapHold {
                registerTap(k, start: p.start, end: e.time)
            } else {
                taps = []
            }
        } else {
            lonePress = nil
        }
        return flushingHeld(e)
    }

    private func mouseDown() {
        lonePress?.interrupted = true
        comboInterrupted = true
        taps = []
        resolvePending()
        flushHeld()
    }

    // MARK: - Taps

    /// Records a tap and fires any matching tap trigger. Returns whether a trigger matched.
    @discardableResult
    private func registerTap(_ k: UInt16, start: TimeInterval, end: TimeInterval) -> Bool {
        if let last = taps.last, start - last.end > doubleTapInterval {
            taps = []
        }
        taps.append(Tap(keyCode: k, end: end))

        let family = KeyCode.family(of: k)
        let exactCount = trailingCount { $0.keyCode == k }
        let familyCount = family.map { f in trailingCount { KeyCode.family(of: $0.keyCode) == f } } ?? exactCount

        var match: Shortcut?
        var higher = false
        for (s, t) in active where t.kind == .tap {
            let count: Int
            if t.eitherSide, let family, KeyCode.family(of: t.keyCode) == family {
                count = familyCount
            } else if t.keyCode == k {
                count = exactCount
            } else {
                continue
            }
            if t.tapCount == count {
                if match == nil { match = s }
            } else if t.tapCount > count {
                higher = true
            }
        }

        guard let s = match else { return false }
        if higher {
            // A triple tap on the same key is also configured: wait to see if it comes.
            pending = PendingFire(shortcut: s, deadline: end + doubleTapInterval)
        } else {
            pending = nil
            taps = []
            onFire(s)
        }
        return true
    }

    private func trailingCount(_ predicate: (Tap) -> Bool) -> Int {
        var n = 0
        for tap in taps.reversed() {
            guard predicate(tap) else { break }
            n += 1
        }
        return n
    }

    private func resolvePending() {
        guard let p = pending else { return }
        pending = nil
        taps = []
        onFire(p.shortcut)
    }

    // MARK: - Combos

    private func comboMatch(_ modifiers: Modifiers, _ keys: [UInt16]) -> Shortcut? {
        let set = Set(keys)
        return active.first { s, t in
            t.kind == .combo && !t.keys.isEmpty && t.modifiers == modifiers && Set(t.keys) == set
        }?.shortcut
    }

    /// Whether `keys` could still grow into a configured multi-key combo.
    private func comboPrefix(_ modifiers: Modifiers, _ keys: [UInt16]) -> Bool {
        let set = Set(keys)
        return active.contains { _, t in
            t.kind == .combo && t.modifiers == modifiers && Set(t.keys).isStrictSuperset(of: set)
        }
    }

    private func modifierComboMatch(_ modifiers: Modifiers) -> Shortcut? {
        active.first { _, t in t.kind == .combo && t.keys.isEmpty && t.modifiers == modifiers }?.shortcut
    }

    // MARK: - Held keys

    private func flushHeld() {
        guard !held.isEmpty else { return }
        let events = held
        held = []
        heldDeadline = nil
        onReplay(events)
    }

    /// Passes `e` through, unless keys are held back, in which case it is replayed after them.
    private func flushingHeld(_ e: KeyEvent) -> Verdict {
        guard !held.isEmpty else { return .pass }
        let events = held + [e]
        held = []
        heldDeadline = nil
        onReplay(events)
        return .swallow
    }

    // MARK: - Housekeeping

    private func rebuild() {
        active = shortcuts.filter(\.enabled).flatMap { s in
            s.triggers.filter(\.isComplete).map { (shortcut: s, trigger: $0) }
        }
        pending = nil
        flushHeld()
        publishDeadline()
    }

    private func publishDeadline() {
        let deadline = [heldDeadline, pending?.deadline].compactMap { $0 }.min()
        guard deadline != lastDeadline else { return }
        lastDeadline = deadline
        onDeadlineChange(deadline)
    }
}
