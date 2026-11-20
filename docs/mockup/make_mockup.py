#!/usr/bin/env python3
"""Draw docs/desktop2-layout.svg: Desktop 2 with the Mac panel and Android device panels, 1 SVG unit = 1 pt.

The layout rule here is the one DeskPad implements:
  H = min(960, (2560 - 2*52 - 48*(k-1)) / sum(aspects)),   k panels, the Mac panel's aspect is 1.6
  each panel is round(aspect*H) wide and H tall; 48 pt gaps; the row is centred below the 30 pt menu bar.
"""
import base64, pathlib

HERE = pathlib.Path(__file__).parent
OUT = HERE.parent / "desktop2-layout.svg"
W, H_DESK, MENU = 2560, 1440, 30
GAP, MARGIN, MAC_ASPECT, H_MAX = 48, 52, 1.6, 960
FOLD_OPEN, FOLD_CLOSED, PIXEL = 1968 / 2184, 1080 / 2520, 1080 / 2410
PINK = "#ff2d95"
FONT = "-apple-system, 'SF Pro Text', 'Helvetica Neue', Helvetica, Arial, sans-serif"


def img(name):
    return "data:image/jpeg;base64," + base64.b64encode((HERE / name).read_bytes()).decode()


def layout(aspects):
    """aspects: Mac first. Returns [(x, y, w, h)]."""
    k = len(aspects)
    h = min(H_MAX, (W - 2 * MARGIN - GAP * (k - 1)) / sum(aspects))
    h = int(h)
    widths = [round(a * h) for a in aspects]
    row = sum(widths) + GAP * (k - 1)
    x = round((W - row) / 2)
    y = round(MENU + (H_DESK - MENU - h) / 2)
    rects = []
    for w in widths:
        rects.append((x, y, w, h))
        x += w + GAP
    return rects


BG, INNER = img("mock-desktop2.jpg"), img("mock-deskpad.jpg")
svg = []
add = svg.append


def menu_bar(x, y, w, h, app_items, right, font=14, fill="rgba(10,20,40,0.38)"):
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}"/>')
    cx = x + 18
    for i, t in enumerate(app_items):
        weight = "700" if i == 1 else "400"
        add(f'<text x="{cx}" y="{y + h * 0.68:.1f}" font-size="{font}" font-weight="{weight}" fill="#fff">{t}</text>')
        cx += len(t) * font * 0.56 + font * 1.3
    add(f'<text x="{x + w - 16}" y="{y + h * 0.68:.1f}" font-size="{font}" fill="#fff" text-anchor="end">{right}</text>')


