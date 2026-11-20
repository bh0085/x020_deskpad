import AppKit

// Android devices connected over adb (USB or Wi-Fi debugging), each mirrored with scrcpy
// (github.com/Genymobile/scrcpy) in a borderless window on the mirrors display; a panel on Desktop 2 shows each one.
// Mirrors come and go with the devices and follow rotation and folding.
// scrcpy runs with SDL_MAC_BACKGROUND_APP=1, so starting it never takes focus from Ben, and with
// SDL_MAC_MOUSE_FOCUS_CLICKTHROUGH=1, so a click on a mirror reaches the phone even while scrcpy is in the background.
// --no-power-on keeps a DeskPad start from waking every phone.
final class AndroidMirrors {
    struct Device {
        let adbSerial: String   // adb's name for it: USB serial, ip:port, or Wi-Fi debugging name
        let key: String         // hardware serial, so a phone on USB and Wi-Fi at once gets one mirror
        let model: String
        let name: String        // the name set on the phone (Settings > About), e.g. "Galaxy Z Fold7"
        let usb: Bool
        var aspect: CGFloat     // width / height of the screen as currently rotated
    }

    final class Mirror {
        var device: Device
        var process: Process?
        var frame: CGRect = .zero
        var launches: [Date] = []
        init(device: Device) { self.device = device }
        var title: String { "Android · \(device.name)" }
        var running: Bool { process?.isRunning == true }
    }

    private(set) var mirrors: [String: Mirror] = [:]
    private(set) var enabled: Bool
    var onLayoutChange: (() -> Void)?
    private let adbQueue = DispatchQueue(label: "deskpad.adb")
    private var hardwareSerials: [String: String] = [:]   // touched only on adbQueue
    private var pollTimer: Timer?
    private var rotationTimer: Timer?
    private var polling = false

    init(enabled: Bool) {
        self.enabled = enabled
        // Mirrors left behind by an earlier DeskPad that crashed or was killed.
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill"); p.arguments = ["-f", "window-title=Android ·"]
        try? p.run(); p.waitUntilExit()
        if enabled { startPolling() }
    }

    var layoutItems: [(key: String, aspect: CGFloat)] {
        mirrors.values.sorted { $0.device.key < $1.device.key }.map { ($0.device.key, $0.device.aspect) }
    }

    var statusLines: [String] {
        mirrors.values.sorted { $0.device.key < $1.device.key }.map {
            "\($0.device.name) (\($0.device.usb ? "USB" : "Wi-Fi"))" + ($0.running ? "" : ", not mirroring")
        }
    }

    func name(of key: String) -> String { mirrors[key]?.device.name ?? key }

    func setEnabled(_ on: Bool) {
        enabled = on
        if on { startPolling() } else { stopPolling(); stopAll(); mirrors = [:] }
        onLayoutChange?()
    }

    func stopAll() { for m in mirrors.values { m.process?.terminate() } }

