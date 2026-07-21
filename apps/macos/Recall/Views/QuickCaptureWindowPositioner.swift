import AppKit
import SwiftUI

struct QuickCapturePresentationContext: Equatable, Sendable {
    let selectionBoundsInAXScreenCoordinates: CGRect?
    let fallbackPointInAppKitScreenCoordinates: CGPoint
}

struct QuickCaptureWindowRequestGate: Equatable, Sendable {
    private(set) var lastAppliedRequestID = 0

    func needsApply(requestID: Int) -> Bool {
        requestID > 0 && requestID != lastAppliedRequestID
    }

    mutating func markApplied(requestID: Int) {
        guard requestID > 0 else { return }
        lastAppliedRequestID = requestID
    }
}

enum QuickCaptureWindowPlacement {
    static let spacing: CGFloat = 12

    static func appKitRect(
        fromAXScreenRect rect: CGRect,
        primaryScreenMaxY: CGFloat
    ) -> CGRect? {
        guard isUsable(rect) else { return nil }
        return CGRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func screenIndex(
        for anchor: CGRect?,
        fallbackPoint: CGPoint,
        screenFrames: [CGRect]
    ) -> Int? {
        guard !screenFrames.isEmpty else { return nil }

        if let anchor, isUsable(anchor) {
            let intersections = screenFrames.enumerated().map { index, frame in
                (index, intersectionArea(anchor, frame))
            }
            if let best = intersections.max(by: { $0.1 < $1.1 }), best.1 > 0 {
                return best.0
            }
        }

        return screenFrames.firstIndex(where: { $0.contains(fallbackPoint) }) ?? 0
    }

    static func windowOrigin(
        windowSize: CGSize,
        anchor: CGRect?,
        visibleFrame: CGRect
    ) -> CGPoint {
        guard windowSize.width > 0, windowSize.height > 0 else {
            return visibleFrame.origin
        }

        guard let anchor, isUsable(anchor) else {
            return CGPoint(
                x: visibleFrame.midX - windowSize.width / 2,
                y: visibleFrame.midY - windowSize.height / 2
            ).clamped(windowSize: windowSize, to: visibleFrame)
        }

        let candidates = [
            CGPoint(
                x: anchor.maxX + spacing,
                y: anchor.maxY - windowSize.height
            ),
            CGPoint(
                x: anchor.minX - spacing - windowSize.width,
                y: anchor.maxY - windowSize.height
            ),
            CGPoint(
                x: anchor.minX,
                y: anchor.minY - spacing - windowSize.height
            ),
            CGPoint(
                x: anchor.minX,
                y: anchor.maxY + spacing
            ),
        ]

        if let fullyVisible = candidates.first(where: {
            visibleFrame.contains(CGRect(origin: $0, size: windowSize))
        }) {
            return fullyVisible
        }

        return candidates[0].clamped(windowSize: windowSize, to: visibleFrame)
    }

    static func anchorForPlacement(_ anchor: CGRect?, on screenFrame: CGRect) -> CGRect? {
        guard let anchor, isUsable(anchor), intersectionArea(anchor, screenFrame) > 0 else {
            return nil
        }
        return anchor
    }

    static func isUsable(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.width.isFinite
            && rect.height.isFinite
            && rect.width > 0
            && rect.height > 0
            && !rect.isNull
            && !rect.isInfinite
    }

    private static func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

struct QuickCaptureWindowAccessor: NSViewRepresentable {
    let requestID: Int
    let context: QuickCapturePresentationContext?

    func makeNSView(context: Context) -> QuickCaptureWindowReaderView {
        QuickCaptureWindowReaderView()
    }

    func updateNSView(_ nsView: QuickCaptureWindowReaderView, context: Context) {
        nsView.presentationRequestID = requestID
        nsView.presentationContext = self.context
        nsView.positionIfNeeded()
    }
}

final class QuickCaptureWindowReaderView: NSView {
    var presentationRequestID = 0
    var presentationContext: QuickCapturePresentationContext?
    private var requestGate = QuickCaptureWindowRequestGate()
    private var scheduledRequestID: Int?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        positionIfNeeded()
    }

    func positionIfNeeded() {
        guard let window,
              let presentationContext else {
            return
        }
        let requestID = presentationRequestID
        guard requestGate.needsApply(requestID: requestID),
              scheduledRequestID != requestID else {
            return
        }
        scheduledRequestID = requestID
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self,
                  let window,
                  self.scheduledRequestID == requestID,
                  self.presentationRequestID == requestID else {
                return
            }
            self.scheduledRequestID = nil
            self.applyPosition(
                to: window,
                context: presentationContext,
                requestID: requestID
            )
        }
    }

    private func applyPosition(
        to window: NSWindow,
        context presentationContext: QuickCapturePresentationContext,
        requestID: Int
    ) {
        guard requestGate.needsApply(requestID: requestID) else { return }

        window.contentView?.layoutSubtreeIfNeeded()
        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else { return }
        let appKitAnchor = presentationContext.selectionBoundsInAXScreenCoordinates.flatMap {
            QuickCaptureWindowPlacement.appKitRect(
                fromAXScreenRect: $0,
                primaryScreenMaxY: primaryScreen.frame.maxY
            )
        }
        guard let targetIndex = QuickCaptureWindowPlacement.screenIndex(
            for: appKitAnchor,
            fallbackPoint: presentationContext.fallbackPointInAppKitScreenCoordinates,
            screenFrames: screens.map(\.frame)
        ) else {
            return
        }

        let targetScreen = screens[targetIndex]
        let placementAnchor = QuickCaptureWindowPlacement.anchorForPlacement(
            appKitAnchor,
            on: targetScreen.frame
        )
        let origin = QuickCaptureWindowPlacement.windowOrigin(
            windowSize: window.frame.size,
            anchor: placementAnchor,
            visibleFrame: targetScreen.visibleFrame
        )
        window.setFrameOrigin(origin)
        requestGate.markApplied(requestID: requestID)
    }
}

private extension CGPoint {
    func clamped(windowSize: CGSize, to frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, frame.minX), max(frame.minX, frame.maxX - windowSize.width)),
            y: min(max(y, frame.minY), max(frame.minY, frame.maxY - windowSize.height))
        )
    }
}
