# DisplayToggle

Status-bar app that turns the MacBook built-in display off and on **without closing the lid**.
Useful when docked to an external monitor and you want the laptop panel dark but the lid open
(keyboard, Touch ID, cooling).

## How it works

Uses the private CoreGraphics call `CGSConfigureDisplayEnabled` inside a
`CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration(.forSession)` transaction.
This is the same "disconnect display" mechanism used by Lunar and BetterDisplay. It is private
API: it can stop working after a macOS update.

## Build and run

```bash
make run
```

Produces `DisplayToggle.app` (menu-bar only, no Dock icon). Drag it into
System Settings → General → Login Items to start it at login.

## Usage

Click the laptop icon in the menu bar. A popover draws every display at its real position and
relative size, as arranged in System Settings → Displays. Each tile has a switch inside it:
flip it to disconnect or reconnect that display. A display that is off stays in place as a
dimmed, dashed tile so you can bring it back. The main display shows a menu-bar strip on top.
The menu-bar icon shows `laptopcomputer` when the panel is on and `laptopcomputer.slash` when off.

## Caveats

- Needs at least one other display connected. The app refuses to turn off the built-in panel if it
  is the only display, so you can't lock yourself out.
- The change is per-session: log out, reboot, sleep/wake or close-and-reopen the lid brings the
  panel back on its own. The menu label follows the real state.
- Every display's last known name and position is cached in UserDefaults, since a disconnected
  display disappears from the display list. If the built-in panel was already off when the app
  first launched, a placeholder tile is drawn under the main display until the panel is seen once.
- Externals can be switched off too, through the same call. An external that you unplug (rather
  than switch off) drops from the layout.
- Requires macOS 13+ (where the disconnect call works on Apple Silicon). Off and on both
  verified on macOS 27.0.1 (Swift 6.4) with two external displays attached.