    private func startPolling() {
        guard pollTimer == nil else { return }
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.checkWindows() }
    }

    private func stopPolling() {
        pollTimer?.invalidate(); pollTimer = nil
        rotationTimer?.invalidate(); rotationTimer = nil
    }

    func poll() {
        guard enabled, !polling else { return }
        polling = true
        let known = Dictionary(mirrors.values.map { ($0.device.adbSerial, $0.device.aspect) }, uniquingKeysWith: { a, _ in a })
        adbQueue.async {
            let devices = self.listDevices(knownAspects: known)
            DispatchQueue.main.async { self.polling = false; self.reconcile(devices) }
        }
    }

    private func reconcile(_ devices: [Device]?) {
        guard enabled, let devices else { return }   // nil: adb itself failed; keep what we have
        var changed = false
        let keys = Set(devices.map(\.key))
        for (k, m) in mirrors where !keys.contains(k) {
            m.process?.terminate()
            mirrors[k] = nil
            changed = true
            log("Android: \(m.device.name) disconnected")
        }
        for var d in devices {
            if let m = mirrors[d.key] {
                if m.device.adbSerial != d.adbSerial {   // switched between USB and Wi-Fi: mirror over the new link
                    d.aspect = m.device.aspect
                    m.device = d
                    m.process?.terminate()
                    m.launches = []
                }
            } else {
                mirrors[d.key] = Mirror(device: d)
                changed = true
                log("Android: \(d.name) connected (\(d.adbSerial))")
            }
        }
        if changed { onLayoutChange?() } else { relaunchStopped() }
    }

    // Place each mirror (frames on the mirrors display, by device key); start scrcpy where it is not running.
    func apply(_ frames: [String: CGRect]) {
        for m in mirrors.values {
            guard let f = frames[m.device.key] else { continue }
            let moved = !AX.near(m.frame, f)
            m.frame = f
            if m.running {
                if moved, let w = window(of: m) { AX.setFrame(w, f) }
            } else {
                launch(m)
            }
        }
    }

    private func relaunchStopped() {
        for m in mirrors.values where !m.running && m.frame != .zero { launch(m) }
    }

    private func launch(_ m: Mirror) {
        let now = Date()
        m.launches = m.launches.filter { now.timeIntervalSince($0) < 60 }
        guard m.launches.count < 3 else { return }   // scrcpy keeps failing: wait for the device to reconnect
        m.launches.append(now)
        let f = m.frame
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Config.scrcpy)
        p.arguments = ["-s", m.device.adbSerial, "--no-audio", "--no-power-on", "--window-borderless",
                       "--window-title=\(m.title)",
                       "--window-x=\(Int(f.minX))", "--window-y=\(Int(f.minY))",
                       "--window-width=\(Int(f.width))", "--window-height=\(Int(f.height))",
                       "--max-size=\(Int(max(f.width, f.height) * 2))"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin"
        env["ADB"] = Config.adb
        env["SDL_MAC_BACKGROUND_APP"] = "1"
        env["SDL_MAC_MOUSE_FOCUS_CLICKTHROUGH"] = "1"
        p.environment = env
        let logPath = (Config.logDir as NSString).appendingPathComponent("scrcpy-\(m.device.key).log")
        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let h = FileHandle(forWritingAtPath: logPath) { p.standardOutput = h; p.standardError = h }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                if m.process === proc { m.process = nil }
                self?.poll()
            }
        }
        do {
            try p.run()
            m.process = p
            log("Android: mirroring \(m.device.name) at \(NSStringFromRect(f))")
        } catch {
            log("Android: scrcpy failed to start: \(error)")
        }
    }

    private func window(of m: Mirror) -> AXUIElement? {
        guard let pid = m.process?.processIdentifier else { return nil }
        let ws = AX.windows(pid: pid)
        return ws.first { AX.title($0) == m.title } ?? ws.first
    }

    // scrcpy reshapes its window when the phone rotates: take the new shape and lay everything out again.
    // A window moved or resized any other way goes back to its place.
    private func checkWindows() {
        var rotated = false
        for m in mirrors.values where m.running {
            guard let w = window(of: m), let f = AX.frame(w), f.height > 0, !AX.near(f, m.frame) else { continue }
            let aspect = f.width / f.height
            if abs(aspect - m.device.aspect) / m.device.aspect > 0.05 {
                m.device.aspect = aspect
                rotated = true
                log("Android: \(m.device.name) changed shape (rotated or folded)")
            } else {
                AX.setFrame(w, m.frame)
            }
        }
        if rotated { onLayoutChange?() }
    }

    // MARK: adb (runs on adbQueue)

    private func listDevices(knownAspects: [String: CGFloat]) -> [Device]? {
        guard let out = run(Config.adb, ["devices", "-l"]) else { return nil }
        var found: [Device] = []
        var listed = Set<String>()
        for line in out.split(separator: "\n").dropFirst() {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let serial = parts[0]
            listed.insert(serial)
            if parts[1] == "offline" && serial.contains(":") {   // a Wi-Fi link that died; its phone may be back on a new port
                _ = run(Config.adb, ["disconnect", serial])
                listed.remove(serial)
                continue
            }
            guard parts[1] == "device" else { continue }   // skip unauthorized and the like
            var props: [String: String] = [:]
            for p in parts.dropFirst(2) {
                if let i = p.firstIndex(of: ":") { props[String(p[..<i])] = String(p[p.index(after: i)...]) }
            }
            let usb = props["usb"] != nil
            let model = (props["model"] ?? serial).replacingOccurrences(of: "_", with: " ")
            let aspect = knownAspects[serial] ?? screenAspect(serial) ?? 0.45
            found.append(Device(adbSerial: serial, key: hardwareSerial(serial, usb: usb), model: model,
                                name: deviceName(serial) ?? model, usb: usb, aspect: aspect))
        }
        var byKey: [String: Device] = [:]   // prefer USB when a phone is connected both ways
        for d in found where byKey[d.key] == nil || (d.usb && byKey[d.key]?.usb == false) { byKey[d.key] = d }
        rememberApproved(Set(found.map(\.key)))
        connectWireless(listed: listed)
        return Array(byKey.values)
    }

    // Phones that have approved this Mac's adb key (seen working over USB or Wi-Fi), by hardware serial.
    private var approved: Set<String> { Set(UserDefaults.standard.stringArray(forKey: "approvedAndroidDevices") ?? []) }
    private func rememberApproved(_ keys: Set<String>) {
        let all = approved.union(keys)
        if all != approved { UserDefaults.standard.set(all.sorted(), forKey: "approvedAndroidDevices") }
    }

    // Wi-Fi: every 10 s, look up phones advertising wireless debugging (mDNS) and connect to the approved ones that
    // are not connected over Wi-Fi yet, including phones on USB, so pulling the cable switches the mirror to Wi-Fi.
    // A phone's port changes when it reboots or rejoins Wi-Fi; this finds the new one. Phones that have never
    // approved this Mac are left alone: connecting would put an "Allow debugging?" prompt on their screen.
    // The approval given over USB covers Wi-Fi too; no pairing needed.
    private var nextScan = Date.distantPast
    private func connectWireless(listed: Set<String>) {
        guard Date() >= nextScan else { return }
        nextScan = Date().addingTimeInterval(10)
        guard let out = run(Config.adb, ["mdns", "services"]) else { return }
        let known = approved
        for line in out.split(separator: "\n") where line.contains("_adb-tls-connect._tcp") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 3, parts[0].hasPrefix("adb-") else { continue }
            let name = parts[0], address = parts[2]
            let hw = name.dropFirst(4).split(separator: "-").first.map(String.init) ?? ""
            guard known.contains(hw), !listed.contains(address), !listed.contains(where: { $0.hasPrefix(name) }) else { continue }
            if let r = run(Config.adb, ["connect", address]), r.contains("connected to") {
                log("Android: connected \(hw) over Wi-Fi at \(address)")
            }
        }
    }

    private var deviceNames: [String: String] = [:]   // touched only on adbQueue
    private func deviceName(_ serial: String) -> String? {
        if let n = deviceNames[serial] { return n }
        guard let n = run(Config.adb, ["-s", serial, "shell", "settings", "get", "global", "device_name"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty, n != "null" else { return nil }
        deviceNames[serial] = n
        return n
    }

    private func hardwareSerial(_ serial: String, usb: Bool) -> String {
        if usb { return serial }
        if let cached = hardwareSerials[serial] { return cached }
        var hw = serial
        // Wi-Fi debugging names look like adb-<serial>-<suffix>._adb-tls-connect._tcp
        if serial.hasPrefix("adb-"), let dash = serial.dropFirst(4).firstIndex(of: "-") {
            hw = String(serial[serial.index(serial.startIndex, offsetBy: 4)..<dash])
        } else if let s = run(Config.adb, ["-s", serial, "shell", "getprop", "ro.serialno"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            hw = s
        }
        hardwareSerials[serial] = hw
        return hw
    }

    // Current (rotated) screen size from `dumpsys window displays` ("cur=1080x2410"), else the physical size.
    private func screenAspect(_ serial: String) -> CGFloat? {
        func dims(_ s: Substring) -> CGFloat? {
            let wh = s.split(separator: "x")
            guard wh.count == 2, let w = Double(wh[0]), let h = Double(wh[1]), h > 0 else { return nil }
            return CGFloat(w / h)
        }
        if let out = run(Config.adb, ["-s", serial, "shell", "dumpsys", "window", "displays"]),
           let r = out.range(of: #"cur=\d+x\d+"#, options: .regularExpression) {
            return dims(out[r].dropFirst(4))
        }
        if let out = run(Config.adb, ["-s", serial, "shell", "wm", "size"]),
           let r = out.range(of: #"\d+x\d+"#, options: [.regularExpression, .backwards]) {
            return dims(out[r])
        }
        return nil
    }

    private func run(_ exe: String, _ args: [String], timeout: TimeInterval = 8) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
