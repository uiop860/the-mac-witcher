#!/usr/bin/env python3
"""Integration checks for the native process collector; no app permissions needed."""
import csv
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "build/tools/mwitch-profile"


class ProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BINARY.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["xcrun", "swiftc", "-O", str(ROOT / "tools/Profile.swift"), "-o", str(BINARY)],
            check=True,
        )

    def run_profile(self, *args):
        return subprocess.run([str(BINARY), *args], capture_output=True, text=True)

    def test_rejects_invalid_arguments(self):
        for args in [
            ["--pid", "1", "--duration", "nan"],
            ["--pid", "0"],
            ["--pid", "1", "--interval", "0"],
            ["--pid", "1", "--duration", "1", "--interval", "2"],
            ["--pid", "1", "--unknown", "value"],
        ]:
            with self.subTest(args=args):
                self.assertEqual(self.run_profile(*args).returncode, 2)

    def test_missing_process_fails_cleanly(self):
        result = self.run_profile("--pid", "2147483647", "--duration", "1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Cannot sample", result.stderr)

    def test_report_and_csv_agree(self):
        child = subprocess.Popen(["/bin/sleep", "30"])
        try:
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "capture"
                result = self.run_profile(
                    "--pid", str(child.pid), "--duration", "0.3",
                    "--interval", "0.1", "--output", str(output),
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                report = json.loads(output.with_suffix(".json").read_text())
                with output.with_suffix(".csv").open() as handle:
                    rows = list(csv.DictReader(handle))
                self.assertEqual(len(rows), report["sampleCount"])
                self.assertGreaterEqual(len(rows), 4)
                self.assertGreaterEqual(report["durationSeconds"], 0.3)
                self.assertGreater(report["initialFootprintBytes"], 0)
                self.assertGreaterEqual(
                    report["peakSampledFootprintBytes"], report["initialFootprintBytes"]
                )
                self.assertGreaterEqual(report["cpuSeconds"], 0)
                self.assertAlmostEqual(
                    report["averageCPUPercentOneCore"],
                    report["cpuSeconds"] / report["durationSeconds"] * 100,
                )
                for key in [
                    "elapsed_seconds", "cpu_seconds_cumulative",
                    "package_idle_wakeups_cumulative", "disk_write_bytes_cumulative",
                ]:
                    values = [float(row[key]) for row in rows]
                    self.assertEqual(values, sorted(values), key)
        finally:
            child.terminate()
            child.wait()

    def test_busy_process_records_cpu_time(self):
        child = subprocess.Popen(["/usr/bin/yes"], stdout=subprocess.DEVNULL)
        try:
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "busy"
                result = self.run_profile(
                    "--pid", str(child.pid), "--duration", "0.3",
                    "--interval", "0.1", "--output", str(output),
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                report = json.loads(output.with_suffix(".json").read_text())
                self.assertGreater(report["cpuSeconds"], 0)
                self.assertGreater(report["averageCPUPercentOneCore"], 0)
        finally:
            child.terminate()
            child.wait()

    def test_exited_process_is_not_reported_as_idle(self):
        # Leave the child unreaped so this also covers zombie process counters.
        child = subprocess.Popen(["/bin/sleep", "0.5"])
        try:
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "capture"
                result = self.run_profile(
                    "--pid", str(child.pid), "--duration", "1.5",
                    "--interval", "0.1", "--output", str(output),
                )
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertFalse(output.with_suffix(".json").exists())
        finally:
            child.wait()


if __name__ == "__main__":
    unittest.main()