def chrome_window(x, y, w, h):
    """The agents' Chrome window, schematic, at real size."""
    add(f'<g clip-path="url(#chromeclip)">')
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#fff"/>')
    add(f'<rect x="{x}" y="{y}" width="{w}" height="40" fill="#f6d36b"/>')
    for i, c in enumerate(["#ff5f57", "#febc2e", "#28c840"]):
        add(f'<circle cx="{x + 20 + i * 20}" cy="{y + 20}" r="6" fill="{c}"/>')
    tabs = ["Wegmans cart", "Keep · Groceries", "Gemini", "Claude agents task"]
    tx = x + 90
    for i, t in enumerate(tabs):
        active = i == 3
        if active:
            add(f'<path d="M{tx},{y + 40} q8,0 8,-8 v-22 q0,-6 6,-6 h214 q6,0 6,6 v22 q0,8 8,8 z" fill="#fff"/>')
        else:
            add(f'<line x1="{tx + 236}" y1="{y + 12}" x2="{tx + 236}" y2="{y + 30}" stroke="#c9a94a" stroke-width="1"/>')
        add(f'<circle cx="{tx + 26}" cy="{y + 22}" r="7" fill="{"#7aa7ff" if active else "#c4a24a"}"/>')
        add(f'<text x="{tx + 40}" y="{y + 27}" font-size="13" fill="#3c3c3c">{t}</text>')
        tx += 236
    add(f'<rect x="{x}" y="{y + 40}" width="{w}" height="40" fill="#fff"/>')
    for i in range(3):
        add(f'<circle cx="{x + 24 + i * 32}" cy="{y + 60}" r="8" fill="none" stroke="#5f6368" stroke-width="1.6"/>')
    add(f'<rect x="{x + 120}" y="{y + 47}" width="{w - 260}" height="26" rx="13" fill="#f1f3f4"/>')
    add(f'<text x="{x + 142}" y="{y + 65}" font-size="13.5" fill="#5f6368">shop.wegmans.com/cart</text>')
    add(f'<rect x="{x}" y="{y + 80}" width="{w}" height="26" fill="#fff"/>')
    for i in range(7):
        add(f'<rect x="{x + 14 + i * 118}" y="{y + 85}" width="104" height="16" rx="8" fill="#f1f3f4"/>')
    add(f'<line x1="{x}" y1="{y + 106}" x2="{x + w}" y2="{y + 106}" stroke="#e3e3e3"/>')
    # a page
    px = x + 120
    add(f'<rect x="{px}" y="{y + 140}" width="{w - 240}" height="64" rx="8" fill="#eef4ee"/>')
    add(f'<text x="{px + 24}" y="{y + 181}" font-size="24" font-weight="600" fill="#2f5d34">Your cart · 23 items</text>')
    for r in range(9):
        ry = y + 236 + r * 70
        add(f'<rect x="{px}" y="{ry}" width="54" height="54" rx="6" fill="#e9ecef"/>')
        add(f'<rect x="{px + 74}" y="{ry + 8}" width="{360 + (r * 53) % 260}" height="14" rx="7" fill="#d9dde1"/>')
        add(f'<rect x="{px + 74}" y="{ry + 32}" width="{160 + (r * 37) % 120}" height="12" rx="6" fill="#eceff1"/>')
        add(f'<rect x="{x + w - 240 - 90}" y="{ry + 14}" width="90" height="26" rx="13" fill="#f1f3f4"/>')
    add("</g>")


def fold_screen(x, y, w, h, s=1.0):
    """Galaxy Z Fold7 inner screen, unfolded, schematic. s scales detail for thumbnails."""
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="url(#phonebg)"/>')
    add(f'<text x="{x + 30 * s}" y="{y + 34 * s}" font-size="{17 * s}" fill="#fff">11:17</text>')
    add(f'<rect x="{x + w - 70 * s}" y="{y + 20 * s}" width="{40 * s}" height="{16 * s}" rx="{4 * s}" fill="none" stroke="#fff" stroke-width="{1.5 * s}"/>')
    add(f'<rect x="{x + w - 67 * s}" y="{y + 23 * s}" width="{26 * s}" height="{10 * s}" rx="{2 * s}" fill="#fff"/>')
    add(f'<text x="{x + 46 * s}" y="{y + 150 * s}" font-size="{88 * s}" font-weight="200" fill="#fff">11:17</text>')
    add(f'<text x="{x + 50 * s}" y="{y + 190 * s}" font-size="{20 * s}" fill="#cfe3ff">Friday, November 20 · 59°F</text>')
    cols, icon = 6, 84 * s
    step = (w - 2 * 48 * s - icon) / (cols - 1)
    colors = ["#ff7a59", "#ffc145", "#5ad19a", "#4db5ff", "#a78bfa", "#f472b6", "#34d399", "#60a5fa", "#fbbf24", "#f87171"]
    for r in range(4):
        for c in range(cols):
            ix, iy = x + 48 * s + c * step, y + 290 * s + r * 126 * s
            add(f'<rect x="{ix:.1f}" y="{iy:.1f}" width="{icon:.1f}" height="{icon:.1f}" rx="{22 * s:.1f}" fill="{colors[(r * 6 + c) % 10]}" opacity="0.92"/>')
            add(f'<rect x="{ix + 10 * s:.1f}" y="{iy + icon + 12 * s:.1f}" width="{icon - 20 * s:.1f}" height="{8 * s:.1f}" rx="{4 * s:.1f}" fill="#ffffff" opacity="0.55"/>')
    add(f'<rect x="{x + 36 * s}" y="{y + h - 150 * s}" width="{w - 72 * s}" height="{110 * s}" rx="{36 * s}" fill="#ffffff" opacity="0.14"/>')
    for c in range(cols):
        ix = x + 48 * s + c * step
        add(f'<rect x="{ix:.1f}" y="{y + h - 137 * s:.1f}" width="{icon:.1f}" height="{icon:.1f}" rx="{22 * s:.1f}" fill="{colors[(c + 4) % 10]}"/>')
    add(f'<rect x="{x + w / 2 - 60 * s}" y="{y + h - 18 * s}" width="{120 * s}" height="{5 * s}" rx="{2.5 * s}" fill="#fff" opacity="0.8"/>')


