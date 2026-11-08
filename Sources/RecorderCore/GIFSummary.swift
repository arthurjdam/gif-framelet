import Foundation
import ImageIO

/// File size, pixel size and play time of an exported GIF, shown after export ("1.8 MB, 320×180, 4.2 s").
public struct GIFSummary: Equatable, Sendable {
    public let bytes: Int
    public let width: Int
    public let height: Int
    public let duration: Double

    public init(bytes: Int, width: Int, height: Int, duration: Double) {
        self.bytes = bytes
        self.width = width
        self.height = height
        self.duration = duration
    }

    /// Reads the GIF's metadata without decoding frames; nil if the file is not a readable image.
    public init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let first = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = first[kCGImagePropertyPixelWidth] as? Int, let height = first[kCGImagePropertyPixelHeight] as? Int else { return nil }
        var duration = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            let frame = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            duration += frame?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? frame?[kCGImagePropertyGIFDelayTime] as? Double ?? 0
        }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        self.init(bytes: bytes, width: width, height: height, duration: duration)
    }

    public static func fileSize(_ bytes: Int, locale: Locale = .current) -> String {
        Int64(bytes).formatted(.byteCount(style: .file).locale(locale))
    }

    public func text(locale: Locale = .current) -> String {
        "\(Self.fileSize(bytes, locale: locale)), \(width)\u{00D7}\(height), \(duration.formatted(.number.precision(.fractionLength(1)).locale(locale))) s"
    }
}
