import AppKit

// A virtual monitor. CGVirtualDisplay is a private CoreGraphics class (header: CGVirtualDisplayPrivate.h, from
// upstream DeskPad); the display exists for as long as this object does. DeskPad makes two: the agents' Mac display
// and the mirrors display that holds the scrcpy windows.
final class VirtualDisplay {
    let display: CGVirtualDisplay
    let name: String
    let size: CGSize                 // points; the display runs at 2x
    let origin: () -> CGPoint        // where it belongs in the display arrangement
    var id: CGDirectDisplayID { display.displayID }
    var bounds: CGRect { CGDisplayBounds(id) }

    init(name: String, size: CGSize, serial: UInt32, origin: @escaping () -> CGPoint) {
        self.name = name
        self.size = size
        self.origin = origin
        let d = CGVirtualDisplayDescriptor()
        d.setDispatchQueue(DispatchQueue.main)
        d.name = name
        d.maxPixelsWide = UInt32(size.width * 2)
        d.maxPixelsHigh = UInt32(size.height * 2)
        // A physical size that works out to the Studio Display's 218 pixels per inch, so macOS treats it as Retina.
        d.sizeInMillimeters = CGSize(width: size.width * 2 / 218 * 25.4, height: size.height * 2 / 218 * 25.4)
        d.vendorID = 0x3456
        d.productID = 0x1234
        // Upstream DeskPad uses serial 1. Distinct serials make macOS keep each display's arrangement, resolution
        // and wallpaper apart.
        d.serialNum = serial
        display = CGVirtualDisplay(descriptor: d)

        let s = CGVirtualDisplaySettings()
        s.hiDPI = 1
        // A listed mode is in points; with hiDPI macOS also offers it at 2x, if twice the size fits the pixel maximum.
        s.modes = [CGVirtualDisplayMode(width: UInt(size.width), height: UInt(size.height), refreshRate: 60)]
        if !display.apply(s) { log("\(name): applying display settings failed") }
    }

    var screen: NSScreen? { NSScreen.screens.first { $0.displayID == id } }
    var isRegistered: Bool { screen != nil }
    var isConfigured: Bool { bounds.size == size && bounds.origin == origin() }

    // The display minus its own menu bar (each display has one), in global top-left coordinates.
    var visibleBounds: CGRect {
        guard let s = screen else { return bounds }
        let mainH = NSScreen.screens[0].frame.height
        let v = s.visibleFrame
        return CGRect(x: v.minX, y: mainH - v.maxY, width: v.width, height: v.height)
    }

    // Select each display's 2x mode and put it at its origin, in one transaction so macOS checks the finished
    // arrangement (the mirrors display touches only the Mac display, which touches only the main display). Persists.
    static func configure(_ displays: [VirtualDisplay]) {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
        for d in displays {
            let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
            let modes = (CGDisplayCopyAllDisplayModes(d.id, opts) as? [CGDisplayMode]) ?? []
            let hidpi = modes.first { $0.width == Int(d.size.width) && $0.height == Int(d.size.height) && $0.pixelWidth == Int(d.size.width * 2) }
            if let hidpi, CGDisplayCopyDisplayMode(d.id)?.pixelWidth != hidpi.pixelWidth {
                CGConfigureDisplayWithDisplayMode(cfg, d.id, hidpi, nil)
            } else if hidpi == nil {
                log("\(d.name): no \(Int(d.size.width))x\(Int(d.size.height)) @2x mode")
            }
            let o = d.origin()
            CGConfigureDisplayOrigin(cfg, d.id, Int32(o.x), Int32(o.y))
        }
        let err = CGCompleteDisplayConfiguration(cfg, .permanently)
        if err != .success { log("display configuration failed: \(err.rawValue)") }
    }

    func setWallpaper(_ url: URL, fill: NSColor? = nil) {
        guard let screen, NSWorkspace.shared.desktopImageURL(for: screen) != url else { return }
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true]
        if let fill { options[.fillColor] = fill }
        do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options) } catch { log("\(name) wallpaper: \(error.localizedDescription)") }
    }
}