def phone_screen(x, y, w, h, s=1.0):
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="url(#phonebg)"/>')
    add(f'<text x="{x + w / 2}" y="{y + h * 0.22}" font-size="{60 * s}" font-weight="200" fill="#fff" text-anchor="middle">11:17</text>')
    for r in range(5):
        for c in range(4):
            add(f'<rect x="{x + w * (0.1 + c * 0.215):.1f}" y="{y + h * (0.36 + r * 0.1):.1f}" width="{w * 0.16:.1f}" height="{w * 0.16:.1f}" rx="{w * 0.045:.1f}" fill="#ffffff" opacity="0.5"/>')


def dim_h(x1, x2, y, label, sub=None, above=True):
    add(f'<g stroke="{PINK}" stroke-width="2" fill="none"><line x1="{x1}" y1="{y}" x2="{x2}" y2="{y}"/>'
        f'<line x1="{x1}" y1="{y - 9}" x2="{x1}" y2="{y + 9}"/><line x1="{x2}" y1="{y - 9}" x2="{x2}" y2="{y + 9}"/></g>')
    ty = y - 12 if above else y + 28
    add(f'<text x="{(x1 + x2) / 2}" y="{ty}" font-size="21" font-weight="600" fill="{PINK}" text-anchor="middle">{label}</text>')
    if sub:
        add(f'<text x="{(x1 + x2) / 2}" y="{ty + (22 if not above else -24)}" font-size="16" fill="{PINK}" text-anchor="middle">{sub}</text>')


def dim_v(x, y1, y2, label, left=True):
    add(f'<g stroke="{PINK}" stroke-width="2" fill="none"><line x1="{x}" y1="{y1}" x2="{x}" y2="{y2}"/>'
        f'<line x1="{x - 9}" y1="{y1}" x2="{x + 9}" y2="{y1}"/><line x1="{x - 9}" y1="{y2}" x2="{x + 9}" y2="{y2}"/></g>')
    tx = x - 12 if left else x + 12
    add(f'<text x="{tx}" y="{(y1 + y2) / 2}" font-size="21" font-weight="600" fill="{PINK}" text-anchor="middle" '
        f'transform="rotate(-90 {tx} {(y1 + y2) / 2})">{label}</text>')


def panel_frame(x, y, w, h, r=12):
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="none" stroke="rgba(255,255,255,0.18)" stroke-width="1"/>')


