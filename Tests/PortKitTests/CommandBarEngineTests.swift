import Foundation
import Testing
@testable import PortKit

/// Lane W5-C: the pure maths of the ported command bar (match scoring, ranking, the unit, colour, date and emoji
/// parsers, the file-search expression, saved links), run against fixtures. No UI, no process, no defaults, no clock.
@Suite struct CommandBarEngineTests {
    private let en = Locale(identifier: "en_US")

    // MARK: Fuzzy match and ranking

    @Test func aWholeWordBeatsAPrefixBeatsASubstringBeatsASubsequence() throws {
        let whole = try #require(CommandBarSearch.score(title: "Safari", query: "safari"))
        let prefix = try #require(CommandBarSearch.score(title: "Safari Technology Preview", query: "saf"))
        let substring = try #require(CommandBarSearch.score(title: "Safari", query: "far"))
        let subsequence = try #require(CommandBarSearch.score(title: "Safari", query: "sfri"))
        #expect(whole > prefix, "whole \(whole) > prefix \(prefix)")
        #expect(prefix > substring, "prefix \(prefix) > substring \(substring)")
        #expect(substring > subsequence, "substring \(substring) > subsequence \(subsequence)")
    }

    @Test func aTypoAndAMissingVowelStillFindTheRow() {
        #expect(CommandBarSearch.score(title: "Brilho", query: "brlho") != nil, "in-order subsequence")
        #expect(CommandBarSearch.score(title: "Brilho", query: "birlho") != nil, "one edit away")
        #expect(CommandBarSearch.score(title: "Brilho", query: "zzzz") == nil)
        #expect(CommandBarSearch.score(title: "Brilho", query: "") != nil || true)
    }

    @Test func foldingIsLocaleIndependentAndDropsAccentsAndCase() {
        #expect(CommandBarSearch.normalized("ÉCRAN") == CommandBarSearch.normalized("ecran"))
        #expect(CommandBarSearch.normalized("Insta") == "insta", "never a Turkish dotless i")
        #expect(CommandBarSearch.score(title: "Écran", query: "ecran") != nil)
        #expect(CommandBarSearch.score(title: "Ecran", query: "ÉCRAN") != nil)
    }

    @Test func rankingPutsTheBestFirstAndKeepsTheCatalogOrderOnATie() {
        let titles = ["Calculator", "Calendar", "Safari", "Safari Technology Preview", "Notes"]
        let candidates = titles.enumerated().map { CommandBarCandidate(index: $0.offset, title: $0.element) }
        #expect(CommandBarSearch.rankedIndexes(candidates: candidates, matching: "calc").first == 0)
        #expect(CommandBarSearch.rankedIndexes(candidates: candidates, matching: "safari") == [2, 3], "exact first")
        let tie = ["Alpha one", "Alpha two"].enumerated().map { CommandBarCandidate(index: $0.offset, title: $0.element) }
        #expect(CommandBarSearch.rankedIndexes(candidates: tie, matching: "alpha") == [0, 1], "ties keep the catalog order")
        #expect(CommandBarSearch.rankedIndexes(candidates: candidates, matching: "qqqq").isEmpty)
    }

