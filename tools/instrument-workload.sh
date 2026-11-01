#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/tools
xcrun swiftc -O -g -target arm64-apple-macosx13.0 -parse-as-library -module-name MwitchPanelWorkload \
  Sources/mwitch/SwitcherPanel.swift Sources/mwitch/SwitcherPanelView.swift \
  Sources/mwitch/SwitcherWindowList.swift Sources/mwitch/SwitcherPanelModel.swift Sources/mwitch/SwitcherPanelDelegate.swift \
  Sources/mwitch/WindowEnumerator.swift Sources/mwitch/WindowSpaces.swift \
  Sources/mwitch/WindowAccessibility.swift Sources/mwitch/WindowActivator.swift \
  tools/InstrumentWorkload.swift -o build/tools/mwitch-panel-workload
APP="build/tools/MwitchPanelWorkload.app"
mkdir -p "$APP/Contents/MacOS"
cp build/tools/mwitch-panel-workload "$APP/Contents/MacOS/mwitch-panel-workload"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.mwitch.instrument-workload</string>
<key>CFBundleExecutable</key><string>mwitch-panel-workload</string>
<key>CFBundleName</key><string>Mwitch Panel Workload</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
cat > build/tools/profile.entitlements <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>
PLIST
SIGN_ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
codesign --force --sign "${SIGN_ID:--}" --entitlements build/tools/profile.entitlements "$APP"
echo "Built $APP (profiling only; never installed)"
echo "Launch executable: $APP/Contents/MacOS/mwitch-panel-workload"
echo "This shows a non-key synthetic panel for 12 seconds when launched."
