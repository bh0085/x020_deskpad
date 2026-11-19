import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var geometry: Geometry!
    var display: VirtualDisplay!
    var viewer: Viewer?
    var chromeGuard: ChromeGuard?
    var android: AndroidMirrors?
    var menu: StatusMenu?
    private var reconfiguring = false

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(atPath: Config.logDir, withIntermediateDirectories: true)
        geometry = Geometry.compute()
        display = VirtualDisplay(size: geometry.displaySize)
        menu = StatusMenu(app: self)
        // The display registers asynchronously. Then pick its 2x mode and corner position, and wait for both.
        waitUntil({ self.display.isRegistered }, timeout: 10, label: "the display to appear") {
            self.display.configure()
            self.waitUntil({ self.display.isConfigured }, timeout: 10, label: "the display mode and position") {
                self.displayReady()
            }
        }
    }

    private func displayReady() {
        log("display \(display.id) at \(NSStringFromRect(display.bounds))")
        setWallpaper()
        chromeGuard = ChromeGuard(displayBounds: { [weak self] in self?.display.bounds })
        android = AndroidMirrors(enabled: Config.showAndroid)
        android?.onLayoutChange = { [weak self] in self?.relayout() }
        relayout()
        startViewer()
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.viewer?.portal.desktopChanged()
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.viewer?.restart()
            self?.android?.poll()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
    }

    // The view: created invisible, moved onto Desktop 2, checked to be there and only there, then shown.
    // It never appears on any other desktop.
    private func startViewer() {
        guard let space = SkyLight.spaceID(forUUID: Config.desktopUUID) else {
            log("no desktop with uuid \(Config.desktopUUID); the view is not shown"); return
        }
        let v = Viewer(display: display, rect: geometry.viewerRect, space: space)
        guard v.pin() else { log("could not move the view to desktop \(space); not shown"); v.window.close(); return }
        viewer = v
        Task { @MainActor in
            do { try await v.prepare() } catch { log("view: \(error.localizedDescription)"); return }
            guard v.isOnlyOnTargetDesktop else { log("the view left desktop \(space); not shown"); return }
            v.window.alphaValue = 1
            v.start()
            log("view \(v.window.windowNumber) on desktop \(space) at \(NSStringFromRect(geometry.viewerRect))")
        }
    }

    func relayout() {
        guard let display else { return }
        let mirrors = android?.enabled == true ? android?.layoutItems ?? [] : []
        let layout = Layout.compute(display: display.visibleBounds, mirrors: mirrors)
        android?.apply(layout)
        chromeGuard?.agentZone = layout.agentZone
        chromeGuard?.placeAgentWindow()
    }

    // macOS can reset a virtual display's mode or position (after sleep, or when the main display changes).
    private func screensChanged() {
        guard display.isRegistered, !display.isConfigured, !reconfiguring else { return }
        reconfiguring = true
        log("display drifted to \(NSStringFromRect(display.bounds)); reconfiguring")
        display.configure()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.reconfiguring = false
            self?.relayout()
        }
    }

    private func setWallpaper() {
        guard FileManager.default.fileExists(atPath: Config.wallpaper),
              let screen = NSScreen.screens.first(where: { $0.displayID == display.id }) else { return }
        let url = URL(fileURLWithPath: Config.wallpaper)
        guard NSWorkspace.shared.desktopImageURL(for: screen) != url else { return }
        do {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true,
            ])
        } catch { log("wallpaper: \(error.localizedDescription)") }
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