def desktop(ox, oy, s, panels, detail=True):
    """Desktop 2 at offset (ox, oy) and scale s. panels: [("mac"|"fold"|"foldc"|"pixel", (x,y,w,h))]."""
    add(f'<g transform="translate({ox} {oy}) scale({s})" font-family="{FONT}">')
    add('<use href="#bgimg"/>')
    menu_bar(0, 0, W, MENU, ["", "Finder", "File", "Edit", "View", "Go", "Window", "Help"], "Fri Nov 20  11:17 AM", 14, "rgba(10,25,45,0.35)")
    labels = {"mac": "Agents' Mac · DeskPad Display", "fold": "Galaxy Z Fold7", "foldc": "Galaxy Z Fold7 (folded)", "pixel": "Pixel 10 Pro"}
    for kind, (x, y, w, h) in panels:
        cid = f"clip{len(svg)}"
        add(f'<clipPath id="{cid}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12"/></clipPath>')
        add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="#000" filter="url(#shadow)"/>')
        add(f'<g clip-path="url(#{cid})">')
        if kind == "mac":
            k = w / 1536
            add(f'<g transform="translate({x} {y}) scale({k})">')
            add('<use href="#innerimg"/>')
            menu_bar(0, 0, 1536, 30, ["", "Chrome", "File", "Edit", "View", "History", "Bookmarks", "Profiles", "Tab", "Window", "Help"], "Fri Nov 20  11:17 AM")
            if detail:
                chrome_window(0, 30, 1536, 930)
            else:
                add('<rect x="0" y="30" width="1536" height="930" fill="#fff"/><rect x="0" y="30" width="1536" height="40" fill="#f6d36b"/>')
            add("</g>")
        elif kind == "fold":
            fold_screen(x, y, w, h, h / 960)
        else:
            phone_screen(x, y, w, h, h / 960)
        add("</g>")
        panel_frame(x, y, w, h)
        add(f'<text x="{x + w / 2}" y="{y + h + 34}" font-size="17" font-weight="500" fill="#fff" fill-opacity="0.78" text-anchor="middle">{labels[kind]}</text>')
    add("</g>")


