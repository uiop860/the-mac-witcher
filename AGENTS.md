# AGENTS.md

This file is for coding agents working on mwitch. Keep `README.md` customer-facing and put developer, build, and implementation details here.

## Project Overview

mwitch is a native macOS menu-bar app written in Swift. It replaces the default `Cmd+Tab` flow with a per-window switcher.

Core files:

- `Sources/mwitch/AppDelegate.swift`: app startup, permissions prompts, menu bar item, launch at login.
- `Sources/mwitch/HotkeyManager.swift`: global `Cmd+Tab`, `Cmd+Shift`, Cmd-release commit, and Esc cancel handling.
- `Sources/mwitch/SwitcherController.swift`: switcher session state and commit/cancel behavior.
- `Sources/mwitch/SwitcherPanel.swift`: AppKit panel shell.
- `Sources/mwitch/SwitcherPanelView.swift`: SwiftUI material shell and native list bridge.
- `Sources/mwitch/SwitcherWindowList.swift`: reusable AppKit rows, selection, and minimal scrolling.
- `Sources/mwitch/SwitcherListState.swift`: window list and keyboard selection.
- `Sources/mwitch/WindowEnumerator.swift`: CoreGraphics window listing.
- `Sources/mwitch/WindowSpaces.swift`: Space membership lookup, used to tell real windows from native tab surfaces.
- `Sources/mwitch/WindowActivator.swift`: Accessibility window activation.
- `Sources/mwitch/WindowActions.swift`: exact-window close and graceful application quit.
- `Sources/mwitch/WindowAccessibility.swift`: shared per-message Accessibility timeout.

## Window Enumeration Notes

Apps that use native macOS window tabbing (Ghostty, Terminal) back every tab with
its own layer-0, titled CG window that Accessibility cannot resolve — exactly how
a real window parked on another Space looks. Frames do not separate them either:
background tabs sit on their window's frame give or take a pixel, and two real
windows are often sized identically. `WindowSpaces` queries WindowServer Space
membership as the structural discriminator: nonempty membership proves a real
window, while empty membership rejects inactive tabs only after minimized and
hidden-app windows are exempted. The private symbols are resolved dynamically;
an unavailable or failed query returns `nil` and fails open.

## Local Commands

Run tests:

```sh
swift test
```

Performance tools and measurement caveats are documented in `tools/BENCHMARKS.md`.
Run `tools/benchmark.sh` for opt-in release benchmarks, or
`tools/profile.sh --duration 60 --label idle` to sample the running app's CPU,
memory, wakeups, and I/O. Outputs stay under ignored `build/benchmarks/`.

Build a signed local release app:

```sh
./build.sh release
open /Applications/mwitch.app
```

Local builds automatically quit any running mwitch instance, copy the app to `/Applications/mwitch.app`, and launch the installed app. Set `MWITCH_INSTALL=0` to skip installation; CI also skips it. The build artifact remains at `build/mwitch.app`.

Validate build support files:

```sh
bash -n build.sh tools/*.sh
git diff --check
```

## Build and Versioning

- `VERSION` contains the app version; `MWITCH_VERSION` can override it.
- `build.sh` stamps the build number from the git commit count.
- The build uses a Developer ID or Apple Development signing identity when
  available, otherwise ad-hoc signing. A stable signing identity and installation
  path allow macOS privacy permissions to persist between rebuilds.
- `Resources/AppIcon.icns` is bundled in the app. Regenerate it with
  `tools/make_icons.sh`; intermediate icon sizes go under `build/`.
- The app has no updater or external package dependencies. Install updates by
  rebuilding.

## Repository Hygiene

- Keep this repository focused on the app, local building, tests and profiling.
- Keep the original license and attribution in `LICENSE`.
- Leave unrelated local files alone, especially untracked tool state such as
  `.rudder/`.
- Do not commit generated outputs under `build/` or `.build/`.
- Keep customer-facing documentation in `README.md` short and plain.
