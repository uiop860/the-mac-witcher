# mwitch

A native macOS menu-bar window switcher for Apple Silicon Macs running macOS 13
or later.

## Install

With Xcode installed, run from this checkout:

```sh
./build.sh release
```

This builds the app, installs it in Applications, and starts it. Grant
Accessibility and Screen Recording permissions when prompted.

## Controls

- `Cmd+Tab`: open the switcher and move down.
- Press Shift while holding Cmd: move up.
- Up or Down: move selection.
- Release Cmd or press Enter: switch to the selected window.
- Esc: dismiss.
- Click a row: switch immediately.
- `Cmd+W` while the switcher is open: close the selected window.
- `Cmd+Q` while the switcher is open: quit the selected window's app.

Close and quit keep the switcher open and refresh the list. Releasing Cmd still
switches to the selection after refresh. Apps can still ask to save changes. Closing
requires an exact Accessibility match; if macOS cannot resolve the selected
window (for example on another Space), the app beeps and leaves it alone.

Hovering does not change selection. Typing does not search. Updates are installed
by rebuilding; there are no automatic update checks.

## Privacy

No telemetry, accounts, or network service. Accessibility raises or closes the selected
window; Screen Recording permission lets macOS provide other apps' window titles.
