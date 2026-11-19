# x020 — DeskPad (fork)

A virtual monitor for agents on base-mac. Claude Code agents do their GUI work on it; Ben watches and steps in from Desktop 2. Forked from [Stengo/DeskPad](https://github.com/Stengo/DeskPad) (MIT), which creates the display with the private `CGVirtualDisplay` API.

## What it does

- **Display.** Creates "DeskPad Display" with exactly the size of the view in points (2480 × 1330 on the Studio Display) at 2x, so the view on Desktop 2 is pixel for pixel as sharp as the Studio Display. The display touches the Studio Display only at its bottom-right corner (origin 2560,1440), so Ben's cursor never drifts onto it.
- **View.** A borderless live view (ScreenCaptureKit, 60 fps) on Desktop 2 only. A click or scroll on it moves Ben's real cursor to the same spot on the display (that first click only steps in); after that all input is native. Pushing past an edge, or leaving Desktop 2, brings the cursor back out. It never takes focus and never shows on Desktop 1.
- **Layout.** Android mirrors sit in a row on the right of the display, all the same height and each as wide as its screen needs. The agent zone takes the rest. The Chrome window named "Claude agents" fills the agent zone.
- **Android.** Every device adb sees (USB or Wi-Fi debugging) gets a borderless [scrcpy](https://github.com/Genymobile/scrcpy) mirror in the row. Mirrors appear and disappear with the devices and reflow when a phone rotates. scrcpy never takes focus when it starts, and a click on a mirror reaches the phone. A device on USB and Wi-Fi at once gets one mirror (USB preferred). Toggle with the menu-bar item.
- **Chrome guard.** Chrome opens new windows next to its most recently active window, restores windows where they were, and on a Dock click shows its existing windows; with the agent window on DeskPad, all three can happen out of Ben's sight. DeskPad moves any Chrome window other than "Claude agents" to the centre of the main display, and a Dock click on Chrome when every Chrome window is on DeskPad opens a window on the main display. At quit it minimizes the agent window so it doesn't land on Ben's screen; the next start puts it back.
- **Menu bar.** Shows the display size, the connected Android devices, and toggles for Android mirrors and the Chrome guard.

What changed from upstream: upstream's resizable window (shown on every desktop, it brought itself to the front whenever the cursor reached the display) is replaced by the Desktop 2 view; the mode list is replaced by one 2x mode sized to the view; ReSwift and the Xcode project are replaced by plain AppKit and `build.sh`; the app runs without a Dock icon.

## Build and run

Requires Xcode command-line tools, and for Android, `brew install scrcpy android-platform-tools`.

```bash
./build.sh            # build, sign with the Apple Development certificate, install to ~/Applications/DeskPad.app
./run.sh start        # also: stop, restart, status, log [n]
```

Start it from a shell that already holds Screen Recording and Accessibility (Claude Code's Bash on base-mac does). DeskPad inherits both, so macOS asks for nothing. Opened from Finder it would need its own grants. It does not start at login.

Log: `~/Library/Logs/DeskPad/deskpad.log`; one scrcpy log per device next to it. Set `DESKPAD_DEBUG=1` to log the view's step-in and step-out.

## Settings

`defaults write com.bh0085.deskpad <key> <value>`, then `./run.sh restart`:

| key | default | meaning |
|---|---|---|
| `desktopUUID` | Desktop 2 on base-mac | desktop the view lives on (uuid from `com.apple.spaces`) |
| `margin` | 40 | points between the view and the edges of that desktop |
| `wallpaper` | `~/Pictures/Undersea-Wallpapers/deskpad-inner.png` | wallpaper of the virtual display |
| `showAndroid` | true | Android mirrors (also in the menu) |
| `chromeGuard` | true | keep Ben's Chrome windows off the display (also in the menu) |

## For agents

- Find the display by its name, "DeskPad Display", or by origin: x ≥ 2560.
- Work in the Chrome window named "Claude agents" (`~/.claude/tools/chromewin.sh deskpad` returns its id). Don't open other Chrome windows on the display; the guard moves them to Ben's screen.
- Test hook for the Dock-click check: post the distributed notification `com.bh0085.deskpad.chromeDockCheck`.

## Credits

Upstream DeskPad by Bastian Andelefski (MIT, see LICENSE.md). `CGVirtualDisplayPrivate.h` by Khaos Tian. Android mirroring by scrcpy (Apache-2.0), run as a separate program.
