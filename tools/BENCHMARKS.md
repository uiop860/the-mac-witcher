# Performance measurements

Run the installed release app, not a debug build. Results live under ignored
`build/benchmarks/`; commit the tools, not generated captures. No extra packages
or administrator access are needed for the benchmarks and process profiler.

## Repeatable code benchmarks

```sh
tools/benchmark.sh build/benchmarks/before
# Make one optimization, then:
tools/benchmark.sh build/benchmarks/after
```

XCTest measures elapsed time, CPU time, and memory for fixed workloads:
100,000 sessions of 100 selection moves with 100 windows; 1,000 recency sorts with
500 windows; and 1,000 enumeration-policy passes over 500 synthetic windows. A separate
panel benchmark submits 100 selections for a 100-window list and forces
AppKit subtree layout. Each update yields the run loop for approximately 1 ms
to deliver SwiftUI observations; elapsed time includes this pacing. This is an
offscreen panel update workload, not full
keyboard-to-visible-frame latency.
Inputs are prepared outside the measured block. The resulting selection/list
is consumed to keep the workload observable. XCTest repeats the block and
reports variation. Environment and test output are saved together.

The default suite skips these tests. Benchmarks deliberately have no fixed
performance thresholds until repeatable machine-specific baselines exist.
XCTest's memory metric describes its measured workload, not the installed
app's complete memory footprint. Synthetic enumeration excludes real AX/CG
IPC, icons, and WindowServer; it cannot predict end-to-end switching latency.

Optional live enumeration (at least one normal window must be open):

```sh
MWITCH_LIVE_BENCHMARKS=1 tools/benchmark.sh build/benchmarks/live
```

This requires Accessibility and Screen Recording for the test runner. It does
not request permissions automatically. Keep windows, Spaces, monitors and apps
identical across runs. This measures enumeration, not panel rendering or
activation. For full switch latency, use Instruments Time Profiler while
repeating the same Cmd+Tab sequence; inspect main-thread AX calls and rendering.

Validate the collector itself (Python 3 standard library only):

```sh
python3 tools/test_profile.py
```

These integration checks compile the native collector and exercise idle/busy
child processes, invalid inputs, process exit, and CSV/JSON consistency. They
do not control or modify the running app.

## Running-app CPU, memory, wakeups and I/O

```sh
tools/profile.sh --duration 60 --label idle --output build/benchmarks/idle
tools/profile.sh --duration 60 --label switching --output build/benchmarks/switching
```

The wrapper compiles an optimized Swift collector, then selects the single
running mwitch instance. Pass `--pid PID` to select explicitly. The default
interval is one second; `--interval 0.5` samples twice per second.

For idle runs, leave the switcher closed and avoid interacting with apps. For
switching runs, use the same windows and a fixed pace (for example, one
open/cycle/commit every two seconds). Include a separate cancel/click run if
optimizing those paths. Warm up the app first. Run each scenario three times
and compare medians. To look for retained memory, run for several minutes:
alternate a switching period with an idle period, and inspect whether footprint
keeps increasing instead of settling. Allocator caches can retain memory
without a leak; confirm suspicious growth with Instruments Allocations/Leaks.

JSON contains summary statistics and samples; CSV contains cumulative counters.
CPU percentage is computed from the kernel's CPU-time delta divided by elapsed
monotonic time: one logical core fully occupied equals 100%. Memory includes
resident size and physical footprint; reported peaks are sampled peaks.
Wakeups and disk I/O are counter deltas over the run. An exit/restart fails the
capture rather than silently switching to another process.

This collector excludes its own resource usage from app counters, but sampling
still has system overhead. It also excludes work mwitch causes in WindowServer
or other apps. JSON records battery status at both ends for context, not
per-app battery consumption.

## Energy and battery

Wakeups and CPU time help identify energy regressions, but neither is a
measurement in joules. For a detailed macOS energy capture, use Instruments'
available power/energy instruments, or run Apple's built-in tool separately:

```sh
sudo powermetrics --samplers tasks,cpu_power,battery \
  --show-process-energy --show-process-io --show-usage-summary \
  -i 1000 -n 60 -o build/benchmarks/energy.txt
```

This is optional and requires administrator access. Check
`powermetrics --help` for your macOS version. Process energy impact is an
estimate; CPU power is system-wide and must not be presented as mwitch watts.
Energy captures can include other process names, so inspect before sharing.

For actual battery impact, use paired runs on battery power for 30–60 minutes
or longer: mwitch quit versus running idle, then controlled switching sessions.
Repeat in alternating order. Keep brightness, power mode, network activity,
connected displays and workload fixed; disable unrelated background jobs where
practical. Record battery state and thermal conditions. The profiler can run
for the full duration, but percentage readings are coarse and cannot isolate
this app's contribution. If a difference is below normal run-to-run variation,
report it as inconclusive, not zero drain. Do not extrapolate a short capture
into hours of battery life.

## Xcode Instruments synthetic UI workload

Build a separate optimized profiling app from the production panel code:

```sh
tools/instrument-workload.sh
xcrun xctrace record --template 'Time Profiler' --time-limit 15s \
  --output build/benchmarks/panel-time.trace --launch -- \
  build/tools/MwitchPanelWorkload.app/Contents/MacOS/mwitch-panel-workload
```

It shows a non-key panel for 12 seconds with 100 fixture windows and never
activates other applications, installs global shortcuts, or changes login
settings. Only this isolated helper gets the debugging entitlement required
for memory profiling. It is not copied into Applications.

Use templates `Leaks` (includes Allocations), `SwiftUI`, or
`Animation Hitches` for separate captures. They introduce different overhead;
do not compare CPU or memory across template types. Check recording warnings
and whether the desired track actually has data before drawing conclusions.
The Power Profiler template in the tested Xcode version rejects macOS.

For a diagnostic-only scroll comparison, add `--env MWITCH_PROFILE_SCROLL=0`
before `--launch`. This skips selection-scroll requests, changes behavior,
and must not be presented as a production speedup. Exclude startup and use the
same template/workload for both sides.

Apple's supplementary heap scan:

```sh
MallocStackLogging=1 leaks --atExit -- \
  build/tools/MwitchPanelWorkload.app/Contents/MacOS/mwitch-panel-workload
```

A zero-leak result applies only to that exercised workload. Synthetic panel
captures omit real AX enumeration/activation, icon loading and focus observers.
