import AppKit
import CoreMedia
import ScreenCaptureKit

// A panel that never becomes key or main, so clicking it never takes focus.
final class InertPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

let inputDebug = ProcessInfo.processInfo.environment["DESKPAD_DEBUG"] == "1"
func inputLog(_ s: String) { if inputDebug { log("input: " + s) } }

// The view's input model ("step in, step out"), with no synthetic events:
// - A click or scroll on the view moves the real cursor to the matching point on the virtual display. That first
//   click only steps in. From then on every click, drag, scroll and hover is ordinary macOS input on the windows
//   there, and the cursor shows in the view.
// - Moving past an edge of the virtual display, or pushing against one, steps out: the cursor reappears just outside
//   the view at the matching spot. Leaving Desktop 2 steps out too.
// (Upstream DeskPad also brought its window to the front whenever the cursor reached the display. That is gone.)
final class PortalView: NSView {
    let displayBounds: () -> CGRect
    var inside = false
    var mover: Any?

    init(frame: NSRect, displayBounds: @escaping () -> CGRect) {
        self.displayBounds = displayBounds
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // View point (bottom-left origin) -> global point (top-left origin) on the virtual display.
    func displayPoint(_ p: NSPoint) -> CGPoint {
        let d = displayBounds()
        return CGPoint(x: d.minX + p.x / bounds.width * d.width, y: d.minY + (bounds.height - p.y) / bounds.height * d.height)
    }

    // Global point on the virtual display -> global point over this view.
    func viewPoint(forDisplayPoint v: CGPoint) -> CGPoint? {
        guard let w = window else { return nil }
        let d = displayBounds()
        let mainH = NSScreen.screens.first?.frame.height ?? 1440
        return CGPoint(x: w.frame.minX + (v.x - d.minX) / d.width * bounds.width,
                       y: (mainH - w.frame.maxY) + (v.y - d.minY) / d.height * bounds.height)
    }

    func stepIn(at local: NSPoint) {
        guard !inside else { return }
        let p = displayPoint(local)
        inside = true
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
        inputLog("step in at \(p)")
        if mover == nil {
            mover = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] e in self?.checkEdges(e) }
        }
    }

    func checkEdges(_ e: NSEvent) {
        guard inside else { return }
        let d = displayBounds()
        let cur = CGEvent(source: nil)?.location ?? .zero
        var out = CGVector.zero
        if !d.contains(cur) {
            out = CGVector(dx: cur.x < d.minX ? -1 : (cur.x >= d.maxX ? 1 : 0), dy: cur.y < d.minY ? -1 : (cur.y >= d.maxY ? 1 : 0))
        } else {
            if cur.x <= d.minX + 0.5 && e.deltaX < -1 { out.dx = -1 }
            if cur.x >= d.maxX - 1.5 && e.deltaX > 1 { out.dx = 1 }
            if cur.y <= d.minY + 0.5 && e.deltaY < -1 { out.dy = -1 }
            if cur.y >= d.maxY - 1.5 && e.deltaY > 1 { out.dy = 1 }
        }
        guard out != .zero else { return }
        stepOut(from: CGPoint(x: min(max(cur.x, d.minX), d.maxX - 1), y: min(max(cur.y, d.minY), d.maxY - 1)), direction: out)
    }

    func stepOut(from v: CGPoint, direction: CGVector) {
        guard inside else { return }
        inside = false
        if let back = viewPoint(forDisplayPoint: v) {
            let dest = CGPoint(x: back.x + direction.dx * 4, y: back.y + direction.dy * 4)
            CGWarpMouseCursorPosition(dest)
            inputLog("step out from \(v) to \(dest)")
        }
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    func desktopChanged() {
        guard inside else { return }
        stepOut(from: CGEvent(source: nil)?.location ?? .zero, direction: .zero)
    }

    override func mouseDown(with e: NSEvent) { stepIn(at: convert(e.locationInWindow, from: nil)) }
    override func rightMouseDown(with e: NSEvent) { stepIn(at: convert(e.locationInWindow, from: nil)) }
    override func otherMouseDown(with e: NSEvent) { stepIn(at: convert(e.locationInWindow, from: nil)) }
    override func scrollWheel(with e: NSEvent) { stepIn(at: convert(e.locationInWindow, from: nil)) }
}

