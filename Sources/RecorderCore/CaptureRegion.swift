import Foundation
import CoreGraphics

public struct CaptureRegion: Equatable, Sendable {
    public let rect: CGRect
    public let displayBounds: CGRect

    public init?(rect: CGRect, displayBounds: CGRect) {
        let clipped = rect.standardized.intersection(displayBounds)
        guard !clipped.isNull, clipped.width >= 16, clipped.height >= 16 else { return nil }
        self.rect = clipped
        self.displayBounds = displayBounds
    }

    public var sourceRect: CGRect {
        CGRect(
            x: rect.minX - displayBounds.minX,
            y: displayBounds.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public func pixelSize(scale: Double, maximumWidth: Int) -> CGSize {
        let nativeWidth = rect.width * scale
        let ratio = min(1, Double(maximumWidth) / nativeWidth)
        let width = max(2, Int((nativeWidth * ratio).rounded()) / 2 * 2)
        let height = max(2, Int((rect.height * scale * ratio).rounded()) / 2 * 2)
        return CGSize(width: width, height: height)
    }
}