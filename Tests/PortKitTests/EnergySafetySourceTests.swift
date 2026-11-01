import Foundation
import Testing

/// Source gates on the energy lane, in the style of `PortPromptScrubTests`: the closed-lid flow may ask for the
/// administrator password only inside the click entry points of `KeepAwakeManager`, nothing probes `sudo` at
/// launch, nothing writes sudoers except through the validated installer, and the music blocker never raises the
/// Apple Events consent prompt from a key press. They fail on a re-import that brings upstream's behaviour back.
@Suite struct EnergySafetySourceTests {
    private static func file(_ path: String) -> [Substring] {
        PortSourceScrubTests.files.first { $0.path == path }?.lines ?? []
    }

    private static func isCode(_ line: Substring) -> Bool {
        !line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//")
    }

    private static let managerPath = "Services/KeepAwakeManager.swift"
    private static let clickBegin = "MARK: - Click entry points (the only place an administrator prompt can start)"
    private static let clickEnd = "MARK: - End of the click entry points"

    private static func clickRange(in lines: [Substring]) -> Range<Int>? {
        guard let begin = lines.firstIndex(where: { $0.contains(clickBegin) }),
              let end = lines.firstIndex(where: { $0.contains(clickEnd) }), begin < end else { return nil }
        return begin..<end
    }

    private static let promptCalls = ["Sudoers.install(", "Sudoers.install {", "restoreSleepWithAuthorization(",
                                      "AdminShell.", "Sudoers.remove("]

    @Test func theManagerHasAClickSectionAndEveryAdministratorPromptIsInsideIt() {
        let lines = Self.file(Self.managerPath)
        #expect(!lines.isEmpty, "KeepAwakeManager.swift is part of the port")
        guard let range = Self.clickRange(in: lines) else {
            Issue.record("the click entry points section is missing")
            return
        }
        var outside: [Int] = []
        var inside = 0
        for (index, line) in lines.enumerated() where Self.isCode(line) {
            guard Self.promptCalls.contains(where: { line.contains($0) }) else { continue }
            if range.contains(index) { inside += 1 } else { outside.append(index + 1) }
        }
        #expect(outside.isEmpty, "an administrator prompt outside a click path: lines \(outside)")
        #expect(inside == 2, "exactly the rule install and the sleep restore, both behind a click")
    }