// A live view of the virtual display (ScreenCaptureKit, up to 60 fps), in a borderless panel that exists only on
// Desktop 2. It replaces upstream DeskPad's window, which showed on any desktop and grabbed the cursor.
final class Viewer: NSObject, SCStreamOutput, SCStreamDelegate {
    let window: InertPanel
    let layer = CALayer()
    let display: VirtualDisplay
    let space: UInt64
    var stream: SCStream?
    var filter: SCContentFilter?
    var running = false
    var current: CVPixelBuffer?   // the frame on screen, held so the stream cannot reuse its buffer mid-display

    var portal: PortalView { window.contentView as! PortalView }

    init(display: VirtualDisplay, rect: CGRect, space: UInt64) {
        self.display = display
        self.space = space
        let mainH = NSScreen.screens[0].frame.height
        let frame = NSRect(x: rect.minX, y: mainH - rect.maxY, width: rect.width, height: rect.height)
        window = InertPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        window.hidesOnDeactivate = false
        window.level = .normal
        window.isOpaque = true
        window.hasShadow = true
        window.backgroundColor = .black
        window.alphaValue = 0   // invisible until it is confirmed to be on Desktop 2 only
        window.isReleasedWhenClosed = false
        let view = PortalView(frame: NSRect(origin: .zero, size: frame.size), displayBounds: { display.bounds })
        view.wantsLayer = true
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        window.contentView = view
        window.orderFrontRegardless()
    }

    func pin() -> Bool {
        for _ in 0..<5 { if SkyLight.pin(window: window.windowNumber, to: space) { return true }; usleep(200_000) }
        return false
    }

    var isOnlyOnTargetDesktop: Bool { SkyLight.spaces(ofWindow: window.windowNumber) == [space] }

    func prepare() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let d = content.displays.first(where: { $0.displayID == display.id }) else {
            throw NSError(domain: "DeskPad", code: 2, userInfo: [NSLocalizedDescriptionKey: "virtual display not visible to ScreenCaptureKit"])
        }
        filter = SCContentFilter(display: d, excludingWindows: [])
    }

    func start() {
        guard !running, let filter else { return }
        let cfg = SCStreamConfiguration()
        cfg.width = Int(display.size.width * 2)
        cfg.height = Int(display.size.height * 2)
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = true
        cfg.queueDepth = 6
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        do {
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "deskpad.frames"))
            stream = s
            running = true
            s.startCapture { [weak self] err in
                if let err { log("capture start failed: \(err)"); DispatchQueue.main.async { self?.running = false } }
            }
        } catch { log("capture setup failed: \(error)") }
    }

    // Rebuild the capture from scratch, e.g. after sleep, when the old stream may have died. While the displays are
    // asleep ScreenCaptureKit lists no displays, so keep retrying (2 s, doubling to 30 s) until it works.
    private var restartPending = false
    private var retryDelay: Double = 2

    func restart() {
        guard !restartPending else { return }
        restartPending = true
        attemptRestart()
    }

    private func attemptRestart() {
        if running, let s = stream { s.stopCapture { _ in } }
        running = false; stream = nil
        Task { @MainActor in
            do {
                try await prepare()
                start()
                restartPending = false
                retryDelay = 2
                log("capture restarted")
            } catch {
                log("capture restart failed (\(error.localizedDescription)); retrying in \(Int(retryDelay)) s")
                let delay = retryDelay
                retryDelay = min(retryDelay * 2, 30)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.attemptRestart() }
            }
        }
    }

    func ensureRunning() { if !running { restart() } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pb = CMSampleBufferGetImageBuffer(sb),
              let surface = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.layer.contents = surface
            CATransaction.commit()
            self.current = pb
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log("capture stopped: \(error.localizedDescription); restarting in 2 s")
        DispatchQueue.main.async { self.running = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.restart() }
    }
}
