import AppKit
import AVKit
import SwiftUI
import RecorderCore

/// Plays a finished take in a loop and lets the user trim its start and end before export.
/// The take is already the recovery, so closing the window simply keeps it for retry.
@MainActor
final class PreviewWindow: NSObject, NSWindowDelegate {
    enum Choice { case export(CMTimeRange?), discard, keep }
    var onFinish: ((Choice) -> Void)?
    private let window: NSWindow
    private let model: PreviewModel
    private var finished = false

    init(movie: URL, options: ExportOptions) {
        model = PreviewModel(movie: movie, options: options)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 540),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Framelet Preview"
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 480, height: 400)
        window.delegate = self
        window.contentView = NSHostingView(rootView: PreviewView(
            model: model,
            export: { [weak self] in self.map { $0.finish(.export($0.model.range)) } },
            discard: { [weak self] in self?.confirmDiscard() },
            keep: { [weak self] in self?.finish(.keep) }))
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { finish(.keep, closing: false) }

    /// Runs once: a button press closes the window, and the resulting windowWillClose is ignored.
    /// The player is stopped and its item released before the controller can delete or export the take.
    private func finish(_ choice: Choice, closing: Bool = true) {
        guard !finished else { return }
        finished = true
        withExtendedLifetime(self) {
            model.stop()
            if closing { window.close() }
            onFinish?(choice)
        }
    }

    private func confirmDiscard() {
        let alert = NSAlert()
        alert.messageText = "Discard this recording?"
        alert.informativeText = "The recording will be deleted without exporting a GIF. This cannot be undone."
        alert.addButton(withTitle: "Keep Recording")
        alert.addButton(withTitle: "Discard").hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.finish(.discard) }
        }
    }
}

@MainActor
private final class PreviewModel: ObservableObject {
    let player: AVPlayer
    let options: ExportOptions
    @Published private(set) var duration = 0.0
    @Published private(set) var pixelSize: CGSize?
    @Published private(set) var isPlaying = true
    @Published var start = 0.0 { didSet { start = min(max(0, start), end - minimumLength); seek(to: start) } }
    @Published var end = 0.0 { didSet { end = max(min(duration, end), start + minimumLength); trimEnd(); seek(to: end) } }
    private var observer: NSObjectProtocol?
    private let minimumLength = 0.1

    init(movie: URL, options: ExportOptions) {
        let item = AVPlayerItem(url: movie)
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        self.options = options
        observer = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.loop() }
        }
        Task {
            let asset = item.asset
            guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { return }
            if let track = try? await asset.loadTracks(withMediaType: .video).first, let size = try? await track.load(.naturalSize), size.width > 0 {
                let width = min(size.width, Double(options.maximumWidth))
                pixelSize = CGSize(width: width.rounded(), height: (size.height * width / size.width).rounded())
            }
            self.duration = duration
            end = duration
            seek(to: start)
            player.play()
        }
    }

    /// The selected range, or nil when the whole take is selected.
    var range: CMTimeRange? {
        guard start > 0.001 || end < duration - 0.001 else { return nil }
        return CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
    }

    var summary: String {
        let length = end - start
        var parts = [String(format: "%.1f s", length), "\(options.frameCount(duration: length)) frames at \(options.fps) fps"]
        if let pixelSize { parts.append("\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px") }
        return parts.joined(separator: " · ")
    }

    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying { player.play() } else { player.pause() }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func trimEnd() { player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600) }

    private func seek(to seconds: Double) {
        guard duration > 0 else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func loop() {
        seek(to: start)
        if isPlaying { player.play() }
    }
}

private struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    let export: () -> Void
    let discard: () -> Void
    let keep: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            PlayerView(player: model.player)
                .frame(minHeight: 200)
                .background(Color.black)
                .clipShape(.rect(cornerRadius: 6))
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                trimRow("Start", value: $model.start)
                trimRow("End", value: $model.end)
            }
            .disabled(model.duration == 0)
            Text(model.summary)
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                .accessibilityLabel("GIF: \(model.summary)")
            HStack {
                Button("Discard...", systemImage: "trash", role: .destructive, action: discard)
                Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") { model.togglePlayback() }
                    .keyboardShortcut(.space, modifiers: [])
                Spacer()
                Button("Keep for Later", action: keep)
                    .keyboardShortcut(.cancelAction)
                    .help("Close the preview and keep the recording for retry from the menu bar.")
                Button("Export GIF", action: export)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.duration == 0)
            }
        }
        .padding(16)
    }

    private func trimRow(_ title: String, value: Binding<Double>) -> some View {
        GridRow {
            Text(title)
            Slider(value: value, in: 0...max(model.duration, 0.1)) { Text("\(title) of GIF") }
                .labelsHidden()
                .accessibilityLabel("\(title) of GIF")
                .accessibilityValue(String(format: "%.1f seconds", value.wrappedValue))
            Text(String(format: "%.1f s", value.wrappedValue)).monospacedDigit().frame(width: 52, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.setAccessibilityLabel("Recording preview")
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}
}
