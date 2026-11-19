import CoreGraphics

// How the virtual display is divided: the agent zone on the left (the "Claude agents" Chrome window fills it) and
// Android mirrors in a row on the right, all the same height, each as wide as its screen's aspect ratio needs.
// With no mirrors the agent zone is the whole display.
struct Layout {
    var agentZone: CGRect
    var mirrorFrames: [String: CGRect] = [:]   // by device key

    // `mirrors`: (key, width/height of the device screen as currently rotated), in display order.
    static func compute(display d: CGRect, mirrors: [(key: String, aspect: CGFloat)]) -> Layout {
        guard !mirrors.isEmpty else { return Layout(agentZone: d) }
        let g = Config.gap
        let n = CGFloat(mirrors.count)
        let sumAspect = mirrors.reduce(0) { $0 + $1.aspect }
        // Width left for mirrors once the agent zone has its minimum, minus the gaps around and between mirrors.
        let available = d.width - Config.agentMinWidth - g * (n + 1)
        let h = max(240, min(d.height - 2 * g, available / sumAspect)).rounded(.down)
        let widths = mirrors.map { ($0.aspect * h).rounded() }
        let rowWidth = widths.reduce(0, +) + g * (n - 1)
        var x = d.maxX - g - rowWidth
        let y = (d.minY + (d.height - h) / 2).rounded()
        var layout = Layout(agentZone: CGRect(x: d.minX, y: d.minY, width: x - g - d.minX, height: d.height))
        for (m, w) in zip(mirrors, widths) {
            layout.mirrorFrames[m.key] = CGRect(x: x, y: y, width: w, height: h)
            x += w + g
        }
        return layout
    }
}
