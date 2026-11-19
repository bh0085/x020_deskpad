import AppKit

// The virtual monitor. CGVirtualDisplay is a private CoreGraphics class (header: CGVirtualDisplayPrivate.h, from
// upstream DeskPad); the display exists for as long as this object does.
final class VirtualDisplay {
    let display: CGVirtualDisplay
    let size: CGSize   // points; the pixel size is twice this
    var id: CGDirectDisplayID { display.displayID }
    var bounds: CGRect { CGDisplayBounds(id) }

    init(size: CGSize) {
        self.size = size
        let d = CGVirtualDisplayDescriptor()
        d.setDispatchQueue(DispatchQueue.main)
        d.name = Config.displayName
        d.maxPixelsWide = UInt32(size.width * 2)
        d.maxPixelsHigh = UInt32(size.height * 2)
        // A physical size that works out to the Studio Display's 218 pixels per inch, so macOS treats it as Retina.
        d.sizeInMillimeters = CGSize(width: size.width * 2 / 218 * 25.4, height: size.height * 2 / 218 * 25.4)
        d.vendorID = 0x3456
        d.productID = 0x1234
        // Upstream DeskPad uses serial 1. A different serial makes macOS keep this display's arrangement,
        // resolution and wallpaper separate from upstream's.
        d.serialNum = 0x0020
        display = CGVirtualDisplay(descriptor: d)

        let s = CGVirtualDisplaySettings()
        s.hiDPI = 1
        // A listed mode is in points; with hiDPI macOS also offers it at 2x, if twice the size fits the pixel maximum.
        s.modes = [CGVirtualDisplayMode(width: UInt(size.width), height: UInt(size.height), refreshRate: 60)]
        if !display.apply(s) { log("applying display settings failed") }
    }

    var isRegistered: Bool { NSScreen.screens.contains { $0.displayID == id } }

    // The display minus its own menu bar (each display has one), in global top-left coordinates.
    // Windows cannot sit under the menu bar, so the layout uses this.
    var visibleBounds: CGRect {
        guard let s = NSScreen.screens.first(where: { $0.displayID == id }) else { return bounds }
        let mainH = NSScreen.screens[0].frame.height
        let v = s.visibleFrame
        return CGRect(x: v.minX, y: mainH - v.maxY, width: v.width, height: v.height)
    }
    var isConfigured: Bool { bounds.size == size && isCornerPlaced }

    // The display touches the main display only at its bottom-right corner, so the cursor never wanders onto it.
    // DeskPad's view moves the cursor there on purpose (see Viewer).
    var cornerOrigin: CGPoint { let m = CGDisplayBounds(CGMainDisplayID()); return CGPoint(x: m.maxX, y: m.maxY) }
    var isCornerPlaced: Bool { bounds.origin == cornerOrigin }

    // Select the 2x mode with the view's size in points, and put the display at the corner. Both persist.
    func configure() {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode]) ?? []
        let hidpi = modes.first { $0.width == Int(size.width) && $0.height == Int(size.height) && $0.pixelWidth == Int(size.width * 2) }
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
        if let hidpi, CGDisplayCopyDisplayMode(id)?.pixelWidth != hidpi.pixelWidth {
            CGConfigureDisplayWithDisplayMode(cfg, id, hidpi, nil)
        } else if hidpi == nil {
            log("no \(Int(size.width))x\(Int(size.height)) @2x mode among \(modes.map { "\($0.width)x\($0.height)/\($0.pixelWidth)" })")
        }
        CGConfigureDisplayOrigin(cfg, id, Int32(cornerOrigin.x), Int32(cornerOrigin.y))
        let err = CGCompleteDisplayConfiguration(cfg, .permanently)
        if err != .success { log("display configuration failed: \(err.rawValue)") }
    }
}
