#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUTPUT="${1:-build/benchmarks/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUTPUT"
{
    date -u
    git rev-parse HEAD
    git status --short
    sw_vers
    sysctl -n hw.model
    xcrun swift --version
} > "$OUTPUT/environment.txt"
MWITCH_BENCHMARKS=1 swift test -c release --filter PerformanceTests 2>&1 | tee "$OUTPUT/tests.log"
echo "Benchmark results: $OUTPUT"
