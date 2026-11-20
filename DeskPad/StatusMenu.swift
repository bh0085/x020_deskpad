import AppKit

// DeskPad's only UI besides the view: a menu-bar item with the options.
final class StatusMenu: NSObject, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
        super.init()
        item.button?.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "DeskPad")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = app.mac.size
        menu.addItem(NSMenuItem(title: "\(Config.displayName): \(Int(s.width)) × \(Int(s.height)) at 2x", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(toggle("Show Android devices", on: Config.showAndroid, #selector(toggleAndroid)))
        if Config.showAndroid {
            let lines = app.android?.statusLines ?? []
            for line in lines.isEmpty ? ["No devices connected"] : lines {
                menu.addItem(NSMenuItem(title: "    " + line, action: nil, keyEquivalent: ""))
            }
        }
        menu.addItem(toggle("Keep my Chrome windows off DeskPad", on: Config.chromeGuard, #selector(toggleChromeGuard)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit DeskPad", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func toggle(_ title: String, on: Bool, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.state = on ? .on : .off
        return i
    }

    @objc func toggleAndroid() {
        Config.showAndroid.toggle()
        app.android?.setEnabled(Config.showAndroid)
    }

    @objc func toggleChromeGuard() {
        Config.chromeGuard.toggle()
        app.chromeGuard?.sweep()
    }

    @objc func quit() { NSApp.terminate(nil) }
}
