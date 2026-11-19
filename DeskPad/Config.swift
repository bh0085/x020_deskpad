import AppKit

// Settings. Override any of them with `defaults write com.bh0085.deskpad <key> <value>` and restart DeskPad.
enum Config {
    static let defaults = UserDefaults.standard

    // Scripts and agents find the virtual display by this name; keep it.
    static let displayName = "DeskPad Display"
    // The desktop the view lives on: Desktop 2 of the Studio Display on base-mac.
    static var desktopUUID: String { defaults.string(forKey: "desktopUUID") ?? "E66111CE-C6B8-497E-871D-DF5D39D81F40" }
    // Space between the view and the edges of Desktop 2, in points.
    static var margin: CGFloat { CGFloat(defaults.object(forKey: "margin") as? Double ?? 40) }
    // Space around and between Android mirrors, in points.
    static let gap: CGFloat = 16
    // The agent zone never gets narrower than this when Android mirrors take the right side.
    static let agentMinWidth: CGFloat = 1440
    static var wallpaper: String {
        defaults.string(forKey: "wallpaper") ?? NSString(string: "~/Pictures/Undersea-Wallpapers/deskpad-inner.png").expandingTildeInPath
    }

    // The Chrome window agents work in (AppleScript `given name`); see ChromeGuard.
    static let agentWindowName = "Claude agents"

    static let adb = "/opt/homebrew/bin/adb"
    static let scrcpy = "/opt/homebrew/bin/scrcpy"
    static let logDir = NSString(string: "~/Library/Logs/DeskPad").expandingTildeInPath

    static var showAndroid: Bool {
        get { defaults.object(forKey: "showAndroid") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showAndroid") }
    }
    static var chromeGuard: Bool {
        get { defaults.object(forKey: "chromeGuard") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "chromeGuard") }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}

// Where the view goes on Desktop 2, and how big the virtual display is. The display has exactly the view's size in
// points and runs at 2x, so the view shows it pixel for pixel, as sharp as the Studio Display itself.
struct Geometry {
    let viewerRect: CGRect    // global coordinates, top-left origin
    let displaySize: CGSize   // points

    static func compute() -> Geometry {
        let main = NSScreen.screens[0]
        let menuBar = main.frame.maxY - main.visibleFrame.maxY
        let m = Config.margin
        var w = main.frame.width - 2 * m, h = main.frame.height - menuBar - 2 * m
        w = (w / 2).rounded(.down) * 2; h = (h / 2).rounded(.down) * 2
        return Geometry(viewerRect: CGRect(x: m, y: menuBar + m, width: w, height: h), displaySize: CGSize(width: w, height: h))
    }
}

func log(_ s: String) { NSLog("DeskPad: %@", s) }
