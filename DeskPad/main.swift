import AppKit

let app = NSApplication.shared
// Apply mouse movement right after a cursor warp instead of holding it back (~0.25 s by default); the view's
// step-in and step-out warp the cursor.
CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
app.setActivationPolicy(.accessory)   // no Dock icon, not in Cmd-Tab, never takes focus
let delegate = AppDelegate()
app.delegate = delegate

// `run.sh stop` sends SIGTERM; quit properly so mirrors stop and the agent window is parked first.
signal(SIGTERM, SIG_IGN)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigterm.setEventHandler { NSApp.terminate(nil) }
sigterm.resume()

app.run()
