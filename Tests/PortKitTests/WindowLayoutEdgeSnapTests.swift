import CoreGraphics
import Foundation
import Testing
@testable import PortKit

/// Lane W3B: the drag-to-edge snapping decisions (which area a pointer is in, what the preview HUD shows), the pure
/// part of upstream `WindowLayoutFeatureTests` / `WindowEdgeSnapRuntimeTests`. No window, no tap, no display.
struct WindowLayoutEdgeSnapTests {
    static let visible = CGRect(x: 0, y: 40, width: 1440, height: 835)
    static let screen = WindowEdgeSnapScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible)
    static let right = WindowEdgeSnapScreen(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                                            visibleFrame: CGRect(x: 1440, y: 40, width: 1920, height: 1040))
    static let upper = WindowEdgeSnapScreen(frame: CGRect(x: 0, y: 900, width: 1280, height: 800),
                                            visibleFrame: CGRect(x: 0, y: 900, width: 1280, height: 775))

    private func target(_ point: CGPoint, screens: [WindowEdgeSnapScreen] = [Self.screen],
                        zones: Set<WindowEdgeSnapZone> = WindowEdgeSnapZone.allEnabled,
                        layout: WindowEdgeSnapLayout = .standard) -> WindowEdgeSnapTarget? {
        WindowEdgeSnapSupport.target(at: point, screens: screens, enabledZones: zones, layout: layout)
    }

    private var snapTop: CGFloat { Self.visible.maxY }

    // MARK: Areas

    @Test func theMenuBarEdgePreviewsMaximizeAndTheInsideNeverSnaps() {
        let top = WindowLayoutGeometry.rect(for: .maximize, current: Self.visible, visibleFrame: Self.visible)
        #expect(target(CGPoint(x: 720, y: snapTop))
                == WindowEdgeSnapTarget(zone: .top, action: .maximize, frame: top, visibleFrame: Self.visible))
        #expect(target(CGPoint(x: 720, y: 900))?.action == .maximize, "the whole menu bar band counts")
        #expect(target(CGPoint(x: 720, y: snapTop - 13)) == nil, "not below the activation band")
        #expect(target(CGPoint(x: 720, y: 450)) == nil, "inside a display nothing snaps")
    }

    @Test func straightEdgesAndInclusiveCornersChooseTheirPlacement() {
        #expect(target(CGPoint(x: 0, y: 450))?.action == .leftHalf)
        #expect(target(CGPoint(x: 1440, y: 450))?.action == .rightHalf)
        #expect(target(CGPoint(x: 720, y: 0))?.action == .bottomHalf)
        #expect(target(CGPoint(x: 0, y: snapTop))?.action == .topLeft)
        #expect(target(CGPoint(x: 1440, y: snapTop))?.action == .topRight)
        #expect(target(CGPoint(x: 0, y: 0))?.action == .bottomLeft)
        #expect(target(CGPoint(x: 1440, y: 0))?.action == .bottomRight)
    }

    @Test func aZoneSwitchedOffStaysOffAndTheOthersKeepWorking() {
        let stored = WindowEdgeSnapZone.disabledZonesStorageValue([.right, .top])
        #expect(stored == "top,right")
        #expect(WindowEdgeSnapZone.disabledZones(from: "unknown, right,top") == [.top, .right], "unknown ids dropped")
        let withoutTop = WindowEdgeSnapZone.enabledZones(from: stored)
        #expect(target(CGPoint(x: 720, y: snapTop), zones: withoutTop) == nil)
        #expect(target(CGPoint(x: 0, y: 450), zones: withoutTop)?.zone == .left)
        #expect(target(CGPoint(x: 720, y: snapTop), zones: []) == nil, "every zone off: nothing snaps")
    }

    // MARK: Chosen placements

    @Test func anAreaPreviewsThePlacementChosenForItAndSavesOnlyTheChanges() {
        #expect(WindowEdgeSnapLayout(storageValue: "") == .standard)
        #expect(WindowEdgeSnapLayout(storageValue: nil) == .standard)
        var chosen = WindowEdgeSnapLayout.standard
        chosen.setAction(.topHalf, for: .top, part: 0)
        chosen.setAction(.rightThird, for: .right, part: 0)
        #expect(chosen.storageValue == "top=topHalf,right=rightThird")
        #expect(WindowEdgeSnapLayout(storageValue: chosen.storageValue) == chosen)
        #expect(target(CGPoint(x: 720, y: snapTop), layout: chosen)?.frame
                == WindowLayoutGeometry.rect(for: .topHalf, current: Self.visible, visibleFrame: Self.visible))
        #expect(target(CGPoint(x: 1440, y: 450), layout: chosen)?.action == .rightThird)
        #expect(target(CGPoint(x: 0, y: 450), layout: chosen)?.action == .leftHalf, "others keep theirs")
        chosen.setAction(.maximize, for: .top, part: 0)
        #expect(chosen.storageValue == "right=rightThird", "choosing the default again saves nothing")
    }

    @Test func aSavedLayoutWithInvalidEntriesKeepsTheDefaultsAndTheValidOnes() {
        let saved = WindowEdgeSnapLayout(storageValue: [
            "top=fullScreen", " left = leftThird ", "topLeft=topLeft+topRight", "bottom=leftThird+",
            "right=nextDisplay", "unknown=leftHalf", "bottomRight=center", "topRight=futurePlacement",
            "bottomLeft=bottomLeftSixth",
        ].joined(separator: ","))
        #expect(saved.actions(for: .top) == [.maximize])
        #expect(saved.actions(for: .left) == [.leftThird])
        #expect(saved.actions(for: .topLeft) == [.topLeft])
        #expect(saved.actions(for: .bottom) == [.bottomHalf])
        #expect(saved.actions(for: .right) == [.rightHalf])
        #expect(saved.actions(for: .bottomRight) == [.bottomRight])
        #expect(saved.actions(for: .topRight) == [.topRight])
        #expect(saved.actions(for: .bottomLeft) == [.bottomLeftSixth])
        let five = "top=" + [WindowLayoutAction.leftQuarter, .leftMiddleQuarter, .rightMiddleQuarter, .rightQuarter,
                              .maximize].map(\.rawValue).joined(separator: "+")
        #expect(WindowEdgeSnapLayout(storageValue: five) == .standard, "more than four areas keeps the default")
    }

    @Test func aSplitEdgeSharesItsLengthBetweenTheCornersAndStacksItsSide() {
        var split = WindowEdgeSnapLayout.standard
        split.setPartCount(3, for: .top)
        split.setPartCount(2, for: .left)
        #expect(split.actions(for: .top) == [.leftThird, .centerThird, .rightThird])
        #expect(split.actions(for: .left) == [.topHalf, .bottomHalf])
        // 180 pt corners on the 1440 pt screen leave 1080 pt: three 360 pt areas.
        for (x, action) in [(181.0, WindowLayoutAction.leftThird), (539, .leftThird), (541, .centerThird),
                            (899, .centerThird), (901, .rightThird), (1259, .rightThird)] {
            #expect(target(CGPoint(x: x, y: snapTop), layout: split)?.action == action, "x \(x)")
        }
        #expect(target(CGPoint(x: 100, y: snapTop), layout: split)?.action == .topLeft)
        #expect(target(CGPoint(x: 1340, y: snapTop), layout: split)?.action == .topRight)
        #expect(target(CGPoint(x: 0, y: 700), layout: split)?.action == .topHalf)
        #expect(target(CGPoint(x: 0, y: 200), layout: split)?.frame
                == WindowLayoutGeometry.rect(for: .bottomHalf, current: Self.visible, visibleFrame: Self.visible))
        split.setPartCount(1, for: .top)
        split.setPartCount(5, for: .left)
        split.setPartCount(2, for: .topLeft)
        #expect(split.actions(for: .top) == [.maximize])
        #expect(split.actions(for: .left) == [.topHalf, .bottomHalf], "five areas are refused")
        #expect(split.actions(for: .topLeft) == [.topLeft], "a corner never splits")
    }

    @Test func everyOfferedPlacementDrawsItsOwnPictureInsideTheScreen() {
        let offered = WindowEdgeSnapPlacementGroup.allCases.flatMap(\.actions)
        let pictures = offered.map(WindowEdgeSnapLayout.previewRect(for:))
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.001, dy: -0.001)
        #expect(Set(offered).count == offered.count)
        #expect(pictures.indices.allSatisfy { first in pictures.indices.allSatisfy { first == $0 || pictures[first] != pictures[$0] } })
        #expect(pictures.allSatisfy { bounds.contains($0) })
        #expect(WindowEdgeSnapLayout.previewRect(for: .topHalf) == CGRect(x: 0, y: 0, width: 1, height: 0.5))
        #expect(WindowEdgeSnapLayout.previewRect(for: .bottomRight) == CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
    }

    // MARK: Several displays

    @Test func negativeDisplayOriginsAndTheirVisibleFrameAreKept() {
        let left = WindowEdgeSnapScreen(frame: CGRect(x: -1280, y: 0, width: 1280, height: 800),
                                        visibleFrame: CGRect(x: -1280, y: 25, width: 1280, height: 775))
        #expect(target(CGPoint(x: -1280, y: 400), screens: [left])?.frame == CGRect(x: -1280, y: 25, width: 640, height: 775))
    }

    @Test func aSeamBetweenDisplaysPreviewsTheDisplayThePointerIsOn() {
        let both = [Self.screen, Self.right]
        #expect(target(CGPoint(x: 1440, y: 450), screens: both)
                == WindowEdgeSnapTarget(zone: .left, action: .leftHalf,
                                        frame: CGRect(x: 1440, y: 40, width: 960, height: 1040),
                                        visibleFrame: Self.right.visibleFrame))
        #expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 1415, y: 450), screens: both, distance: 30)
                == WindowEdgeSnapTarget(zone: .right, action: .rightHalf,
                                        frame: CGRect(x: 720, y: 40, width: 720, height: 835),
                                        visibleFrame: Self.visible), "slowed at the seam: the display it is still on")
        #expect(target(CGPoint(x: 1440, y: 1000), screens: both)?.action == .topLeft)
    }

    @Test func aPointerPassingThroughASeamAtSpeedIsNotCaught() {
        let both = [Self.screen, Self.right]
        let seam = CGPoint(x: 1435, y: 450)
        let fast = WindowEdgeSnapSupport.crossingSpeed * 3
        #expect(WindowEdgeSnapSupport.target(at: seam, screens: both, velocity: CGVector(dx: fast, dy: 0)) == nil)
        #expect(WindowEdgeSnapSupport.target(at: seam, screens: both, velocity: CGVector(dx: -fast, dy: 0)) == nil)
        #expect(WindowEdgeSnapSupport.target(at: seam, screens: both, velocity: CGVector(dx: 0, dy: fast))?.action == .rightHalf,
                "sliding along a seam keeps its preview")
        #expect(WindowEdgeSnapSupport.target(at: seam, screens: both,
                    velocity: CGVector(dx: WindowEdgeSnapSupport.crossingSpeed, dy: 0))?.action == .rightHalf,
                "slowed to the crossing speed counts as aiming")
        #expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 1440, y: 450), screens: [Self.screen],
                    velocity: CGVector(dx: fast, dy: 0))?.action == .rightHalf, "no display beyond: snaps at any speed")
    }

    @Test func aMenuBarBelowAnotherDisplayWaitsForThePointerToSlow() {
        let stacked = [Self.screen, Self.upper]
        let bar = CGPoint(x: 720, y: Self.visible.maxY)
        let fast = WindowEdgeSnapSupport.crossingSpeed * 3
        #expect(target(bar, screens: stacked)?.action == .maximize)
        #expect(target(CGPoint(x: 720, y: 900), screens: stacked)?.visibleFrame == Self.visible)
        #expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 720, y: 905), screens: stacked,
                                             velocity: CGVector(dx: 0, dy: fast)) == nil)
        #expect(WindowEdgeSnapSupport.target(at: bar, screens: [Self.screen],
                                             velocity: CGVector(dx: 0, dy: fast))?.action == .maximize)
        #expect(WindowEdgeSnapSupport.target(at: bar, screens: stacked, velocity: CGVector(dx: 0, dy: fast)) == nil)
    }

    @Test func aDegenerateScreenNeverSnaps() {
        let flat = WindowEdgeSnapScreen(frame: .zero, visibleFrame: .zero)
        #expect(target(CGPoint(x: 0, y: 0), screens: [flat]) == nil)
        #expect(target(CGPoint(x: 0, y: 0), screens: []) == nil)
    }

    // MARK: Pointer speed and system tiling

    @Test func theTrailReadsSteadySpeedRestAndFlicks() {
        var trail = WindowEdgeSnapPointerTrail()
        for step in 0...10 { trail.append(CGPoint(x: CGFloat(step) * 10, y: 0), at: TimeInterval(step) * 0.01) }
        let steady = trail.velocity(at: 0.1)
        #expect(abs(steady.dx - 1000) < 1 && steady.dy == 0)
        #expect(trail.velocity(at: 0.1 + WindowEdgeSnapPointerTrail.stillAfter + 0.01) == .zero)
        var nudged = trail
        nudged.append(CGPoint(x: 101, y: 0), at: 0.5)
        #expect(abs(nudged.velocity(at: 0.5).dx) <= WindowEdgeSnapSupport.crossingSpeed)
        var flicked = trail
        flicked.append(CGPoint(x: 130, y: 0), at: 0.5)
        #expect(flicked.velocity(at: 0.5).dx > WindowEdgeSnapSupport.crossingSpeed)
        var polled = WindowEdgeSnapPointerTrail()
        polled.append(.zero, at: 1)
        polled.append(CGPoint(x: 1, y: 0), at: 1.001)
        #expect(abs(polled.velocity(at: 1.001).dx) <= WindowEdgeSnapSupport.crossingSpeed)
    }

    @Test func theSystemsOwnTilingIsReadNeverWritten() {
        #expect(WindowEdgeSnapSupport.systemTilingEnabled { _ in nil }, "an unwritten key means enabled")
        #expect(!WindowEdgeSnapSupport.systemTilingEnabled { _ in false })
        #expect(WindowEdgeSnapSupport.systemTilingEnabled { $0 == "EnableTilingByEdgeDrag" })
        #expect(!WindowEdgeSnapSupport.systemTilingEnabled(valueFor: { _ in true }, displaysSpan: true),
                "with displays spanning the system tiling is inert")
        #expect(!WindowEdgeSnapSupport.displaysSpan(nil) && !WindowEdgeSnapSupport.displaysSpan(false)
                && WindowEdgeSnapSupport.displaysSpan(true))
        #expect(WindowEdgeSnapSupport.systemTopWindowOverviewDragEnabled(value: nil))
        #expect(!WindowEdgeSnapSupport.systemTopWindowOverviewDragEnabled(value: false))
    }

    @Test func aDragAgainstTheTopEdgeStaysOnePointInsideOnlyWhileTheTopZoneIsOn() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let top = CGPoint(x: 720, y: 0)
        #expect(WindowEdgeSnapSupport.locationAvoidingSystemTopDrag(top, screenFrames: [frame]) == CGPoint(x: 720, y: 1))
        let withoutTop = WindowEdgeSnapZone.enabledZones(from: "top")
        #expect(WindowEdgeSnapSupport.locationAvoidingSystemTopDrag(top, screenFrames: [frame], enabledZones: withoutTop) == top)
    }
}