main = layout([MAC_ASPECT, FOLD_OPEN])
LEG_Y, TOTAL_H = H_DESK, 2240
add(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {TOTAL_H}" width="{W // 2}" height="{TOTAL_H // 2}">')
add('<title>Desktop 2 layout mockup</title>')
add(f'<defs><filter id="shadow" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="14" stdDeviation="20" flood-color="#000814" flood-opacity="0.55"/></filter>'
    '<linearGradient id="phonebg" x1="0" y1="0" x2="0.4" y2="1"><stop offset="0" stop-color="#0b1f3a"/><stop offset="0.55" stop-color="#16406b"/><stop offset="1" stop-color="#0a2a3f"/></linearGradient>'
    '<clipPath id="chromeclip"><rect x="0" y="30" width="1536" height="930"/></clipPath>'
    f'<image id="bgimg" href="{BG}" x="0" y="0" width="{W}" height="{H_DESK}" preserveAspectRatio="xMidYMid slice"/>'
    f'<image id="innerimg" href="{INNER}" x="0" y="0" width="1536" height="960" preserveAspectRatio="xMidYMid slice"/></defs>')
desktop(0, 0, 1, [("mac", main[0]), ("fold", main[1])])

# Measurements (not drawn by DeskPad).
(ax, ay, aw, ah), (bx, by, bw, bh) = main
add(f'<g font-family="{FONT}">')
dim_h(ax, ax + aw, ay - 22, f"{aw} pt", f"virtual display {aw} × {ah} pt at 2x = {aw * 2} × {ah * 2} px, shown 1:1")
dim_h(bx, bx + bw, by - 22, f"{bw} pt", "Fold 1968 × 2184 px at 88%")
dim_v(ax - 24, ay, ay + ah, f"{ah} pt")
dim_v(bx + bw + 30, by, by + bh, f"{bh} pt", left=False)
dim_h(ax + aw, bx, ay + ah / 2, f"{bx - ax - aw}")
dim_h(0, ax, ay + ah + 80, f"{ax}", above=False)
dim_h(bx + bw, W, by + bh + 80, f"{W - bx - bw}", above=False)
dim_v(bx - GAP / 2, MENU, ay, f"{ay - MENU}", left=False)
dim_v(bx - GAP / 2, ay + ah, H_DESK, f"{H_DESK - ay - ah}", left=False)
add("</g>")

# Animated cursor: crosses into the Mac panel, clicks, crosses the gap into the Fold, taps, leaves.
pts = [(24, 760), (24, 760), (300, 700), (640, 470), (640, 470), (1616, 600), (1990, 760), (1990, 760), (2120, 1330), (1300, 1352), (24, 760)]
kt = [0, 0.06, 0.18, 0.3, 0.4, 0.52, 0.64, 0.74, 0.86, 0.94, 1]
vals = ";".join(f"{x} {y}" for x, y in pts)
kts = ";".join(str(t) for t in kt)
for (cx, cy), t0 in [((640, 470), 0.33), ((1990, 760), 0.67)]:
    add(f'<circle cx="{cx}" cy="{cy}" r="0" fill="none" stroke="#ffffff" stroke-width="3"><animate attributeName="r" values="0;0;30;30" keyTimes="0;{t0};{t0 + 0.05};1" dur="12s" repeatCount="indefinite"/>'
        f'<animate attributeName="opacity" values="0;0;1;0;0" keyTimes="0;{t0};{t0 + 0.005};{t0 + 0.05};1" dur="12s" repeatCount="indefinite"/></circle>')
add(f'<g><animateTransform attributeName="transform" type="translate" values="{vals}" keyTimes="{kts}" dur="12s" repeatCount="indefinite"/>'
    '<path d="M0,0 L0,24 L6.5,18 L11,28 L14.5,26.5 L10,17 L18,17 Z" fill="#000" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></g>')

# Legend.
add(f'<rect x="0" y="{LEG_Y}" width="{W}" height="{TOTAL_H - LEG_Y}" fill="#f5f5f7"/>')
add(f'<g font-family="{FONT}" fill="#1d1d1f">')
add(f'<text x="60" y="{LEG_Y + 70}" font-size="34" font-weight="700">Desktop 2 layout, mockup: 1 unit = 1 pt (Desktop 2 is 2560 × 1440 pt, 5120 × 2880 px)</text>')
rules = [
    "Mac panel: the virtual DeskPad Display, 1536 × 960 pt at 2x (3072 × 1920 px), shown pixel for pixel. Agents' Chrome fills it below its menu bar.",
    "Device panels: one scrcpy mirror per Android device, as tall as the Mac panel, as wide as the screen's current shape (unfolded, folded, rotated).",
    "Spacing: 48 pt between panels, at least 52 pt at the sides, the row centred under the menu bar. A label sits 34 pt under each panel. Corners 12 pt.",
    "More devices than fit: the whole row scales down together. The Mac display stays 1536 × 960; its view scales.",
    "Cursor: crosses panel edges freely. Inside a panel the real cursor is on that screen and clicks act there; between panels it is on Desktop 2. Nothing takes focus by itself.",
    f'<tspan fill="{PINK}">Pink</tspan> marks measurements; DeskPad does not draw them.',
]
for i, r in enumerate(rules):
    add(f'<text x="60" y="{LEG_Y + 130 + i * 44}" font-size="25">• {r}</text>')
add(f'<text x="60" y="{LEG_Y + 420}" font-size="25" font-weight="700">Other cases (same rule, drawn at 1/5):</text>')
cases = [
    ("No devices", [MAC_ASPECT], ["mac"]),
    ("Fold 7 unfolded (above)", [MAC_ASPECT, FOLD_OPEN], ["mac", "fold"]),
    ("Fold 7 folded (cover screen 1080 × 2520)", [MAC_ASPECT, FOLD_CLOSED], ["mac", "foldc"]),
    ("Fold 7 unfolded + Pixel 10 Pro", [MAC_ASPECT, FOLD_OPEN, PIXEL], ["mac", "fold", "pixel"]),
]
s, tw, gap_t = 0.2, int(W * 0.2), 64
x0 = (W - (4 * tw + 3 * gap_t)) / 2
for i, (title, aspects, kinds) in enumerate(cases):
    rects = layout(aspects)
    ox, oy = x0 + i * (tw + gap_t), LEG_Y + 450
    desktop(ox, oy, s, list(zip(kinds, rects)), detail=False)
    mac_w = rects[0][2]
    note = "" if mac_w == 1536 else f" · Mac view at {mac_w / 1536:.0%}"
    add(f'<text x="{ox + tw / 2}" y="{oy + H_DESK * s + 36}" font-size="22" text-anchor="middle">{title}{note}</text>')
add("</g></svg>")
OUT.write_text("\n".join(svg))
print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB); main layout {main}")
for title, aspects, _ in cases:
    print(f"  {title}: {layout(aspects)}")