    @Test func noOtherPortedFileCanPromptForTheClosedLidRule() {
        var offenders: [String] = []
        for file in PortSourceScrubTests.files where file.path != Self.managerPath && file.path != "Services/ShellSupport.swift" {
            for (index, line) in file.lines.enumerated() where Self.isCode(line) {
                if line.contains("Sudoers.install") || line.contains("restoreSleepWithAuthorization")
                    || line.contains("Sudoers.remove") { offenders.append("\(file.path):\(index + 1)") }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func theTwoClickEntriesAreOnlyReachedFromTheEnergyPageNotFromTheShellFacade() {
        var callers: [String] = []
        for file in PortSourceScrubTests.files where file.path != Self.managerPath {
            for line in file.lines where Self.isCode(line) {
                if line.contains("setClosedLidMode(") || line.contains("restoreSleepFromClick(") {
                    callers.append(file.path)
                }
            }
        }
        #expect(Set(callers) == ["Bridge/Energy.swift"], "\(callers)")
        let energy = Self.file("Bridge/Energy.swift")
        let facadeStart = energy.firstIndex { $0.contains("public enum PortKeepAwake") } ?? 0
        let laneStart = energy.firstIndex { $0.contains("MARK: - The lane") } ?? energy.count
        let facade = energy[facadeStart..<laneStart]
        #expect(!facade.contains { $0.contains("setClosedLidMode") || $0.contains("restoreSleepFromClick") })
        // And the page calls them from buttons only.
        let buttonCalls = energy.filter { $0.contains("Button(") && ($0.contains("setClosedLidMode") || $0.contains("restoreSleepFromClick")) }
        #expect(buttonCalls.count == 3, "Désactiver, Activer…, Rétablir la veille maintenant")
    }

    @Test func nothingProbesSudoOrWritesSleepAtInit() {
        let lines = Self.file(Self.managerPath)
        guard let initStart = lines.firstIndex(where: { $0.contains("private init()") }) else {
            Issue.record("no private init")
            return
        }
        let end = lines[initStart...].firstIndex { $0.hasPrefix("    }") } ?? lines.endIndex
        let body = lines[initStart..<end]
        #expect(!body.contains { Self.isCode($0) && ($0.contains("refreshPasswordlessStatus()") || $0.contains("Sudoers.")) },
                "the init may not run `sudo -n` or touch pmset: the status is read when the page opens or an attempt starts")
    }

    @Test func aCarriedClosedLidPreferenceIsDroppedUntilTheClickConfirmsIt() {
        let text = Self.file(Self.managerPath).joined(separator: "\n")
        #expect(text.contains("closedLidConfirmedKey"))
        #expect(text.contains("clamshellPreferred = carried && confirmed"))
        #expect(text.contains("static let closedLidConfirmedKey = \"macIslandClosedLidConfirmed\""))
        // The click is the only writer of the confirmation.
        let writers = Self.file(Self.managerPath).filter {
            Self.isCode($0) && $0.contains("closedLidConfirmedKey") && $0.contains(".set(")
        }
        #expect(writers.count == 1, "only setClosedLidMode(true) confirms; the init only ever drops a carried value")
    }

    @Test func theRecoveryNeverPromptsAtLaunch() {
        let lines = Self.file(Self.managerPath)
        guard let start = lines.firstIndex(where: { $0.contains("func recoverIfNeeded(") }),
              let end = lines[start...].firstIndex(where: { $0.contains("private func finishRecovery") }) else {
            Issue.record("recoverIfNeeded not found")
            return
        }
        let body = lines[start..<end].filter(Self.isCode)
        #expect(!body.contains { line in Self.promptCalls.contains { line.contains($0) } })
        #expect(body.contains { $0.contains("sleepRestoreNeeded = true") }, "a failed silent restore is surfaced, not prompted")
    }

    @Test func theDisableFallbackSurfacesInsteadOfPrompting() {
        let lines = Self.file(Self.managerPath)
        guard let start = lines.firstIndex(where: { $0.contains("private func disableClamshell(") }),
              let end = lines[start...].firstIndex(where: { $0.contains("private func finishClamshellRestore") }) else {
            Issue.record("disableClamshell not found")
            return
        }
        let body = lines[start..<end].filter(Self.isCode)
        #expect(!body.contains { line in Self.promptCalls.contains { line.contains($0) } })
        #expect(body.contains { $0.contains("sleepRestoreNeeded = true") })
    }

    @Test func theSafetyPolicyRunsBeforeSleepIsEverDisabledAndWhileItIs() {
        let text = Self.file(Self.managerPath).joined(separator: "\n")
        #expect(text.contains("ClamshellSafetyPolicy.violation("))
        #expect(text.contains("func checkClamshellSafety("))
        #expect(text.contains("checkClamshellSafety()"), "the 30 s battery timer runs it")
        #expect(text.contains("if let violation = currentClamshellViolation(activeSince: nil, now: Date())"),
                "and enableClamshell asks before the first `pmset disablesleep 1`")
    }

    @Test func theMusicBlockerNeverRaisesTheAppleEventsConsentPrompt() {
        let lines = Self.file("Services/Audio/MusicLaunchBlocker.swift")
        let call = lines.filter { Self.isCode($0) && $0.contains("AEDeterminePermissionToAutomateTarget") }
        #expect(call.count == 1)
        #expect(call.allSatisfy { $0.contains(", false))") }, "askUserIfNeeded must be false: no prompt from a key press")
    }

    @Test func bluetoothFailsClosedWhenThePrivateSwitchIsMissing() {
        let text = Self.file("Services/Bluetooth/BluetoothSleepService.swift").joined(separator: "\n")
        #expect(text.contains("return controllerPower != nil"), "isSupported includes the dlsym probe")
        #expect(text.contains("func restoreNow()"))
        #expect(text.contains("guard Self.isSupported else { return }"))
    }

    @Test func theUpstreamKeepAwakeHotkeyRegistrarStaysIdle() {
        let lines = Self.file("Services/HotkeyManager.swift")
        #expect(lines.contains { $0.contains("guard PortShortcutOwnership.upstreamKeepAwakeHotkeyAllowed else { unregister(); return }") })
    }
}
