#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Select the app only when exactly one instance exists; --pid overrides this.
HAS_PID=0
for arg in "$@"; do
    [[ "$arg" != "--pid" ]] || HAS_PID=1
done
if [[ "$HAS_PID" == 0 ]]; then
    APP_PIDS="$(pgrep -x mwitch || true)"
    if [[ -z "$APP_PIDS" || "$APP_PIDS" == *$'\n'* ]]; then
        echo "error: launch one mwitch instance, or supply --pid PID." >&2
        exit 1
    fi
    set -- --pid "$APP_PIDS" "$@"
fi
mkdir -p build/tools
xcrun swiftc -O tools/Profile.swift -o build/tools/mwitch-profile
exec build/tools/mwitch-profile "$@"
