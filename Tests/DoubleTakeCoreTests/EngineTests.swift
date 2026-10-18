import Testing
@testable import DoubleTakeCore

/// Drives an Engine with synthetic events on a fake clock.
final class Harness {
    let engine = Engine()
    var fired: [String] = []
    var replayed: [[Int]] = []
    var now: Double = 100
    var token = 0
    var mods: Modifiers = []

    init(_ shortcuts: [Shortcut]) {
        engine.shortcuts = shortcuts
        engine.onFire = { [unowned self] in fired.append($0.name) }
        engine.onReplay = { [unowned self] in replayed.append($0.map(\.token)) }
    }

    func wait(_ seconds: Double) {
        now += seconds
        engine.tick(now: now)
    }

    @discardableResult
    func modifier(_ code: UInt16, down: Bool) -> Verdict {
        let f = KeyCode.family(of: code)!
        if down { mods.insert(f) } else { mods.remove(f) }
        return send(.flagsChanged, code, isDown: down)
    }

    func tapModifier(_ code: UInt16, hold: Double = 0.05) {
        modifier(code, down: true)
        wait(hold)
        modifier(code, down: false)
    }

    @discardableResult
    func key(_ code: UInt16, down: Bool, isRepeat: Bool = false) -> Verdict {
        send(down ? .keyDown : .keyUp, code, isRepeat: isRepeat)
    }

    func send(_ kind: KeyEventKind, _ code: UInt16, isDown: Bool = false, isRepeat: Bool = false) -> Verdict {
        token += 1
        return engine.handle(KeyEvent(kind: kind, keyCode: code, modifiers: mods, isDown: isDown,
                                      isRepeat: isRepeat, time: now, token: token))
    }
}

private func shortcut(_ name: String, _ triggers: Trigger...) -> Shortcut {
    Shortcut(name: name, triggers: triggers, action: Action())
}

private let kJ: UInt16 = 38
private let kK: UInt16 = 40
private let kT: UInt16 = 17
private let kC: UInt16 = 8

@Suite struct DoubleTapTests {
    @Test func doubleTapFn() {
        let h = Harness([shortcut("dictation", .tap(KeyCode.function))])
        h.tapModifier(KeyCode.function)
        #expect(h.fired.isEmpty)
        h.wait(0.1)
        h.tapModifier(KeyCode.function)
        #expect(h.fired == ["dictation"])
    }

    @Test func tooSlowDoesNotFire() {
        let h = Harness([shortcut("x", .tap(KeyCode.command))])
        h.tapModifier(KeyCode.command)
        h.wait(0.5)
        h.tapModifier(KeyCode.command)
        #expect(h.fired.isEmpty)
    }

    @Test func longHoldIsNotATap() {
        let h = Harness([shortcut("x", .tap(KeyCode.command))])
        h.tapModifier(KeyCode.command, hold: 0.8)
        h.wait(0.05)
        h.tapModifier(KeyCode.command)
        #expect(h.fired.isEmpty)
    }

    @Test func usingModifierInAShortcutIsNotATap() {
        let h = Harness([shortcut("x", .tap(KeyCode.command))])
        // ⌘C then ⌘V quickly must not count as a double tap of ⌘.
        h.modifier(KeyCode.command, down: true)
        h.key(kC, down: true)
        h.key(kC, down: false)
        h.modifier(KeyCode.command, down: false)
        h.wait(0.05)
        h.tapModifier(KeyCode.command)
        #expect(h.fired.isEmpty)
    }

    @Test func sideSpecific() {
        let h = Harness([shortcut("right", .tap(KeyCode.rightCommand))])
        h.tapModifier(KeyCode.command)
        h.wait(0.05)
        h.tapModifier(KeyCode.command)
        #expect(h.fired.isEmpty)
        h.wait(0.5)
        h.tapModifier(KeyCode.rightCommand)
        h.wait(0.05)
        h.tapModifier(KeyCode.rightCommand)
        #expect(h.fired == ["right"])
    }

    @Test func eitherSideAcceptsMixedSides() {
        let h = Harness([shortcut("either", .tap(KeyCode.command, eitherSide: true))])
        h.tapModifier(KeyCode.command)
        h.wait(0.05)
        h.tapModifier(KeyCode.rightCommand)
        #expect(h.fired == ["either"])
    }

    @Test func doubleWaitsForTripleThenFires() {
        let h = Harness([
            shortcut("double", .tap(KeyCode.option)),
            shortcut("triple", .tap(KeyCode.option, count: 3)),
        ])
        h.tapModifier(KeyCode.option)
        h.wait(0.05)
        h.tapModifier(KeyCode.option)
        #expect(h.fired.isEmpty)
        h.wait(0.35)
        #expect(h.fired == ["double"])
    }

    @Test func tripleTap() {
        let h = Harness([
            shortcut("double", .tap(KeyCode.option)),
            shortcut("triple", .tap(KeyCode.option, count: 3)),
        ])
        for _ in 0..<3 {
            h.tapModifier(KeyCode.option)
            h.wait(0.05)
        }
        h.wait(1)
        #expect(h.fired == ["triple"])
    }

    @Test func pendingDoubleFiresWhenOtherKeyPressed() {
        let h = Harness([
            shortcut("double", .tap(KeyCode.option)),
            shortcut("triple", .tap(KeyCode.option, count: 3)),
        ])
        h.tapModifier(KeyCode.option)
        h.wait(0.05)
        h.tapModifier(KeyCode.option)
        h.key(kJ, down: true)
        #expect(h.fired == ["double"])
    }

