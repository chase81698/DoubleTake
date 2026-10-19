import Testing
@testable import DoubleTakeCore

private let kJ: UInt16 = 38, kK: UInt16 = 40, kT: UInt16 = 17, kEsc: UInt16 = 53

@Suite struct PermissionTests {
    @Test func actionsThatPressKeysOrClickMenusNeedCustomActions() {
        var keystroke = Action()
        keystroke.type = .keystroke
        var menu = Action()
        menu.type = .menuItem
        #expect(keystroke.needsCustomActions)
        #expect(menu.needsCustomActions)
        for s in [SystemAction.dictation, .spotlight, .lockScreen, .emojiPicker, .playPause, .nextTrack, .previousTrack,
                  .accessibilityShortcuts] {
            #expect(Action.system(s).needsCustomActions, "\(s)")
        }
    }

    @Test func actionsThatOpenOrRunThingsDont() {
        for type in [ActionType.openApp, .openURL, .shellScript, .appleScript, .runShortcut] {
            var a = Action()
            a.type = type
            #expect(!a.needsCustomActions, "\(type)")
        }
        for s in [SystemAction.siri, .missionControl, .showDesktop, .screenSaver, .screenshot, .toggleDarkMode,
                  .toggleMute, .volumeUp, .volumeDown, .hideOthers, .quitFrontApp] {
            #expect(!Action.system(s).needsCustomActions, "\(s)")
        }
    }

    @Test func onlyMultiKeyCombosNeedCustomActions() {
        #expect(Trigger.combo([], [kJ, kK]).needsCustomActions)
        #expect(!Trigger.combo([.control, .option], [kT]).needsCustomActions)
        #expect(!Trigger.combo([.control, .option], []).needsCustomActions)
        #expect(!Trigger.tap(KeyCode.function).needsCustomActions)
        #expect(!Trigger.tap(kEsc).needsCustomActions)
    }

    @Test func whichTriggersLetTheirKeyThrough() {
        #expect(Trigger.combo([.control, .option], [kT]).passesKeyThroughWithoutCustomActions)
        #expect(Trigger.tap(kEsc).passesKeyThroughWithoutCustomActions)
        #expect(!Trigger.tap(KeyCode.function).passesKeyThroughWithoutCustomActions)
        #expect(!Trigger.tap(KeyCode.rightCommand, count: 3).passesKeyThroughWithoutCustomActions)
        #expect(!Trigger.combo([.control, .option], []).passesKeyThroughWithoutCustomActions)
    }

    @Test func shortcutNeedsCustomActionsForItsActionOrAnyTrigger() {
        let open = Action()
        var app = open
        app.type = .openApp
        #expect(!Shortcut(name: "a", triggers: [.tap(KeyCode.function)], action: app).needsCustomActions)
        #expect(Shortcut(name: "b", triggers: [.tap(KeyCode.function), .combo([], [kJ, kK])], action: app).needsCustomActions)
        #expect(Shortcut(name: "c", triggers: [.tap(KeyCode.function)], action: .system(.dictation)).needsCustomActions)
    }
}

@Suite struct WatchOnlyEngineTests {
    func engine(_ shortcuts: [Shortcut]) -> (Engine, () -> [String], () -> Int) {
        let engine = Engine()
        engine.canHoldKeys = false
        engine.shortcuts = shortcuts
        var fired: [String] = []
        var replays = 0
        engine.onFire = { fired.append($0.name) }
        engine.onReplay = { _ in replays += 1 }
        return (engine, { fired }, { replays })
    }

    func key(_ e: Engine, _ code: UInt16, _ down: Bool, _ time: Double, mods: Modifiers = [], token: Int) -> Verdict {
        e.handle(KeyEvent(kind: down ? .keyDown : .keyUp, keyCode: code, modifiers: mods, isDown: down, time: time, token: token))
    }

    @Test func multiKeyCombosAreIgnoredAndNothingIsHeld() {
        var app = Action()
        app.type = .openApp
        let (e, fired, replays) = engine([Shortcut(name: "jk", triggers: [.combo([], [kJ, kK])], action: app)])
        #expect(key(e, kJ, true, 100, token: 1) == .pass)
        #expect(key(e, kK, true, 100.02, token: 2) == .pass)
        e.tick(now: 101)
        #expect(fired().isEmpty)
        #expect(replays() == 0)
    }

    @Test func modifierCombosStillFire() {
        var app = Action()
        app.type = .openApp
        let (e, fired, _) = engine([Shortcut(name: "term", triggers: [.combo([.control, .option], [kT])], action: app)])
        _ = key(e, kT, true, 100, mods: [.control, .option], token: 1)
        #expect(fired() == ["term"])
    }

    @Test func turningHoldingBackOnRestoresMultiKeyCombos() {
        var app = Action()
        app.type = .openApp
        let (e, fired, _) = engine([Shortcut(name: "jk", triggers: [.combo([], [kJ, kK])], action: app)])
        e.canHoldKeys = true
        _ = key(e, kJ, true, 100, token: 1)
        _ = key(e, kK, true, 100.02, token: 2)
        #expect(fired() == ["jk"])
    }
}
