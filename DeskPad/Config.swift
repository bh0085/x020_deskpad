import AppKit

// Settings. Override any of them with `defaults write com.bh0085.deskpad <key> <value>` and restart DeskPad.
enum Config {
    static let defaults = UserDefaults.standard

    // Scripts and agents find the virtual display by this name; keep it.
    static let displayName = "DeskPad Display"
    // The desktop the view lives on: Desktop 2 of the Studio Display on base-mac.
    static var desktopUUID: String { defaults.string(forKey: "desktopUUID") ?? "E66111CE-C6B8-497E-871D-DF5D39D81F40" }
    // The agents' Mac display, in points; it runs at 2x and its panel on Desktop 2 shows it pixel for pixel.
    static var macSize: CGSize {
        CGSize(width: defaults.object(forKey: "macWidth") as? Double ?? 1536, height: defaults.object(forKey: "macHeight") as? Double ?? 960)
    }
    // A second virtual display holds the scrcpy windows; their panels on Desktop 2 show them. Nobody looks at it directly.
    static let mirrorsDisplayName = "DeskPad Mirrors"
    static let mirrorsSize = CGSize(width: 2400, height: 1100)
    // Desktop 2 layout: at least `margin` at the sides, `gap` between panels, labels under the panels.
    static let margin: CGFloat = 52
    static let gap: CGFloat = 48
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

func log(_ s: String) { NSLog("DeskPad: %@", s) }
