import Foundation
import CoreGraphics

/// The most recently recorded region, persisted so it can be recorded again or pre-selected.
public struct LastRegion: Codable, Equatable, Sendable {
    public let rect: CGRect
    public let displayBounds: CGRect
    public let displayID: UInt32

    public init(region: CaptureRegion, displayID: UInt32) {
        rect = region.rect
        displayBounds = region.displayBounds
        self.displayID = displayID
    }

    /// The region to record again, or nil when its display is gone, has changed geometry, or the rect no longer fits.
    public func region(displays: [UInt32: CGRect]) -> CaptureRegion? {
        guard let bounds = displays[displayID], bounds == displayBounds, bounds.contains(rect),
              let region = CaptureRegion(rect: rect, displayBounds: bounds), region.rect == rect else { return nil }
        return region
    }
}
