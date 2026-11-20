import CoreGraphics

// Desktop 2's layout (docs/desktop2-layout.svg draws it): the Mac panel, then one panel per Android device, in a row,
// all the same height, each as wide as its screen's shape needs, 48 pt apart, at least 52 pt from the sides, centred
// under the menu bar. The row is as tall as the Mac display (960 pt) unless it would be too wide; then everything
// scales down together (the Mac display keeps its size; its panel shows it scaled).
// Each device's scrcpy window sits on the mirrors display at its panel's size, so mirrors are shown 1:1.
// Minimized devices (asleep, set to minimize) become small cards in the bottom-right corner instead; their scrcpy
// windows keep running at a small size, so waking one brings its panel straight back.
struct Layout {
    struct Device { let key: String; let panel: CGRect; let mirror: CGRect }
    var mac: CGRect
    var devices: [Device] = []
    var tiles: [Device] = []
    static let tileSize = CGSize(width: 230, height: 56)

    // area: Desktop 2 below its menu bar. mirrors: the mirrors display below its menu bar.
    static func compute(area: CGRect, macSize: CGSize, devices: [(key: String, aspect: CGFloat)],
                        minimized: [(key: String, aspect: CGFloat)] = [], mirrors: CGRect) -> Layout {
        let m = Config.margin, g = Config.gap
        let aspects = [macSize.width / macSize.height] + devices.map(\.aspect)
        let k = CGFloat(aspects.count)
        let fitWidth = (area.width - 2 * m - g * (k - 1)) / aspects.reduce(0, +)
        let h = min(macSize.height, fitWidth, area.height - 2 * m).rounded(.down)
        let widths = aspects.map { ($0 * h).rounded() }
        let row = widths.reduce(0, +) + g * (k - 1)
        var x = area.minX + ((area.width - row) / 2).rounded()
        let y = area.minY + ((area.height - h) / 2).rounded()
        var layout = Layout(mac: CGRect(x: x, y: y, width: widths[0], height: h))
        x += widths[0] + g
        var mx = mirrors.minX + 24
        for (d, w) in zip(devices, widths.dropFirst()) {
            layout.devices.append(Device(key: d.key, panel: CGRect(x: x, y: y, width: w, height: h),
                                         mirror: CGRect(x: mx, y: mirrors.minY + 24, width: w, height: h)))
            x += w + g
            mx += w + 24
        }
        var tx = area.maxX - 24
        let ty = area.maxY - 24 - tileSize.height
        for d in minimized {
            tx -= tileSize.width
            let mw = (d.aspect * 240).rounded()
            layout.tiles.append(Device(key: d.key, panel: CGRect(x: tx, y: ty, width: tileSize.width, height: tileSize.height),
                                       mirror: CGRect(x: mx, y: mirrors.minY + 24, width: mw, height: 240)))
            tx -= 16
            mx += mw + 24
        }
        return layout
    }
}
