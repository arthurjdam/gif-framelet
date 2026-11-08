import Foundation

/// Metadata kept as `recovery.json` next to a recovery movie, so a retry after relaunch uses the capture fps.
public struct RecoveryInfo: Codable, Equatable, Sendable {
    public let fps: Int

    public init(fps: Int) { self.fps = fps }

    public func write(besides movie: URL) throws {
        try JSONEncoder().encode(self).write(to: Self.url(besides: movie), options: .atomic)
    }

    public static func read(besides movie: URL) -> RecoveryInfo? {
        (try? Data(contentsOf: url(besides: movie))).flatMap { try? JSONDecoder().decode(RecoveryInfo.self, from: $0) }
    }

    public static func url(besides movie: URL) -> URL {
        movie.deletingLastPathComponent().appendingPathComponent("recovery.json")
    }
}