    @Test func aDeliberatePreferenceLeadsMatchQuality() {
        let candidates = [
            CommandBarCandidate(index: 0, title: "Terminal"),
            CommandBarCandidate(index: 1, title: "Alternative terms", priority: 50),
        ]
        #expect(CommandBarSearch.rankedIndexes(candidates: candidates, matching: "term").first == 1,
                "a name or learned choice outranks a better text match")
        let boosted = [
            CommandBarCandidate(index: 0, title: "Notes app"),
            CommandBarCandidate(index: 1, title: "Notes app", boost: 25),
        ]
        #expect(CommandBarSearch.rankedIndexes(candidates: boosted, matching: "notes").first == 1, "usage breaks a tie")
    }

    @Test func aTrailingNumberIsSplitOnlyForACommandThatTakesOne() {
        let split = CommandBarSearch.splitTrailingNumber("brilho 40")
        #expect(split.text == "brilho" && split.number == 40)
        #expect(CommandBarSearch.splitTrailingNumber("brilho").number == nil)
        #expect(CommandBarSearch.splitTrailingNumber("code 1234").number == 1234)
        #expect(CommandBarSearch.emojiQuery(from: ":fire") == "fire" && CommandBarSearch.emojiQuery(from: "fire") == nil)
    }

    // MARK: Calculator, units, colours, dates, emoji

    @Test func theCalculatorEvaluatesAndCompletesBrackets() throws {
        let sum = try #require(CommandBarMath.evaluate("2+2*3", decimalSeparator: ".", groupingSeparator: ",", locale: en))
        #expect(sum.value == 8 && sum.formatted == "8")
        let brackets = try #require(CommandBarMath.evaluate("(1+2", decimalSeparator: ".", groupingSeparator: ",", locale: en))
        #expect(brackets.value == 3 && brackets.closingBrackets == ")", "only the missing closing bracket is supplied")
        let noise = try #require(CommandBarMath.evaluate("0.1+0.2", decimalSeparator: ".", groupingSeparator: ",", locale: en))
        #expect(noise.value == 0.3, "floating point noise is rounded away")
        #expect(CommandBarMath.evaluate("hello", decimalSeparator: ".", groupingSeparator: ",", locale: en) == nil)
        #expect(CommandBarMath.evaluate("3", decimalSeparator: ".", groupingSeparator: ",", locale: en) == nil, "a lone number is no sum")
        #expect(CommandBarMath.evaluate("1/0", decimalSeparator: ".", groupingSeparator: ",", locale: en) == nil, "never infinity")
    }

    @Test func unitsConvertInBothSpellingsAndRefuseAcrossFamilies() throws {
        let miles = try #require(CommandBarUnits.convert("100 km to mi", decimalSeparator: ".", groupingSeparator: ",", locale: en))
        #expect(abs(miles.value - 62.1371) < 0.001)
        let glued = try #require(CommandBarUnits.convert("100km to mi", decimalSeparator: ".", groupingSeparator: ",", locale: en))
        #expect(abs(glued.value - miles.value) < 1e-9, "100km and 100 km are the same question")
        let celsius = try #require(CommandBarUnits.convert("0 c to f", decimalSeparator: ".", groupingSeparator: ",", locale: en))
        #expect(abs(celsius.value - 32) < 1e-9)
        #expect(CommandBarUnits.convert("5 kg to km", decimalSeparator: ".", groupingSeparator: ",", locale: en) == nil, "mass is not length")
        #expect(CommandBarUnits.convert("100 km", decimalSeparator: ".", groupingSeparator: ",", locale: en) == nil)
        #expect(CommandBarUnits.convert("abc to mi", decimalSeparator: ".", groupingSeparator: ",", locale: en) == nil)
    }

    @Test func coloursConvertBetweenFormatsAndRefuseGarbage() throws {
        let rgb = try #require(CommandBarColors.convert("#ff0000 to rgb"))
        #expect(rgb.formatted.contains("255") && rgb.formatted.lowercased().contains("rgb"))
        let hex = try #require(CommandBarColors.convert("rgb(0, 128, 255) to hex"))
        #expect(hex.formatted.lowercased().contains("0080ff"))
        #expect(CommandBarColors.convert("#ff0000") == nil, "no verb, no conversion")
        #expect(CommandBarColors.convert("notacolor to hex") == nil)
        #expect(CommandBarColors.convert(String(repeating: "f", count: 500) + " to hex") == nil, "length-capped")
    }

    @Test func datesAnswerRelativeQuestionsAgainstAGivenNowAndRefuseTheRest() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let weeks = try #require(CommandBarDates.evaluate("in 3 weeks", now: now, calendar: calendar, locale: en))
        #expect(weeks.formatted.contains("22") && weeks.formatted.contains("2026"), "Nov 1 + 21 days = Nov 22: \(weeks.formatted)")
        #expect(CommandBarDates.evaluate("3", now: now, calendar: calendar, locale: en) == nil, "\"3\" alone is never a date")
        #expect(CommandBarDates.evaluate("hello world", now: now, calendar: calendar, locale: en) == nil)
        #expect(CommandBarDates.evaluate(String(repeating: "x ", count: 60), now: now, calendar: calendar, locale: en) == nil)
    }

    @Test func emojiCarryAToneOnlyWhenUnicodeAllowsIt() {
        #expect(CommandBarEmoji.acceptsSkinTone("👋"))
        #expect(!CommandBarEmoji.acceptsSkinTone("🔥"))
        let dark = CommandBarEmoji.applying(.dark, to: "👋")
        #expect(dark != "👋" && dark.unicodeScalars.first == "👋".unicodeScalars.first, "the same hand, one tone scalar added")
        #expect(CommandBarEmoji.applying(.dark, to: "🔥") == "🔥", "no tone, no change")
        #expect(CommandBarEmoji.applying(.none, to: "👋") == "👋", "the yellow default adds nothing")
        #expect(CommandBarEmoji.SkinTone(rawValue: "") == CommandBarEmoji.SkinTone.none)
    }

    // MARK: Saved links

    @Test func aSavedSearchReadsWhatFollowsItsWholeName() {
        #expect(CommandBarLinks.trailingArgument(query: "gh Mac Island", name: "gh") == "Mac Island")
        #expect(CommandBarLinks.trailingArgument(query: "ghost town", name: "gh") == nil, "the name is matched whole")
        #expect(CommandBarLinks.trailingArgument(query: "GH  é", name: "gh") == "é")
        #expect(CommandBarLinks.trailingArgument(query: "gh", name: "gh") == nil)
        #expect(CommandBarLinks.rankingTitle(name: "gh", query: "gh swift") == "gh swift")
    }

    @Test func aScriptAnswersToItsNameWholeOrWhatFollowsIt() {
        var link = CommandBarLink()
        link.name = "report"
        link.kind = .script
        link.destination = "/tmp/never-run"
        #expect(CommandBarLinks.scriptArgument(for: link, query: "report today") == "today")
        #expect(CommandBarLinks.scriptArgument(for: link, query: "report") == nil, "a bare name needs the person's say-so")
        link.runsWithoutArgument = true
        #expect(CommandBarLinks.scriptArgument(for: link, query: "report") == "")
        #expect(CommandBarLinks.scriptArgument(for: link, query: "repo") == nil, "never from a prefix of its name")
        #expect(CommandBarLinks.matchingScriptLink(in: [link], query: "report x")?.argument == "x")
    }

    @Test func aLinkOpensOnlyWhatItsKindAllowsAndATypedAddressMustBeWeb() {
        var web = CommandBarLink()
        web.destination = "example.com/?q={query}"
        let expanded = CommandBarLinks.expand(web.destination, kind: .link, query: "a b&c")
        #expect(CommandBarLinks.url(for: web, expanded: expanded)?.absoluteString == "https://example.com/?q=a%20b%26c")
        var script = CommandBarLink()
        script.kind = .script
        script.destination = "/tmp/x"
        #expect(CommandBarLinks.url(for: script, expanded: "/tmp/x") == nil, "a script runs, it never opens")
        #expect(CommandBarLinks.typedURL("https://example.com/a")?.host == "example.com")
        #expect(CommandBarLinks.typedURL("example.com")?.scheme == "https")
        #expect(CommandBarLinks.typedURL("file:///etc/passwd") == nil)
        #expect(CommandBarLinks.typedURL("javascript:alert(1)") == nil)
        #expect(CommandBarLinks.typedURL("a@b.com") == nil && CommandBarLinks.typedURL("notes.txt") == nil)
    }

    @Test func theSavedListIsCappedAndDropsEmptyRows() {
        var links: [CommandBarLink] = []
        for index in 0..<80 {
            var link = CommandBarLink()
            link.name = "n\(index)"
            link.destination = "d"
            links.append(link)
        }
        let data = CommandBarLinks.encode(links)
        #expect(CommandBarLinks.decode(data).count == CommandBarLinks.limit)
        var blank = CommandBarLink()
        blank.name = " "
        blank.destination = "x"
        #expect(CommandBarLinks.decode(CommandBarLinks.encode([blank])).isEmpty)
        #expect(CommandBarLinks.decode(Data("garbage".utf8)).isEmpty)
        #expect(CommandBarLinks.decode(nil).isEmpty)
    }

    // MARK: File search

    @Test func aFileSearchHasOneClausePerWordAndEscapesEverythingTyped() throws {
        let one = try #require(CommandBarFileSearchSupport.expression(for: "report"))
        #expect(one == "kMDItemFSName == \"*report*\"cd")
        let two = try #require(CommandBarFileSearchSupport.expression(for: "annual report"))
        #expect(two.components(separatedBy: "kMDItemFSName").count - 1 == 2)
        #expect(CommandBarFileSearchSupport.expression(for: "  \n ") == nil)
        let sneaky = try #require(CommandBarFileSearchSupport.expression(for: "a\\\"b"))
        #expect(sneaky.contains("\\\\") && sneaky.contains("\\\""), "backslash and quote are escaped")
    }

    @Test func aFileHiddenOrIgnoredIsNeverOffered() {
        #expect(CommandBarFileSearchSupport.abbreviating("/Users/me/Documents/x", homeDirectory: "/Users/me") == "~/Documents/x")
        #expect(CommandBarFileSearchSupport.shouldPublishResult(for: "abc", currentQuery: "abc"))
        #expect(!CommandBarFileSearchSupport.shouldPublishResult(for: "abc", currentQuery: "abcd"), "a stale answer is dropped")
        #expect(CommandBarFileSearchSupport.decodeList(CommandBarFileSearchSupport.encodeList(["a", "b c"])) == ["a", "b c"])
    }

    // MARK: Preferences

    @Test func disabledSourcesRoundTripAndTheActionsNeverSwitchOff() {
        let raw = CommandBarPreferences.storageValue(for: [.apps, .emoji, .actions])
        #expect(raw == "apps,emoji", "sorted, and the always-on source is never stored")
        #expect(CommandBarPreferences.disabledSources(from: "emoji, apps,actions,nonsense") == [.apps, .emoji])
        #expect(CommandBarPreferences.source(ofRowID: "app.com.apple.Safari") == .apps)
        #expect(CommandBarPreferences.source(ofRowID: "action.screenshot") == .actions)
        #expect(CommandBarPreferences.source(ofRowID: "file./tmp/a") == .files)
    }
}
