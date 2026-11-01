import CoreGraphics
import Foundation
import Testing
@testable import PortKit

/// Lane W3B: the pure window maths of the ported Window Layout (upstream `WindowLayoutFeatureTests`, the checks that
/// need no window, no Accessibility and no display), as swift-testing. Rects are AppKit rects (y up) and every
/// frame passed in is a `visibleFrame`: the menu bar and the Dock are already outside it, which is how the
/// menu bar and Dock insets are exercised (a different inset is a different visible frame).
struct WindowLayoutGeometryTests {
    static let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
    static let current = CGRect(x: 200, y: 200, width: 800, height: 500)

    private func rect(_ action: WindowLayoutAction, in frame: CGRect = Self.visible, current: CGRect = Self.current,
                      windowGap: CGFloat = 0, screenGap: CGFloat = 0) -> CGRect {
        WindowLayoutGeometry.rect(for: action, current: current, visibleFrame: frame, windowGap: windowGap,
                                  screenGap: screenGap)
    }

    // MARK: Halves, thirds, quarters

    @Test func halvesAndThirdsFillTheVisibleFrame() {
        let expected: [(WindowLayoutAction, CGRect)] = [
            (.leftHalf, CGRect(x: 0, y: 40, width: 720, height: 860)),
            (.rightHalf, CGRect(x: 720, y: 40, width: 720, height: 860)),
            (.topHalf, CGRect(x: 0, y: 470, width: 1440, height: 430)),
            (.bottomHalf, CGRect(x: 0, y: 40, width: 1440, height: 430)),
            (.leftThird, CGRect(x: 0, y: 40, width: 480, height: 860)),
            (.centerThird, CGRect(x: 480, y: 40, width: 480, height: 860)),
            (.rightThird, CGRect(x: 960, y: 40, width: 480, height: 860)),
            (.leftTwoThirds, CGRect(x: 0, y: 40, width: 960, height: 860)),
            (.rightTwoThirds, CGRect(x: 480, y: 40, width: 960, height: 860)),
            (.centerHalf, CGRect(x: 360, y: 40, width: 720, height: 860)),
            (.centerTwoThirds, CGRect(x: 240, y: 40, width: 960, height: 860)),
            (.maximize, Self.visible),
        ]
        for (action, target) in expected { #expect(rect(action) == target, "\(action.rawValue)") }
    }

    @Test func quarterRowsColumnsAndVerticalThirdsTileTheirStrip() {
        let expected: [(WindowLayoutAction, CGRect)] = [
            (.topQuarter, CGRect(x: 0, y: 685, width: 1440, height: 215)),
            (.upperMiddleQuarter, CGRect(x: 0, y: 470, width: 1440, height: 215)),
            (.lowerMiddleQuarter, CGRect(x: 0, y: 255, width: 1440, height: 215)),
            (.bottomQuarter, CGRect(x: 0, y: 40, width: 1440, height: 215)),
            (.leftQuarter, CGRect(x: 0, y: 40, width: 360, height: 860)),
            (.leftMiddleQuarter, CGRect(x: 360, y: 40, width: 360, height: 860)),
            (.rightMiddleQuarter, CGRect(x: 720, y: 40, width: 360, height: 860)),
            (.rightQuarter, CGRect(x: 1080, y: 40, width: 360, height: 860)),
            (.topThird, CGRect(x: 0, y: 613, width: 1440, height: 287)),
            (.middleThird, CGRect(x: 0, y: 326, width: 1440, height: 288)),
            (.bottomThird, CGRect(x: 0, y: 40, width: 1440, height: 287)),
            (.topTwoThirds, CGRect(x: 0, y: 326, width: 1440, height: 574)),
            (.bottomTwoThirds, CGRect(x: 0, y: 40, width: 1440, height: 574)),
        ]
        for (action, target) in expected { #expect(rect(action) == target, "\(action.rawValue)") }
    }

    @Test func gridCellsAreSixthsAndCorners() {
        let sixths: [(WindowLayoutAction, CGRect)] = [
            (.topLeftSixth, CGRect(x: 0, y: 470, width: 480, height: 430)),
            (.topCenterSixth, CGRect(x: 480, y: 470, width: 480, height: 430)),
            (.topRightSixth, CGRect(x: 960, y: 470, width: 480, height: 430)),
            (.bottomLeftSixth, CGRect(x: 0, y: 40, width: 480, height: 430)),
            (.bottomCenterSixth, CGRect(x: 480, y: 40, width: 480, height: 430)),
            (.bottomRightSixth, CGRect(x: 960, y: 40, width: 480, height: 430)),
            (.topLeft, CGRect(x: 0, y: 470, width: 720, height: 430)),
            (.topRight, CGRect(x: 720, y: 470, width: 720, height: 430)),
            (.bottomLeft, CGRect(x: 0, y: 40, width: 720, height: 430)),
            (.bottomRight, CGRect(x: 720, y: 40, width: 720, height: 430)),
        ]
        for (action, target) in sixths { #expect(rect(action) == target, "\(action.rawValue)") }
    }

    @Test func anAnchoredRectKeepsTheEdgeTheActionIsAimedAt() {
        let visible = Self.visible
        #expect(WindowLayoutGeometry.anchoredRect(for: .leftQuarter,
                    targetRect: CGRect(x: 0, y: 40, width: 360, height: 860),
                    actualSize: CGSize(width: 600, height: 860), visibleFrame: visible)
                == CGRect(x: 0, y: 40, width: 600, height: 860))
        #expect(WindowLayoutGeometry.anchoredRect(for: .rightMiddleQuarter,
                    targetRect: CGRect(x: 720, y: 40, width: 360, height: 860),
                    actualSize: CGSize(width: 600, height: 860), visibleFrame: visible)
                == CGRect(x: 480, y: 40, width: 600, height: 860))
        #expect(WindowLayoutGeometry.anchoredRect(for: .topQuarter,
                    targetRect: CGRect(x: 0, y: 685, width: 1440, height: 215),
                    actualSize: CGSize(width: 1440, height: 400), visibleFrame: visible)
                == CGRect(x: 0, y: 500, width: 1440, height: 400))
        #expect(WindowLayoutGeometry.anchoredRect(for: .middleThird,
                    targetRect: CGRect(x: 0, y: 326, width: 1440, height: 288),
                    actualSize: CGSize(width: 1440, height: 400), visibleFrame: visible)
                == CGRect(x: 0, y: 270, width: 1440, height: 400))
    }

    @Test func aMinimumSizedWindowOnTheSameAnchorsIsAccepted() {
        let target = CGRect(x: 960, y: 40, width: 480, height: 430)
        let anchored = CGRect(x: 840, y: 40, width: 600, height: 500)
        #expect(WindowLayoutGeometry.anchoredRect(for: .bottomRightSixth, targetRect: target,
                    actualSize: CGSize(width: 600, height: 500), visibleFrame: Self.visible) == anchored)
        #expect(WindowLayoutGeometry.accepts(actualRect: anchored, targetRect: target, action: .bottomRightSixth,
                                             anchorTolerance: 36))
        #expect(!WindowLayoutGeometry.accepts(actualRect: .zero, targetRect: .zero, action: .fullScreen,
                                              anchorTolerance: 10), "full screen is never frame-accepted")
    }

    // MARK: Gaps and margin

    @Test func windowGapIsTheTotalDistanceBetweenTwoNeighbours() {
        #expect(rect(.leftHalf, windowGap: 16) == CGRect(x: 0, y: 40, width: 712, height: 860))
        #expect(rect(.rightHalf, windowGap: 16) == CGRect(x: 728, y: 40, width: 712, height: 860))
        #expect(rect(.centerThird, windowGap: 16) == CGRect(x: 488, y: 40, width: 464, height: 860))
        #expect(rect(.topLeft, windowGap: 32) == CGRect(x: 0, y: 486, width: 704, height: 414))
        // The two gapped halves end up exactly one gap apart.
        let left = rect(.leftHalf, windowGap: 16), right = rect(.rightHalf, windowGap: 16)
        #expect(right.minX - left.maxX == 16)
    }

    @Test func screenGapInsetsTheFrameAndKeepsRoomOnASmallDisplay() {
        #expect(rect(.leftHalf, screenGap: 32) == CGRect(x: 32, y: 72, width: 688, height: 796))
        #expect(rect(.maximize, windowGap: 16, screenGap: 32) == CGRect(x: 32, y: 72, width: 1376, height: 796))
        #expect(rect(.leftHalf, windowGap: 16, screenGap: 32) == CGRect(x: 32, y: 72, width: 680, height: 796))
        #expect(WindowLayoutGeometry.screenGapFrame(CGRect(x: 0, y: 0, width: 100, height: 100), screenGap: 128)
                == CGRect(x: 10, y: 10, width: 80, height: 80), "80 pt of layout space survive an oversized gap")
    }

    @Test func centreAndMarginMaximizeKeepTheirOwnGeometry() {
        #expect(rect(.center, windowGap: 64) == rect(.center), "no neighbours, no window gap")
        #expect(rect(.center, screenGap: 32) == rect(.center), "centring keeps the size under a screen gap")
        #expect(rect(.marginMaximize, windowGap: 64) == rect(.marginMaximize))
        #expect(rect(.marginMaximize, windowGap: 16, screenGap: 32) == rect(.marginMaximize), "margins do not compound")
        let margin = rect(.marginMaximize)
        #expect(margin == CGRect(x: 72, y: 83, width: 1296, height: 774), "5 % each side by default")
        let centred = rect(.center)
        #expect(centred.size == Self.current.size && centred.midX == Self.visible.midX && centred.midY == Self.visible.midY)
        let huge = CGRect(x: 0, y: 0, width: 5000, height: 4000)
        #expect(rect(.center, current: huge).size == Self.visible.size, "a window larger than the screen shrinks to it")
    }

    @Test func marginPercentIsSanitised() {
        #expect(WindowLayoutMargin.sanitizedPercent(.nan) == WindowLayoutMargin.defaultPercent)
        #expect(WindowLayoutMargin.sanitizedPercent(.infinity) == WindowLayoutMargin.defaultPercent)
        #expect(WindowLayoutMargin.sanitizedPercent(-3) == 0)
        #expect(WindowLayoutMargin.sanitizedPercent(99) == 25)
        #expect(WindowLayoutGaps.presets == [0, 8, 16, 32, 64, 128])
    }

    // MARK: Menu bar and Dock insets, other displays

    /// A visible frame is the screen minus the menu bar and the Dock, wherever the Dock sits: the same actions on
    /// each one must stay inside it (1 pt for `integral` rounding) and never collapse.
    static let insetFrames: [(name: String, frame: CGRect)] = [
        ("menu bar only", CGRect(x: 0, y: 0, width: 1440, height: 875)),
        ("Dock at the bottom", CGRect(x: 0, y: 70, width: 1440, height: 805)),
        ("Dock on the left", CGRect(x: 72, y: 0, width: 1368, height: 875)),
        ("Dock on the right", CGRect(x: 0, y: 0, width: 1368, height: 875)),
        ("notch menu bar, Dock bottom", CGRect(x: 0, y: 70, width: 1512, height: 878)),
        ("second display on the left", CGRect(x: -1920, y: -180, width: 1920, height: 1055)),
        ("second display above", CGRect(x: 100, y: 982, width: 2560, height: 1415)),
        ("portrait display", CGRect(x: 1440, y: -600, width: 1080, height: 1895)),
    ]

    static let tilingActions: [WindowLayoutAction] = WindowLayoutAction.allCases.filter {
        ![.fullScreen, .restore, .previousDisplay, .nextDisplay].contains($0)
    }

    @Test func everyPlacementStaysInsideTheVisibleFrameWhateverTheInsets() {
        for (name, frame) in Self.insetFrames {
            let window = CGRect(x: frame.minX + 50, y: frame.minY + 50, width: 800, height: 500)
            for action in Self.tilingActions {
                for (windowGap, screenGap) in [(CGFloat(0), CGFloat(0)), (16, 0), (0, 32), (16, 32)] {
                    let target = rect(action, in: frame, current: window, windowGap: windowGap, screenGap: screenGap)
                    #expect(target.width > 0 && target.height > 0, "\(name) \(action.rawValue) not empty")
                    #expect(frame.insetBy(dx: -1, dy: -1).contains(target),
                            "\(name) \(action.rawValue) gap \(windowGap)/\(screenGap): \(target) in \(frame)")
                }
            }
        }
    }

    @Test func maximizeFillsExactlyWhatTheMenuBarAndDockLeave() {
        for (name, frame) in Self.insetFrames { #expect(rect(.maximize, in: frame) == frame, "\(name)") }
    }

    @Test func leftAndRightHalvesMeetWithoutOverlapOrHole() {
        for (name, frame) in Self.insetFrames {
            let left = rect(.leftHalf, in: frame), right = rect(.rightHalf, in: frame)
            #expect(abs(left.maxX - right.minX) <= 1, "\(name)")
            #expect(abs(left.width + right.width - frame.width) <= 2, "\(name)")
            let top = rect(.topHalf, in: frame), bottom = rect(.bottomHalf, in: frame)
            #expect(abs(top.minY - bottom.maxY) <= 1, "\(name)")
        }
    }

    // MARK: Moving between displays

    @Test func movingToTheNextDisplayKeepsSizeAndSideAndStaysUnderTheMenuBar() {
        let next = CGRect(x: 1440, y: 80, width: 1920, height: 1000)
        func moved(_ window: CGRect, to destination: CGRect = next, from source: CGRect = Self.visible) -> CGRect {
            WindowLayoutGeometry.rectForDisplay(current: window, sourceVisibleFrame: source,
                                                destinationVisibleFrame: destination)
        }
        #expect(moved(CGRect(x: 720, y: 40, width: 720, height: 860)) == CGRect(x: 2640, y: 220, width: 720, height: 860))
        #expect(moved(CGRect(x: 0, y: 40, width: 720, height: 860)) == CGRect(x: 1440, y: 220, width: 720, height: 860))
        #expect(moved(CGRect(x: -40, y: 0, width: 2000, height: 1200)) == next, "oversized windows clamp to the target")
        #expect(moved(Self.visible) == next, "a maximized window stays maximized")
        #expect(moved(CGRect(x: 4, y: 44, width: 1432, height: 852)) == next, "within tolerance of maximized")
        let ultrawide = CGRect(x: 1440, y: 0, width: 3440, height: 1400)
        #expect(moved(Self.current, to: ultrawide) == CGRect(x: 1640, y: 700, width: 800, height: 500))
        let short = CGRect(x: 1440, y: 80, width: 1920, height: 400)
        let shrunk = moved(Self.current, to: short)
        #expect(shrunk == CGRect(x: 1640, y: 80, width: 800, height: 400))
        #expect(moved(shrunk, to: Self.visible, from: short) == CGRect(x: 200, y: 500, width: 800, height: 400),
                "the original height is not restored after shrinking to fit")
    }

    @Test func nextAndPreviousDisplayFollowTheArrangementFromLeftToRight() {
        let frames = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1200, y: -200, width: 1200, height: 1920),
                      CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        #expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0, frames: frames, movingForward: true) == 2)
        #expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0, frames: frames, movingForward: false) == 1)
        #expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 2, frames: frames, movingForward: true) == 1,
                "wraps around")
        #expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0, frames: [frames[0]], movingForward: true) == nil)
        #expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 9, frames: frames, movingForward: true) == nil)
    }

    @Test func aDegenerateDisplayNeverProducesAnInvalidFrame() {
        let window = Self.current
        let flat = CGRect(x: 0, y: 0, width: 0, height: 0)
        #expect(WindowLayoutGeometry.rectForDisplay(current: window, sourceVisibleFrame: flat,
                                                    destinationVisibleFrame: Self.visible) == window.integral)
        #expect(WindowLayoutGeometry.rectForDisplay(current: window, sourceVisibleFrame: Self.visible,
                                                    destinationVisibleFrame: flat) == window.integral)
    }

    // MARK: Restore history

    @Test func restoreHistoryWalksBackAndStaysBoundedPerWindow() {
        let key = WindowLayoutWindowKey(processID: 41, processLaunchTime: 100, windowID: 414)
        let other = WindowLayoutWindowKey(processID: 42, processLaunchTime: 100, windowID: 414)
        let reused = WindowLayoutWindowKey(processID: 41, processLaunchTime: 101, windowID: 414)
        let frames: [WindowLayoutFrame] = (0...WindowLayoutHistory.perWindowLimit).map {
            WindowLayoutFrame(origin: CGPoint(x: $0 * 10, y: $0 * 20), size: CGSize(width: 800 + $0, height: 500 + $0))
        }
        var history = WindowLayoutHistory()
        for index in 0...2 { history.record(frames[index], for: key) }
        history.record(frames[3], for: other)
        #expect(history.popPrevious(for: key, current: frames[3]) == frames[2])
        #expect(history.popPrevious(for: key, current: frames[2]) == frames[1])
        #expect(history.popPrevious(for: key, current: frames[1]) == frames[0])
        #expect(history.popPrevious(for: other, current: frames[4]) == frames[3], "isolated per process")
        history.record(frames[5], for: key)
        history.record(frames[6], for: key)
        history.discardLatest(for: key)
        #expect(history.popPrevious(for: key, current: frames[7]) == frames[5], "a failed action removes only its own frame")
        history.record(frames[10], for: key)
        history.record(frames[11], for: reused)
        history.removeStaleWindows(keeping: [reused])
        #expect(history.popPrevious(for: key, current: frames[12]) == nil)
        #expect(history.popPrevious(for: reused, current: frames[12]) == frames[11])
        var bounded = WindowLayoutHistory()
        for frame in frames { bounded.record(frame, for: key) }
        var count = 0
        var cursor = WindowLayoutFrame(origin: CGPoint(x: -1, y: -1), size: CGSize(width: 1, height: 1))
        while let previous = bounded.popPrevious(for: key, current: cursor) { count += 1; cursor = previous }
        #expect(count == WindowLayoutHistory.perWindowLimit)
    }

    // MARK: Shortcut resolution

    @Test func aStoredShortcutResolvesToTheSavedTheDefaultOrNothing() {
        let left = GlobalShortcut.windowLayoutLeftDefault
        #expect(WindowLayoutAction.resolvedShortcut(storedValue: nil, defaultShortcut: left) == left)
        #expect(WindowLayoutAction.resolvedShortcut(storedValue: WindowLayoutAction.clearedShortcutStorageValue,
                                                    defaultShortcut: left) == nil, "cleared stays cleared")
        #expect(WindowLayoutAction.resolvedShortcut(storedValue: "garbage-value", defaultShortcut: left) == left)
        #expect(WindowLayoutAction.resolvedShortcut(storedValue: GlobalShortcut.windowLayoutRightDefault.storageValue,
                                                    defaultShortcut: left) == .windowLayoutRightDefault)
        #expect(WindowLayoutAction.resolvedShortcut(storedValue: "garbage-value", defaultShortcut: nil) == nil)
    }

    @Test func everyActionTargetsOnlyWhatItChanges() {
        #expect(WindowLayoutAction.center.targetCapability == .position)
        #expect(WindowLayoutAction.fullScreen.targetCapability == .fullScreen)
        #expect(WindowLayoutAction.maximize.targetCapability == .frame)
        #expect(WindowLayoutAction.restore.targetCapability == .position)
    }
}
