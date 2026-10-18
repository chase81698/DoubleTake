import Foundation
import Testing
@testable import DoubleTakeCore

@Suite struct SpecTests {
    @Test(arguments: ["double:fn", "triple:right-cmd", "double:cmd", "double:esc", "ctrl+opt+t", "cmd+shift+k", "j+k", "ctrl+opt", "double:f5"])
    func roundTrips(_ spec: String) throws {
        #expect(Spec.format(try Spec.parseTrigger(spec)) == spec)
    }

    @Test func bareModifierMeansEitherSide() throws {
        let t = try Spec.parseTrigger("double:opt")
        #expect(t.kind == .tap && t.eitherSide && KeyCode.family(of: t.keyCode) == .option)
        #expect(try Spec.parseTrigger("double:right-opt").eitherSide == false)
    }

    @Test func comboAcceptsAliasesInAnyOrder() throws {
        let t = try Spec.parseTrigger("T+Option+Control")
        #expect(t.modifiers == [.control, .option] && t.keys == [17])
    }

    @Test func rejectsBadSpecs() {
        #expect(throws: Spec.ParseError.self) { try Spec.parseTrigger("double:banana") }
        #expect(throws: Spec.ParseError.self) { try Spec.parseTrigger("cmd") }
        #expect(throws: Spec.ParseError.self) { try Spec.parseTrigger("quadruple:fn") }
        #expect(throws: Spec.ParseError.self) { try Spec.parseKeystroke("cmd+a+b") }
    }

    @Test func keystrokes() throws {
        let k = try Spec.parseKeystroke("cmd+shift+t")
        #expect(k == Keystroke(modifiers: [.command, .shift], keyCode: 17))
        #expect(Spec.format(k) == "cmd+shift+t")
    }

    @Test func sparseJSONGetsDefaults() throws {
        let json = #"{"shortcuts":[{"name":"Hi","triggers":[{"keyCode":63}],"action":{"type":"shellScript","script":"say hi"}}]}"#
        let config = try ConfigFile.decode(Data(json.utf8))
        let s = try #require(config.shortcuts.first)
        #expect(s.enabled && s.triggers[0].kind == .tap && s.triggers[0].tapCount == 2 && s.triggers[0].isComplete)
        #expect(config.settings == AppSettings())
        #expect(config.index(of: "hi") == 0)
        #expect(config.index(of: s.shortID) == 0)
    }

    @Test func configRoundTrips() throws {
        let config = ConfigFile(shortcuts: [Shortcut(name: "A", triggers: [.combo([.command], [40])], action: .system(.siri))])
        #expect(try ConfigFile.decode(config.encoded()) == config)
    }
}
