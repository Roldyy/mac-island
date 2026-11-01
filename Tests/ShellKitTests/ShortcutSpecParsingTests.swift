import AppKit
import Testing
@testable import ShellKit

@Suite struct ShortcutSpecParsingTests {
    @Test func numberAfterColonIsAKeyCode() throws {
        let s = try #require(ShortcutSpec.parse("option+command:9"))   // Vorssaint: 9 = V
        #expect(s.keyCode == 9 && s.key == "v" && s.display == "⌥⌘V")
    }

    @Test func threeSpellingsOfOneCombination() throws {
        let a = try #require(ShortcutSpec.parse("option+command:9"))
        #expect(a == ShortcutSpec.parse("option+command+v"))
        #expect(a == ShortcutSpec.parse("option+command:v"))
        #expect(ShortcutSpec.parse("control+option+command:40") == .keepAwakeDefault)
        #expect(ShortcutSpec.parse("control+option+command+k") == .keepAwakeDefault)
    }

    @Test func digitKeyIsRecordedByCodeAndReadsBack() throws {
        let nine = try #require(ShortcutSpec.from(keyCode: 25, flags: [.option, .command]))
        #expect(nine.key == "9")
        #expect(nine.stored == "option+command:25")
        #expect(ShortcutSpec.parse(nine.stored) == nine)
    }

    @Test func rejectsWhatIsNotAShortcut() {
        #expect(ShortcutSpec.parse("shift:a") == nil)
        #expect(ShortcutSpec.parse("command:200") == nil)
        #expect(ShortcutSpec.parse("command+") == nil)
        #expect(ShortcutSpec.parse("hyper+command:9") == nil)
        #expect(ShortcutSpec.parse("a:b:c") == nil)
    }
}
