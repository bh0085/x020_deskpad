import AppKit

// Cursor crossing between Desktop 2 and the screens its panels show. No synthetic events, only cursor moves:
// - When the cursor crosses into a panel, it moves to the matching point on that panel's screen (the Mac display,
//   or the scrcpy window on the mirrors display). Every click, drag and scroll after that is ordinary macOS input
//   on that screen, and the cursor shows in the panel.
// - When it leaves that screen (or that mirror window), or pushes against a display edge it cannot cross, it moves
//   back to Desktop 2, just outside the panel at the matching point.
// - It never moves while a mouse button is down, so a drag is never cut off.
// - Only while Desktop 2 is showing; leaving Desktop 2 while inside brings the cursor back first.
final class Portal {
    struct Region: Equatable {
        let panel: CGRect    // on Desktop 2, global top-left coordinates
        let target: CGRect   // the screen area it shows, global coordinates
    }

    var regions: [Region] = [] { didSet { regionsChanged(oldValue) } }
    var isActive: () -> Bool = { false }   // Desktop 2 is showing
    private(set) var inside: Region?
    private var monitors: [Any] = []

    init() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e) }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e); return e }) { monitors.append(l) }
    }

    private var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private func handle(_ e: NSEvent) {
        let c = cursor
        let buttonsDown = NSEvent.pressedMouseButtons != 0
        if inside == nil, let r = regions.first(where: { $0.target.contains(c) }) {
            inside = r   // already on a screen (DeskPad restarted, or something else moved the cursor there)
        }
        if let r = inside {
            guard !buttonsDown, let exit = exitPoint(r, c, dx: e.deltaX, dy: e.deltaY) else { return }
            inside = nil
            warp(exit)
            inputLog("out of \(r.target) to \(exit)")
        } else {
            guard !buttonsDown, isActive(), let r = regions.first(where: { $0.panel.contains(c) }) else { return }
            stepIn(r, at: c)
        }
    }

    // A click on a panel (the cursor did not cross in by itself, e.g. it was already there when Desktop 2 opened).
    func click(at c: CGPoint) {
        guard inside == nil, let r = regions.first(where: { $0.panel.contains(c) }) else { return }
        stepIn(r, at: c)
    }

    private func stepIn(_ r: Region, at c: CGPoint) {
        let t = map(c, from: r.panel, to: r.target)
        inside = r
        warp(t)
        inputLog("into \(r.target) at \(t)")
    }

    private func exitPoint(_ r: Region, _ c: CGPoint, dx: CGFloat, dy: CGFloat) -> CGPoint? {
        let t = r.target
        var dir = CGVector.zero
        if !t.contains(c) {
            dir = CGVector(dx: c.x < t.minX ? -1 : (c.x >= t.maxX ? 1 : 0), dy: c.y < t.minY ? -1 : (c.y >= t.maxY ? 1 : 0))
        } else {
            // At a display edge the cursor is held in place; a push outward still means "leave".
            if c.x <= t.minX + 0.5 && dx < -1 { dir.dx = -1 }
            if c.x >= t.maxX - 1.5 && dx > 1 { dir.dx = 1 }
            if c.y <= t.minY + 0.5 && dy < -1 { dir.dy = -1 }
            if c.y >= t.maxY - 1.5 && dy > 1 { dir.dy = 1 }
        }
        guard dir != .zero else { return nil }
        let clamped = CGPoint(x: min(max(c.x, t.minX), t.maxX - 1), y: min(max(c.y, t.minY), t.maxY - 1))
        let p = map(clamped, from: t, to: r.panel)
        return CGPoint(x: p.x + dir.dx * 3 + (dir.dx > 0 ? 1 : 0), y: p.y + dir.dy * 3 + (dir.dy > 0 ? 1 : 0))
    }

    // Leaving Desktop 2 while on a panel's screen: bring the cursor back to the same spot of the panel.
    func leave() {
        guard let r = inside else { return }
        inside = nil
        warp(map(cursor, from: r.target, to: r.panel))
    }

    private func regionsChanged(_ old: [Region]) {
        guard let r = inside, !regions.contains(r) else { return }
        // The layout changed under the cursor: keep it on the screen it is on if that screen still has a panel.
        inside = regions.first { $0.target.contains(cursor) }
        if inside == nil { warp(map(cursor, from: r.target, to: r.panel)) }
    }

    private func map(_ p: CGPoint, from a: CGRect, to b: CGRect) -> CGPoint {
        CGPoint(x: b.minX + (p.x - a.minX) / a.width * b.width, y: b.minY + (p.y - a.minY) / a.height * b.height)
    }

    private func warp(_ p: CGPoint) {
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}

let inputDebug = ProcessInfo.processInfo.environment["DESKPAD_DEBUG"] == "1"
func inputLog(_ s: String) { if inputDebug { log("cursor: " + s) } }
