import XCTest

@testable import Mema

final class QuickCaptureWindowPlacementTests: XCTestCase {
    func testRequestGateAppliesFirstAndNewRequestsOnly() {
        var gate = QuickCaptureWindowRequestGate()

        XCTAssertFalse(gate.needsApply(requestID: 0))
        XCTAssertTrue(gate.needsApply(requestID: 1))
        gate.markApplied(requestID: 1)
        XCTAssertFalse(gate.needsApply(requestID: 1))
        XCTAssertTrue(gate.needsApply(requestID: 2))
    }

    func testAXRectConvertsFromTopLeftToAppKitCoordinates() throws {
        let converted = try XCTUnwrap(
            QuickCaptureWindowPlacement.appKitRect(
                fromAXScreenRect: CGRect(x: 100, y: 200, width: 80, height: 20),
                primaryScreenMaxY: 900
            )
        )

        XCTAssertEqual(converted, CGRect(x: 100, y: 680, width: 80, height: 20))
    }

    func testInvalidAXBoundsAreIgnored() {
        XCTAssertNil(
            QuickCaptureWindowPlacement.appKitRect(
                fromAXScreenRect: CGRect(x: 10, y: 10, width: 0, height: 20),
                primaryScreenMaxY: 900
            )
        )
    }

    func testScreenUsesLargestSelectionIntersection() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_000, height: 800),
            CGRect(x: 1_000, y: 0, width: 1_000, height: 800),
        ]
        let anchor = CGRect(x: 950, y: 200, width: 300, height: 100)

        XCTAssertEqual(
            QuickCaptureWindowPlacement.screenIndex(
                for: anchor,
                fallbackPoint: .zero,
                screenFrames: screens
            ),
            1
        )
    }

    func testMissingBoundsUsesMouseScreen() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_000, height: 800),
            CGRect(x: -900, y: 0, width: 900, height: 700),
        ]

        XCTAssertEqual(
            QuickCaptureWindowPlacement.screenIndex(
                for: nil,
                fallbackPoint: CGPoint(x: -300, y: 400),
                screenFrames: screens
            ),
            1
        )
    }

    func testOffscreenAnchorIsDroppedBeforeWindowPlacement() {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let offscreen = CGRect(x: 4_000, y: 2_000, width: 100, height: 40)

        XCTAssertNil(
            QuickCaptureWindowPlacement.anchorForPlacement(offscreen, on: screen)
        )
    }

    func testWindowPrefersRightSideWhenItFits() {
        let origin = QuickCaptureWindowPlacement.windowOrigin(
            windowSize: CGSize(width: 300, height: 240),
            anchor: CGRect(x: 100, y: 400, width: 80, height: 40),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(origin, CGPoint(x: 192, y: 200))
    }

    func testWindowTriesLeftWhenRightDoesNotFit() {
        let origin = QuickCaptureWindowPlacement.windowOrigin(
            windowSize: CGSize(width: 300, height: 240),
            anchor: CGRect(x: 700, y: 400, width: 80, height: 40),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(origin, CGPoint(x: 388, y: 200))
    }

    func testWindowClampsInsideVisibleFrameAtScreenEdge() {
        let visibleFrame = CGRect(x: 0, y: 40, width: 800, height: 720)
        let origin = QuickCaptureWindowPlacement.windowOrigin(
            windowSize: CGSize(width: 500, height: 600),
            anchor: CGRect(x: 760, y: 730, width: 30, height: 20),
            visibleFrame: visibleFrame
        )
        let windowFrame = CGRect(origin: origin, size: CGSize(width: 500, height: 600))

        XCTAssertTrue(visibleFrame.contains(windowFrame))
    }

    func testMissingAnchorCentersWithinVisibleFrame() {
        let origin = QuickCaptureWindowPlacement.windowOrigin(
            windowSize: CGSize(width: 500, height: 400),
            anchor: nil,
            visibleFrame: CGRect(x: -1_000, y: 30, width: 1_000, height: 770)
        )

        XCTAssertEqual(origin, CGPoint(x: -750, y: 215))
    }
}
