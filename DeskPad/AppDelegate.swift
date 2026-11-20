import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var mac: VirtualDisplay!       // the agents' Mac screen
    var mirrors: VirtualDisplay!   // holds the scrcpy windows
    var macCapture: DisplayCapture?
    var mirrorsCapture: DisplayCapture?
    var macPanel: Panel?
    var devicePanels: [String: Panel] = [:]
    let portal = Portal()
    var space: UInt64?             // Desktop 2
    var chromeGuard: ChromeGuard?
    var android: AndroidMirrors?
    var menu: StatusMenu?
    private(set) var layout: Layout?
    private var mirrorsSurface: IOSurface?
    private var reconfiguring = false
    private let macTitle = "Agents' Mac · DeskPad Display"

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(atPath: Config.logDir, withIntermediateDirectories: true)
        let main = { CGDisplayBounds(CGMainDisplayID()) }
        // The Mac display touches the main display only at its bottom-right corner, so the cursor never wanders
        // onto it; the mirrors display touches the Mac display the same way. Portal moves the cursor between them.
        mac = VirtualDisplay(name: Config.displayName, size: Config.macSize, serial: 0x20) {
            CGPoint(x: main().maxX, y: main().maxY)
        }
        mirrors = VirtualDisplay(name: Config.mirrorsDisplayName, size: Config.mirrorsSize, serial: 0x21) { [unowned self] in
            CGPoint(x: main().maxX + self.mac.size.width, y: main().maxY + self.mac.size.height)
        }
        menu = StatusMenu(app: self)
        waitUntil({ self.mac.isRegistered && self.mirrors.isRegistered }, timeout: 10, label: "the displays to appear") {
            VirtualDisplay.configure([self.mac, self.mirrors])
            self.waitUntil({ self.mac.isConfigured && self.mirrors.isConfigured }, timeout: 10, label: "display modes and positions") {
                self.displaysReady()
            }
        }
    }

    private func displaysReady() {
        log("Mac display at \(NSStringFromRect(mac.bounds)), mirrors display at \(NSStringFromRect(mirrors.bounds))")
        mac.setWallpaper(URL(fileURLWithPath: Config.wallpaper))
        if let black = blackImage() { mirrors.setWallpaper(black, fill: .black) }
        space = SkyLight.spaceID(forUUID: Config.desktopUUID)
        if space == nil { log("no desktop with uuid \(Config.desktopUUID); panels not shown") }
        chromeGuard = ChromeGuard(displayBounds: { [weak self] in
            self.map { VirtualArea(rects: [$0.mac.bounds, $0.mirrors.bounds]) }
        })
        android = AndroidMirrors(enabled: Config.showAndroid)
        android?.onLayoutChange = { [weak self] in self?.relayout() }
        portal.isActive = { [weak self] in self?.macPanel?.window.isOnActiveSpace == true }
        relayout()

        let mc = DisplayCapture(display: mac)
        mc.onFrame = { [weak self] s in self?.macPanel?.show(s) }
        let rc = DisplayCapture(display: mirrors)
        rc.onFrame = { [weak self] s in
            self?.mirrorsSurface = s
            self?.devicePanels.values.forEach { $0.show(s) }
        }
        macCapture = mc; mirrorsCapture = rc
        mc.restart(); rc.restart()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.macPanel?.window.isOnActiveSpace != true { self.portal.leave() }
            self.macCapture?.ensureRunning(); self.mirrorsCapture?.ensureRunning()
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.macCapture?.restart(); self?.mirrorsCapture?.restart()
                self?.android?.poll()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
    }

    // Desktop 2 below its menu bar, global top-left coordinates.
    private var desktopArea: CGRect {
        let s = NSScreen.screens[0]
        let menuBar = s.frame.maxY - s.visibleFrame.maxY
        return CGRect(x: 0, y: menuBar, width: s.frame.width, height: s.frame.height - menuBar)
    }

    func relayout() {
        guard let mac, let mirrors else { return }
        let items = android?.enabled == true ? android?.layoutItems ?? [] : []
        let l = Layout.compute(area: desktopArea, macSize: mac.size, devices: items, mirrors: mirrors.visibleBounds)
        if let space {
            if let p = macPanel { p.setRect(l.mac, title: macTitle) }
            else { macPanel = Panel(rect: l.mac, title: macTitle, space: space) { [weak self] c in self?.portal.click(at: c) } }
            let keys = Set(l.devices.map(\.key))
            for (k, p) in devicePanels where !keys.contains(k) { p.close(); devicePanels[k] = nil }
            for d in l.devices {
                let title = android?.name(of: d.key) ?? d.key
                guard let p = devicePanels[d.key] ?? Panel(rect: d.panel, title: title, space: space, onClick: { [weak self] c in self?.portal.click(at: c) }) else { continue }
                p.setRect(d.panel, title: title)
                // Half a point in from each edge, so texture filtering never pulls in what is next to the mirror.
                p.contentsRect = unitRect(d.mirror.insetBy(dx: 0.5, dy: 0.5), in: mirrors.bounds)
                if let s = mirrorsSurface { p.show(s) }
                devicePanels[d.key] = p
            }
        }
        android?.apply(Dictionary(l.devices.map { ($0.key, $0.mirror) }, uniquingKeysWith: { a, _ in a }))
        var regions: [Portal.Region] = []
        if macPanel != nil { regions.append(.init(panel: l.mac, target: mac.bounds)) }
        regions += l.devices.filter { devicePanels[$0.key] != nil }.map { .init(panel: $0.panel, target: $0.mirror) }
        portal.regions = regions
        chromeGuard?.agentZone = mac.visibleBounds
        chromeGuard?.placeAgentWindow()
        if layout.map({ $0.mac != l.mac || $0.devices.map(\.panel) != l.devices.map(\.panel) }) ?? true {
            log("layout: Mac \(NSStringFromRect(l.mac)); " + l.devices.map { "\(android?.name(of: $0.key) ?? $0.key) \(NSStringFromRect($0.panel))" }.joined(separator: "; "))
        }
        layout = l
    }

    // A rect on a display as the part of that display's captured frame, in the layer's unit coordinates
    // (origin at the bottom left on macOS).
    private func unitRect(_ r: CGRect, in b: CGRect) -> CGRect {
        CGRect(x: (r.minX - b.minX) / b.width, y: 1 - (r.maxY - b.minY) / b.height, width: r.width / b.width, height: r.height / b.height)
    }

    // macOS can reset a virtual display's mode or position (after sleep, or when the main display changes).
    private func screensChanged() {
        guard mac.isRegistered, mirrors.isRegistered, !(mac.isConfigured && mirrors.isConfigured), !reconfiguring else { return }
        reconfiguring = true
        log("displays drifted (Mac \(NSStringFromRect(mac.bounds)), mirrors \(NSStringFromRect(mirrors.bounds))); reconfiguring")
        VirtualDisplay.configure([mac, mirrors])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.reconfiguring = false
            self?.relayout()
        }
    }

    // The mirrors display's wallpaper: plain black, so any gap around a mirror looks like the phone's own border.
    private func blackImage() -> URL? {
        let dir = NSString(string: "~/Library/Application Support/DeskPad").expandingTildeInPath
        let url = URL(fileURLWithPath: dir).appendingPathComponent("black.png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        return url
    }

    func applicationWillTerminate(_ n: Notification) {
        android?.stopAll()
        chromeGuard?.parkAgentWindow()
        log("quit")
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval, label: String, then: @escaping () -> Void) {
        let start = Date()
        func tick() {
            if condition() { then(); return }
            if Date().timeIntervalSince(start) > timeout { log("gave up waiting for \(label); continuing"); then(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { tick() }
        }
        tick()
    }
}
