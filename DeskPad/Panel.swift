import AppKit

// A panel that never becomes key or main, so clicking it never takes focus.
final class InertPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// One screen on Desktop 2: a live view of the Mac display or of one Android mirror, with rounded corners, a shadow
// and a label underneath. The window exists only on Desktop 2: it is created invisible, moved there with SkyLight,
// checked to be there and only there, and then shown.
final class Panel {
    static let labelHeight: CGFloat = 50   // the label's baseline sits about 34 pt under the panel
    let window: InertPanel
    let content = CALayer()
    let label: NSTextField
    private let overlay = CATextLayer()
    private let dim = CALayer()
    private(set) var rect: CGRect          // the screen part, global top-left coordinates
    var contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    // A corner card shows only its text, not the mirror.
    var showsMirror = true {
        didSet {
            guard showsMirror != oldValue else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            if !showsMirror { content.contents = nil }
            content.backgroundColor = showsMirror ? NSColor.black.cgColor : NSColor(white: 0.12, alpha: 0.92).cgColor
            CATransaction.commit()
        }
    }

    init?(rect: CGRect, title: String, space: UInt64, onClick: @escaping (CGPoint) -> Void) {
        self.rect = rect
        window = InertPanel(contentRect: Panel.windowFrame(for: rect), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        label = NSTextField(labelWithString: title)
        window.hidesOnDeactivate = false
        window.level = .normal
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        let view = PanelView(frame: NSRect(origin: .zero, size: window.frame.size), onClick: onClick)
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        content.cornerRadius = 12
        content.masksToBounds = true
        content.backgroundColor = NSColor.black.cgColor
        content.contentsGravity = .resize
        view.layer?.addSublayer(content)
        dim.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        dim.isHidden = true
        content.addSublayer(dim)
        overlay.alignmentMode = .center
        overlay.isWrapped = true
        overlay.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        overlay.contentsScale = 2
        overlay.isHidden = true
        content.addSublayer(overlay)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.8)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        view.addSubview(label)
        window.contentView = view
        layoutContents()
        window.orderFrontRegardless()
        var pinned = false
        for _ in 0..<5 { if SkyLight.pin(window: window.windowNumber, to: space) { pinned = true; break }; usleep(100_000) }
        guard pinned, SkyLight.spaces(ofWindow: window.windowNumber) == [space] else {
            log("panel \"\(title)\" could not be moved to desktop \(space); not shown")
            window.close()
            return nil
        }
        window.alphaValue = 1
    }

    static func windowFrame(for r: CGRect) -> NSRect {
        let mainH = NSScreen.screens[0].frame.height
        return NSRect(x: r.minX, y: mainH - r.maxY - labelHeight, width: r.width, height: r.height + labelHeight)
    }

    func setRect(_ r: CGRect, title: String) {
        label.stringValue = title
        guard r != rect else { return }
        rect = r
        window.setFrame(Panel.windowFrame(for: r), display: true)
        layoutContents()
    }

    private func layoutContents() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.frame = CGRect(x: 0, y: Panel.labelHeight, width: rect.width, height: rect.height)
        dim.frame = content.bounds
        let fontSize: CGFloat = rect.height < 300 ? 13 : 17
        overlay.fontSize = fontSize
        overlay.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let textHeight = min(fontSize * 4, rect.height - 8)
        overlay.frame = CGRect(x: 6, y: (rect.height - textHeight) / 2, width: rect.width - 12, height: textHeight)
        CATransaction.commit()
        label.frame = NSRect(x: 8, y: Panel.labelHeight - 42, width: rect.width - 16, height: 22)
        (window.contentView as? PanelView)?.screenRect = content.frame
    }

    // Text over the screen (e.g. "Reconnecting…"), optionally dimming what is under it; nil removes it.
    func setOverlay(_ text: String?, dim dimmed: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        overlay.string = text
        overlay.isHidden = text == nil
        dim.isHidden = !(text != nil && dimmed)
        CATransaction.commit()
    }

    func show(_ surface: IOSurface) {
        guard showsMirror else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.contents = surface
        content.contentsRect = contentsRect
        CATransaction.commit()
    }

    func close() { window.close() }
}

// Clicks reach the panel only if the cursor did not cross into it on its own (see Portal); then a click steps in.
final class PanelView: NSView {
    let onClick: (CGPoint) -> Void
    var screenRect = CGRect.zero
    init(frame: NSRect, onClick: @escaping (CGPoint) -> Void) {
        self.onClick = onClick
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { click(e) }
    override func rightMouseDown(with e: NSEvent) { click(e) }
    override func scrollWheel(with e: NSEvent) { click(e) }
    private func click(_ e: NSEvent) {
        guard screenRect.contains(convert(e.locationInWindow, from: nil)) else { return }
        onClick(CGEvent(source: nil)?.location ?? .zero)
    }
}
