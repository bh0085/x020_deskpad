import AppKit
import CoreMedia
import ScreenCaptureKit

// Live capture of one virtual display (ScreenCaptureKit, up to 60 fps, at the display's full 2x resolution).
// ScreenCaptureKit delivers frames only when something on the display changes, so an idle display costs little.
// While the displays sleep it lists no displays at all; restarts retry (2 s, doubling to 30 s) until it works.
final class DisplayCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let display: VirtualDisplay
    var onFrame: ((IOSurface) -> Void)?
    private var stream: SCStream?
    private(set) var running = false
    private var current: CVPixelBuffer?   // the frame on screen, held so the stream cannot reuse its buffer mid-display
    private var restartPending = false
    private var retryDelay: Double = 2

    init(display: VirtualDisplay) { self.display = display }

    func restart() {
        guard !restartPending else { return }
        restartPending = true
        attempt()
    }

    func ensureRunning() { if !running { restart() } }

    private func attempt() {
        if running, let s = stream { s.stopCapture { _ in } }
        running = false; stream = nil
        Task { @MainActor in
            do {
                try await start()
                restartPending = false
                retryDelay = 2
            } catch {
                log("\(display.name) capture: \(error.localizedDescription); retrying in \(Int(retryDelay)) s")
                let delay = retryDelay
                retryDelay = min(retryDelay * 2, 30)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.attempt() }
            }
        }
    }

    @MainActor private func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let d = content.displays.first(where: { $0.displayID == display.id }) else {
            throw NSError(domain: "DeskPad", code: 2, userInfo: [NSLocalizedDescriptionKey: "display not visible to ScreenCaptureKit"])
        }
        let cfg = SCStreamConfiguration()
        cfg.width = Int(display.size.width * 2)
        cfg.height = Int(display.size.height * 2)
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = true
        cfg.queueDepth = 6
        let s = SCStream(filter: SCContentFilter(display: d, excludingWindows: []), configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "deskpad.capture.\(display.id)"))
        try await s.startCapture()
        stream = s
        running = true
        log("\(display.name) capture running")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pb = CMSampleBufferGetImageBuffer(sb),
              let surface = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async {
            self.current = pb
            self.onFrame?(surface)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log("\(display.name) capture stopped: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.running = false
            self.restart()
        }
    }
}