    @Test func doubleTapRegularKeySwallowsSecondPress() {
        let h = Harness([shortcut("esc", .tap(KeyCode.escape))])
        #expect(h.key(KeyCode.escape, down: true) == .pass)
        #expect(h.key(KeyCode.escape, down: false) == .pass)
        h.wait(0.1)
        #expect(h.key(KeyCode.escape, down: true) == .swallow)
        #expect(h.key(KeyCode.escape, down: false) == .swallow)
        #expect(h.fired == ["esc"])
    }

    @Test func disabledShortcutDoesNotFire() {
        var s = shortcut("x", .tap(KeyCode.function))
        s.enabled = false
        let h = Harness([s])
        h.tapModifier(KeyCode.function)
        h.wait(0.05)
        h.tapModifier(KeyCode.function)
        #expect(h.fired.isEmpty)
    }
}

@Suite struct ComboTests {
    @Test func modifierCombo() {
        let h = Harness([shortcut("term", .combo([.control, .option], [kT]))])
        h.modifier(KeyCode.control, down: true)
        h.modifier(KeyCode.option, down: true)
        #expect(h.key(kT, down: true) == .swallow)
        #expect(h.key(kT, down: true, isRepeat: true) == .swallow)
        #expect(h.key(kT, down: false) == .swallow)
        #expect(h.fired == ["term"])
    }

    @Test func wrongModifiersPassThrough() {
        let h = Harness([shortcut("term", .combo([.control, .option], [kT]))])
        h.modifier(KeyCode.control, down: true)
        #expect(h.key(kT, down: true) == .pass)
        #expect(h.fired.isEmpty)
    }

    @Test func simultaneousKeys() {
        let h = Harness([shortcut("jk", .combo([], [kJ, kK]))])
        #expect(h.key(kJ, down: true) == .swallow) // held back
        h.wait(0.02)
        #expect(h.key(kK, down: true) == .swallow)
        #expect(h.fired == ["jk"])
        #expect(h.key(kJ, down: false) == .swallow)
        #expect(h.key(kK, down: false) == .swallow)
        #expect(h.replayed.isEmpty)
    }

    @Test func simultaneousKeysInEitherOrder() {
        let h = Harness([shortcut("jk", .combo([], [kJ, kK]))])
        h.key(kK, down: true)
        h.key(kJ, down: true)
        #expect(h.fired == ["jk"])
    }

    @Test func heldKeyIsReplayedAfterTimeout() {
        let h = Harness([shortcut("jk", .combo([], [kJ, kK]))])
        h.key(kJ, down: true) // token 1
        h.wait(0.2)
        #expect(h.replayed == [[1]])
        #expect(h.key(kJ, down: false) == .pass)
        #expect(h.fired.isEmpty)
    }

    @Test func heldKeyReleasedEarlyIsReplayedWithItsRelease() {
        let h = Harness([shortcut("jk", .combo([], [kJ, kK]))])
        h.key(kJ, down: true) // 1
        #expect(h.key(kJ, down: false) == .swallow) // 2
        #expect(h.replayed == [[1, 2]])
    }

    @Test func otherKeyFlushesHeldKeyInOrder() {
        let h = Harness([shortcut("jk", .combo([], [kJ, kK]))])
        h.key(kJ, down: true) // 1
        #expect(h.key(kT, down: true) == .swallow) // 2, replayed after J
        #expect(h.replayed == [[1, 2]])
    }

    @Test func modifierOnlyCombo() {
        let h = Harness([shortcut("ctlopt", .combo([.control, .option], []))])
        h.modifier(KeyCode.control, down: true)
        h.modifier(KeyCode.option, down: true)
        h.wait(0.1)
        h.modifier(KeyCode.option, down: false)
        h.modifier(KeyCode.control, down: false)
        #expect(h.fired == ["ctlopt"])
    }

    @Test func modifierOnlyComboIgnoredWhenUsedWithAKey() {
        let h = Harness([shortcut("ctlopt", .combo([.control, .option], []))])
        h.modifier(KeyCode.control, down: true)
        h.modifier(KeyCode.option, down: true)
        h.key(kT, down: true)
        h.key(kT, down: false)
        h.modifier(KeyCode.option, down: false)
        h.modifier(KeyCode.control, down: false)
        #expect(h.fired.isEmpty)
    }
}

@Suite struct RecorderTests {
    @Test func recordsModifierTap() {
        let r = KeyRecorder(mode: .tap)
        #expect(r.handle(KeyEvent(kind: .flagsChanged, keyCode: KeyCode.rightCommand, modifiers: .command, isDown: true, time: 0)) == nil)
        #expect(r.handle(KeyEvent(kind: .flagsChanged, keyCode: KeyCode.rightCommand, modifiers: [], isDown: false, time: 0.1)) == .tap(KeyCode.rightCommand))
    }

    @Test func recordsCombo() {
        let r = KeyRecorder(mode: .combo)
        _ = r.handle(KeyEvent(kind: .flagsChanged, keyCode: KeyCode.command, modifiers: .command, isDown: true, time: 0))
        _ = r.handle(KeyEvent(kind: .keyDown, keyCode: kK, modifiers: .command, time: 0))
        #expect(r.handle(KeyEvent(kind: .keyUp, keyCode: kK, modifiers: .command, time: 0)) == nil)
        #expect(r.handle(KeyEvent(kind: .flagsChanged, keyCode: KeyCode.command, modifiers: [], isDown: false, time: 0)) == .combo(.command, [kK]))
    }

    @Test func recordsKeystroke() {
        let r = KeyRecorder(mode: .keystroke)
        #expect(r.handle(KeyEvent(kind: .keyDown, keyCode: kT, modifiers: [.command, .shift], time: 0))
            == .keystroke(Keystroke(modifiers: [.command, .shift], keyCode: kT)))
    }
}
