import Foundation

/// Captures the keys a user presses while setting up a trigger or keystroke.
public final class KeyRecorder {
    public enum Mode: Sendable {
        /// A single key to be tapped (modifiers count on release).
        case tap
        /// Everything held together, finished when all keys are released.
        case combo
        /// Modifiers plus one ordinary key, finished on key down.
        case keystroke
    }

    public enum Result: Equatable, Sendable {
        case tap(UInt16)
        case combo(Modifiers, [UInt16])
        case keystroke(Keystroke)
    }

    public let mode: Mode
    private var keys: [UInt16] = []
    private var down: Set<UInt16> = []
    private var peak: Modifiers = []
    private var loneModifier: UInt16?

    public init(mode: Mode) {
        self.mode = mode
    }

    /// Feeds an event; returns the result once recording is complete.
    public func handle(_ e: KeyEvent) -> Result? {
        switch e.kind {
        case .keyDown:
            guard !e.isRepeat else { return nil }
            loneModifier = nil
            switch mode {
            case .tap:
                return .tap(e.keyCode)
            case .keystroke:
                return .keystroke(Keystroke(modifiers: e.modifiers, keyCode: e.keyCode))
            case .combo:
                if !keys.contains(e.keyCode) { keys.append(e.keyCode) }
                down.insert(e.keyCode)
                peak.formUnion(e.modifiers)
            }

        case .keyUp:
            down.remove(e.keyCode)
            if mode == .combo { return finishCombo(e.modifiers) }

        case .flagsChanged:
            guard let family = KeyCode.family(of: e.keyCode) else { return nil }
            peak.formUnion(e.modifiers)
            if e.isDown {
                loneModifier = e.modifiers == family && keys.isEmpty ? e.keyCode : nil
            } else if mode == .tap, loneModifier == e.keyCode {
                return .tap(e.keyCode)
            }
            if mode == .combo { return finishCombo(e.modifiers) }

        case .mouseDown:
            break
        }
        return nil
    }

    private func finishCombo(_ modifiers: Modifiers) -> Result? {
        guard down.isEmpty, modifiers.isEmpty else { return nil }
        defer {
            keys = []
            peak = []
        }
        if !keys.isEmpty { return .combo(peak, keys) }
        if peak.count >= 2 { return .combo(peak, []) }
        return nil
    }
}
