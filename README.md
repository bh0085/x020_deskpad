# x020 — DeskPad (fork)

A virtual monitor for agents on base-mac. Claude Code agents do their GUI work on it; Ben watches and steps in from Desktop 2. Forked from [Stengo/DeskPad](https://github.com/Stengo/DeskPad) (MIT), which creates the display with the private `CGVirtualDisplay` API.

## What it does

Desktop 2 shows a row of live screens, laid out as in [docs/desktop2-layout.svg](docs/desktop2-layout.svg): the agents' Mac screen, then one panel per Android device.

- **Mac display.** "DeskPad Display", 1536 × 960 pt at 2x (3072 × 1920 px). Its panel shows it pixel for pixel. The display touches the Studio Display only at its bottom-right corner (origin 2560,1440), so Ben's cursor never drifts onto it by itself. The Chrome window named "Claude agents" fills it below its menu bar.
- **Android devices.** Every device adb sees (USB or Wi-Fi debugging) gets a borderless [scrcpy](https://github.com/Genymobile/scrcpy) window on a second virtual display, "DeskPad Mirrors" (2400 × 1100 pt at 2x, at the Mac display's bottom-right corner), and a panel on Desktop 2 that shows that window 1:1. Panels appear and disappear with the devices and reshape when a phone rotates or folds. scrcpy never takes focus when it starts and doesn't wake a sleeping phone. A device on USB and Wi-Fi at once gets one panel (USB preferred); pull the cable and the panel switches to Wi-Fi. Every 10 s DeskPad looks up phones advertising wireless debugging (`adb mdns services`) and connects to those that have approved this Mac before (remembered in the `approvedAndroidDevices` setting); the USB approval covers Wi-Fi, so no pairing is needed. Phones that never approved this Mac are left alone, since connecting would put an "Allow debugging?" prompt on their screen. The label is the name set on the phone. Toggle with the menu-bar item.
- **Sleeping phones.** DeskPad reads each phone's screen state every 2 s. A sleeping phone's label says "asleep, click to wake", and any click on its panel wakes it (`KEYCODE_WAKEUP` over adb; scrcpy's touches can't wake a phone). A phone set to "Minimize to the corner when asleep" (menu bar, per phone; on for the Pixel 10 Pro) shrinks to a small card in the bottom-right corner while its screen is off; clicking the card wakes it and its panel rejoins the row.
- **Dropouts.** A phone that drops off adb (cable pulled, new Wi-Fi port) keeps its panel for 90 s with a "Reconnecting…" overlay, so the row doesn't jump; it comes back on whichever link answers first.
- **Layout.** All panels share one height, each as wide as its screen needs, 48 pt apart, at least 52 pt from the sides, centred under the menu bar, with a label under each. The row is 960 pt tall unless it would be too wide; then it scales down together (the Mac display keeps its size; its panel shows it scaled).
- **Cursor.** The cursor crosses panel edges as if the panels were real screens. Inside a panel it is on that screen (the Mac display, or the phone's mirror) and every click, drag and scroll acts there; leaving the screen, or pushing against an edge it can't cross, brings it back to Desktop 2 just outside the panel. It never moves while a mouse button is down. Leaving Desktop 2 brings it back first. No synthetic events.
- **Panels.** Borderless ScreenCaptureKit views (60 fps), only on Desktop 2, never taking focus. Capture restarts by itself after sleep.
- **Chrome guard.** Chrome opens new windows next to its most recently active window, restores windows where they were, and when it comes to the front (Dock, Spotlight, Launchpad, Cmd-Tab, a link) it focuses its most recent window; with the agent window on a virtual display, all of that can happen out of Ben's sight, and his typing would land in the agents' tabs. DeskPad moves any Chrome window other than "Claude agents" to the main display, and when Chrome comes forward with no window on Ben's screen it restores a minimized window, moves a link's new tab out of the agent window into its own window, or opens a new window. At quit it minimizes the agent window so it doesn't land on Ben's screen; the next start puts it back.
- **Menu bar.** Shows the display size, the connected Android devices, and toggles for Android panels and the Chrome guard.

What changed from upstream: upstream's resizable window (shown on every desktop, it brought itself to the front whenever the cursor reached the display) is replaced by the Desktop 2 panels; the mode list is replaced by one 2x mode; ReSwift and the Xcode project are replaced by plain AppKit and `build.sh`; the app runs without a Dock icon.

## Build and run

Requires Xcode command-line tools, and for Android, `brew install scrcpy android-platform-tools`.

```bash
./build.sh            # build, sign with the Apple Development certificate, install to ~/Applications/DeskPad.app
./run.sh start        # also: stop, restart, status, log [n]
```

Start it from a shell that already holds Screen Recording and Accessibility (Claude Code's Bash on base-mac does). DeskPad inherits both, so macOS asks for nothing. Opened from Finder it would need its own grants. It does not start at login.

Log: `~/Library/Logs/DeskPad/deskpad.log`; one scrcpy log per device next to it. Set `DESKPAD_DEBUG=1` to log every cursor crossing.

## Settings

`defaults write com.bh0085.deskpad <key> <value>`, then `./run.sh restart`:

| key | default | meaning |
|---|---|---|
| `desktopUUID` | Desktop 2 on base-mac | desktop the view lives on (uuid from `com.apple.spaces`) |
| `macWidth`, `macHeight` | 1536, 960 | size of the agents' Mac display, in points |
| `wallpaper` | `~/Pictures/Undersea-Wallpapers/deskpad-inner.png` | wallpaper of the virtual display |
| `showAndroid` | true | Android mirrors (also in the menu) |
| `chromeGuard` | true | keep Ben's Chrome windows off the display (also in the menu) |

## For agents

- Find the display by its name, "DeskPad Display", or by origin 2560,1440. Leave "DeskPad Mirrors" alone: DeskPad places the scrcpy windows there.
- Work in the Chrome window named "Claude agents" (`~/.claude/tools/chromewin.sh deskpad` returns its id). Don't open other Chrome windows on the display; the guard moves them to Ben's screen.
- Test hooks (distributed notifications): `com.bh0085.deskpad.chromeDockCheck` runs the "Chrome came forward" check; `com.bh0085.deskpad.chromeSweep` logs what the Chrome guard sees and sweeps.
- `docs/mockup/make_mockup.py` regenerates the layout drawing.

## Credits

Upstream DeskPad by Bastian Andelefski (MIT, see LICENSE.md). `CGVirtualDisplayPrivate.h` by Khaos Tian. Android mirroring by scrcpy (Apache-2.0), run as a separate program.
