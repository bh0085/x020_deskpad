import AppKit

// Small Accessibility helpers. AX coordinates are global, top-left origin.
enum AX {
    static func copy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
    }

    static func windows(_ app: AXUIElement) -> [AXUIElement] { copy(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    static func windows(pid: pid_t) -> [AXUIElement] { windows(AXUIElementCreateApplication(pid)) }

    static func title(_ w: AXUIElement) -> String? { copy(w, kAXTitleAttribute) as? String }
    static func isStandard(_ w: AXUIElement) -> Bool { copy(w, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole as String }
    static func isMinimized(_ w: AXUIElement) -> Bool { copy(w, kAXMinimizedAttribute) as? Bool == true }
    static func setMinimized(_ w: AXUIElement, _ on: Bool) {
        AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    static func frame(_ w: AXUIElement) -> CGRect? {
        guard let p = copy(w, kAXPositionAttribute), let s = copy(w, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    static func setPosition(_ w: AXUIElement, _ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v) }
    }

    static func setSize(_ w: AXUIElement, _ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, v) }
    }

    // Move first (onto the target display), then size, then move again in case the size change shifted it.
    static func setFrame(_ w: AXUIElement, _ r: CGRect) {
        setPosition(w, r.origin); setSize(w, r.size); setPosition(w, r.origin)
    }

    static func near(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
