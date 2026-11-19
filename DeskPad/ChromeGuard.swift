import AppKit

// ChromeGuard keeps Ben's Chrome usable while agents work in a Chrome window on DeskPad.
// Chrome opens a new window next to its most recently active window, restores windows where they were, and on a
// Dock click shows its existing windows; once the agent window lives on DeskPad, all three can happen out of sight.
// - A standard Chrome window on DeskPad whose title does not start with "Claude agents" (the agent window's given
//   name, AppleScript `set given name of window id N to "Claude agents"`) moves to the centre of the main display,
//   unless the cursor is on DeskPad (Ben is working there through the view).
// - A Dock click on Chrome when every Chrome window sits on DeskPad restores a minimized window or presses
//   File > New Window, so the click always gives Ben a window on his screen.
// - The agent window fills the agent zone of the layout.
// Checks run when Chrome launches, activates, opens a window or changes its focused window, and on Dock clicks.
final class ChromeGuard {
    static let chromeID = "com.google.Chrome"
    let displayBounds: () -> CGRect?
    var agentZone: CGRect?
    private var agentPlacement: (zone: CGRect, result: CGRect)?   // where Chrome actually put the window last time
    var observer: AXObserver?
    var appElement: AXUIElement?
    var dockMonitor: Any?

    init(displayBounds: @escaping () -> CGRect?) {
        self.displayBounds = displayBounds
        dockMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] e in self?.dockClick(e) }
        // Test hook: the Dock-click check without a real Dock click.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.bh0085.deskpad.chromeDockCheck"), object: nil, queue: .main) { [weak self] _ in
            self?.ensureWindowOnMainDisplay()
        }
        let nc = NSWorkspace.shared.notificationCenter
        func chrome(_ n: Notification) -> NSRunningApplication? {
            let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            return a?.bundleIdentifier == Self.chromeID ? a : nil
        }
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let a = chrome(n) { self?.attach(a, tries: 20) }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if chrome(n) != nil { self?.detach() }
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if chrome(n) != nil { self?.check() }
        }
        if let a = NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeID).first { attach(a, tries: 20) }
    }

    // A freshly launched Chrome may refuse AX for a moment; retry once a second.
    func attach(_ a: NSRunningApplication, tries: Int) {
        detach()
        let pid = a.processIdentifier
        let el = AXUIElementCreateApplication(pid)
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            Unmanaged<ChromeGuard>.fromOpaque(refcon!).takeUnretainedValue().check()
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        var ok = AXObserverCreate(pid, callback, &obs) == .success
        if ok, let obs {
            for n in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
                ok = ok && AXObserverAddNotification(obs, el, n as CFString, me) == .success
            }
        }
        guard ok, let obs else {
            if tries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.attach(a, tries: tries - 1) } }
            else { log("ChromeGuard could not observe Chrome (pid \(pid))") }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs; appElement = el
        // Session restore places windows over several seconds after launch.
        for d in [0.0, 2.0, 5.0, 10.0] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in self?.sweep() } }
    }

    func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil; appElement = nil
    }

    // Chrome may still be placing a new window when the notification arrives, so look twice.
    func check() {
        for d in [0.15, 0.8] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in self?.sweep() } }
    }

    var chromeWindows: [AXUIElement] { appElement.map { AX.windows($0).filter(AX.isStandard) } ?? [] }

    func isAgent(_ w: AXUIElement) -> Bool { AX.title(w)?.hasPrefix(Config.agentWindowName) == true }

    func sweep() {
        placeAgentWindow()
        guard Config.chromeGuard, let deskpad = displayBounds() else { return }
        if let cursor = CGEvent(source: nil)?.location, deskpad.contains(cursor) { return }
        var moved = 0
        for w in chromeWindows {
            // An unreadable title must never get the agent window moved.
            guard let title = AX.title(w), !title.hasPrefix(Config.agentWindowName), !AX.isMinimized(w),
                  let f = AX.frame(w), deskpad.contains(CGPoint(x: f.midX, y: f.midY)) else { continue }
            let target = mainDisplayTarget(for: f.size, offset: CGFloat(moved) * 24)
            AX.setFrame(w, target)
            moved += 1
            log("moved Chrome window \"\(title)\" from DeskPad to \(NSStringFromRect(target))")
        }
    }

    // The agent window fills the agent zone. Minimized (parked at quit) windows come back first.
    func placeAgentWindow() {
        guard let zone = agentZone, let w = chromeWindows.first(where: isAgent) else { return }
        if AX.isMinimized(w) { AX.setMinimized(w, false) }
        guard let f = AX.frame(w) else { return }
        // Chrome may round the frame a little; accept where it put the window for this zone.
        if AX.near(f, zone, 4) || (agentPlacement?.zone == zone && agentPlacement.map { AX.near(f, $0.result) } == true) { return }
        AX.setFrame(w, zone)
        let result = AX.frame(w) ?? zone
        agentPlacement = (zone, result)
        log("agent window -> \(NSStringFromRect(result))")
    }

    // At quit the virtual display goes away and macOS would move the agent window onto Ben's screen. Minimize it
    // instead; the next DeskPad start puts it back.
    func parkAgentWindow() {
        if let w = chromeWindows.first(where: isAgent) { AX.setMinimized(w, true) }
    }

    func dockClick(_ e: NSEvent) {
        guard let p = e.cgEvent?.location, isChromeDockItem(at: p) else { return }
        // A click that launches Chrome needs time for session restore before the check means anything.
        for d in [0.5, 2.5, 5.0] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in self?.ensureWindowOnMainDisplay() } }
    }

    // The Dock autohides, so this works only at click time, when the item is on screen.
    func isChromeDockItem(at p: CGPoint) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &hit) == .success, var el = hit else { return false }
        for _ in 0..<3 {
            if AX.copy(el, kAXSubroleAttribute) as? String == "AXApplicationDockItem" { return AX.title(el) == "Google Chrome" }
            guard let parent = AX.copy(el, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            el = parent as! AXUIElement
        }
        return false
    }

    func ensureWindowOnMainDisplay() {
        guard let appElement, let deskpad = displayBounds() else { return }
        var minimized: AXUIElement?
        for w in chromeWindows {
            if AX.isMinimized(w) { if !isAgent(w) { minimized = w }; continue }
            if let f = AX.frame(w), !deskpad.contains(CGPoint(x: f.midX, y: f.midY)) { return }
        }
        if let minimized {
            AX.setMinimized(minimized, false)
            log("Dock click on Chrome: restored a minimized window"); return
        }
        guard let item = menuItem(appElement, menu: "File", item: "New Window") else { log("Chrome's File > New Window not found"); return }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        log("Dock click on Chrome with no window on the main display: opened a new window")
        check()
    }

    func menuItem(_ app: AXUIElement, menu: String, item: String) -> AXUIElement? {
        guard let bar = AX.copy(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        for top in AX.copy(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? [] where AX.title(top) == menu {
            for m in AX.copy(top, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                for i in AX.copy(m, kAXChildrenAttribute) as? [AXUIElement] ?? [] where AX.title(i) == item { return i }
            }
        }
        return nil
    }

    // Centre of the main display's visible area, in top-left-origin coordinates.
    func mainDisplayTarget(for size: CGSize, offset: CGFloat) -> CGRect {
        let primary = NSScreen.screens[0]
        let vf = primary.visibleFrame
        let vis = CGRect(x: vf.minX, y: primary.frame.height - vf.maxY, width: vf.width, height: vf.height)
        let w = min(size.width, vis.width), h = min(size.height, vis.height)
        return CGRect(x: min(vis.midX - w / 2 + offset, vis.maxX - w), y: min(vis.midY - h / 2 + offset, vis.maxY - h), width: w, height: h)
    }
}
