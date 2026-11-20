import AppKit

// ChromeGuard keeps Ben's Chrome usable while agents work in a Chrome window on DeskPad.
// Chrome opens a new window next to its most recently active window, restores windows where they were, and on a
// Dock click shows its existing windows; once the agent window lives on DeskPad, all three can happen out of sight.
// - A standard Chrome window on DeskPad whose title does not start with "Claude agents" (the agent window's given
//   name, AppleScript `set given name of window id N to "Claude agents"`) moves to the centre of the main display,
//   unless the cursor is on DeskPad (Ben is working there through the view).
// - When Chrome comes to the front (Dock, Spotlight, Launchpad, Cmd-Tab, a link) and Ben has no Chrome window it can
//   show him, Chrome would focus the agent window, out of sight, and his typing would land in the agents' tabs.
//   ChromeGuard gives him a window on his screen instead: it restores a minimized one, moves a link's new tab out of
//   the agent window into a window of its own, or presses File > New Window.
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
    private var tabTimer: Timer?
    private var agentTabBaseline: Int?        // agent window's tab count, sampled every 2 s
    private var openedWindowAt = Date.distantPast
    private var lastUserSize: CGSize?         // size of Ben's own Chrome windows, for rescued windows

    init(displayBounds: @escaping () -> CGRect?) {
        self.displayBounds = displayBounds
        dockMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] e in self?.dockClick(e) }
        // Test hooks: the activation check without activating Chrome, and a sweep with a status line in the log.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.bh0085.deskpad.chromeDockCheck"), object: nil, queue: .main) { [weak self] _ in
            self?.ensureUserWindow(tabsBefore: nil)
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.bh0085.deskpad.chromeSweep"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            log("ChromeGuard: observing \(self.appElement != nil), \(self.chromeWindows.count) windows: \(self.chromeWindows.map { "\(AX.title($0) ?? "?") \(AX.frame($0).map(NSStringFromRect) ?? "?")" })")
            self.sweep()
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
            if chrome(n) != nil { self?.chromeActivated() }
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
        tabTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, let agent = self.chromeWindows.first(where: self.isAgent) else { return }
            self.agentTabBaseline = self.tabCount(agent)
        }
        // Session restore places windows over several seconds after launch.
        for d in [0.0, 2.0, 5.0, 10.0] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in self?.sweep() } }
    }

    func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil; appElement = nil
        tabTimer?.invalidate(); tabTimer = nil
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
                  let f = AX.frame(w) else { continue }
            guard deskpad.contains(CGPoint(x: f.midX, y: f.midY)) else { lastUserSize = f.size; continue }
            // A window Chrome cascaded from the agent window has the agent zone's size; give it Ben's usual size.
            let size = (agentZone.map { f.width >= $0.width * 0.9 } ?? false) ? (lastUserSize ?? CGSize(width: 1600, height: 1100)) : f.size
            let target = mainDisplayTarget(for: size, offset: CGFloat(moved) * 24)
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
        let before = agentTabBaseline
        for d in [0.5, 2.5, 5.0] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in self?.ensureUserWindow(tabsBefore: before) } }
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

    func chromeActivated() {
        let before = agentTabBaseline
        check()
        for d in [0.35, 1.2] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in self?.ensureUserWindow(tabsBefore: before) } }
    }

    // Make sure Chrome has a window Ben can see. `tabsBefore`: the agent window's tab count before Chrome came forward.
    func ensureUserWindow(tabsBefore: Int?) {
        guard Config.chromeGuard, let appElement, let deskpad = displayBounds() else { return }
        if let cursor = CGEvent(source: nil)?.location, deskpad.contains(cursor) { return }   // Ben is working in the view
        guard Date().timeIntervalSince(openedWindowAt) > 3 else { return }                    // one is on its way
        let onDeskpad: (CGRect) -> Bool = { deskpad.contains(CGPoint(x: $0.midX, y: $0.midY)) }
        // 1. A window on the current desktop: Chrome shows it.
        var minimized: AXUIElement?
        for w in chromeWindows where !isAgent(w) {
            if AX.isMinimized(w) { minimized = w; continue }
            if let f = AX.frame(w), !onDeskpad(f) { return }
        }
        // 2. A minimized window: bring it back.
        if let minimized {
            AX.setMinimized(minimized, false)
            log("Chrome came forward: restored a minimized window"); return
        }
        // 3. A window on another desktop: macOS switches there.
        if userWindowOnOtherDesktop(deskpad: deskpad) { return }
        // 4. A link opened from another app went into a new tab of the agent window: move that tab to its own window.
        if let before = tabsBefore, let agent = chromeWindows.first(where: isAgent), let now = tabCount(agent), now > before,
           let focused = AX.copy(appElement, kAXFocusedWindowAttribute), CFEqual(focused, agent),
           let move = menuItem(appElement, menu: "Tab", item: "Move Tab to New Window") {
            AXUIElementPerformAction(move, kAXPressAction as CFString)
            agentTabBaseline = now - 1
            openedWindowAt = Date()
            log("Chrome came forward with a new tab in the agent window: moved it to a window of its own")
            check(); return
        }
        // 5. Otherwise a new window; sweep() moves it off DeskPad.
        guard let item = menuItem(appElement, menu: "File", item: "New Window") else { log("Chrome's File > New Window not found"); return }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        openedWindowAt = Date()
        log("Chrome came forward with no window on Ben's screen: opened a new window")
        check()
    }

    // A window of Ben's on a desktop he is not looking at (the window server lists it; AX, which sees only the
    // current desktops, does not). Chrome keeps 1x1 and menu-bar windows around, so only real-sized ones count.
    func userWindowOnOtherDesktop(deskpad: CGRect) -> Bool {
        let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        return info.contains { w in
            guard w[kCGWindowOwnerName as String] as? String == "Google Chrome", w[kCGWindowLayer as String] as? Int == 0,
                  w[kCGWindowIsOnscreen as String] as? Bool != true,
                  let name = w[kCGWindowName as String] as? String, !name.isEmpty, !name.hasPrefix(Config.agentWindowName),
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"], width > 300, height > 200
            else { return false }
            return !deskpad.contains(CGPoint(x: x + width / 2, y: y + height / 2))
        }
    }

    // Tabs are the radio buttons in the window's tab strip (an AXTabGroup about 7 levels down).
    func tabCount(_ w: AXUIElement) -> Int? {
        var queue: [(AXUIElement, Int)] = [(w, 0)]
        while !queue.isEmpty {
            let (e, depth) = queue.removeFirst()
            if AX.copy(e, kAXRoleAttribute) as? String == "AXTabGroup" {
                return (AX.copy(e, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { AX.copy($0, kAXRoleAttribute) as? String == "AXRadioButton" }.count
            }
            if depth < 9 { for c in AX.copy(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] { queue.append((c, depth + 1)) } }
        }
        return nil
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
