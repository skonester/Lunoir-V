"""Development-only tests of the V executable; Python is never its runtime controller.

Run after build-native.ps1. --exe can select a portable copy outside the checkout.
The media generator uses the repository's existing V/mpv binding.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
PARSER = argparse.ArgumentParser()
PARSER.add_argument("--exe", type=Path, default=ROOT / "Lunoir-V.exe")
PARSER.add_argument("--artifacts", type=Path, help="Keep rendered snapshots and state JSON for inspection")
OPTIONS, TEST_ARGS = PARSER.parse_known_args()
EXE = OPTIONS.exe.resolve()
KERNEL = ctypes.windll.kernel32
KERNEL.OpenProcess.restype = ctypes.c_void_p
KERNEL.OpenProcess.argtypes = (ctypes.c_ulong, ctypes.c_bool, ctypes.c_ulong)
KERNEL.WaitForSingleObject.argtypes = (ctypes.c_void_p, ctypes.c_ulong)
KERNEL.CloseHandle.argtypes = (ctypes.c_void_p,)
KERNEL.TerminateProcess.argtypes = (ctypes.c_void_p, ctypes.c_uint)


def running(pid: int) -> bool:
    handle = KERNEL.OpenProcess(0x100000, False, pid)
    if not handle:
        return False
    try:
        return KERNEL.WaitForSingleObject(handle, 0) == 258
    finally:
        KERNEL.CloseHandle(handle)


def until(condition, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for the native player")


class NativePlayer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not EXE.is_file():
            raise unittest.SkipTest("Build Lunoir-V.exe with build-native.ps1 first")
        cls.fixture_folder = tempfile.TemporaryDirectory(prefix="lunoir-native-fixtures-")
        cls.fixture = Path(cls.fixture_folder.name)
        env = dict(os.environ, V_C_ERROR_BUG_REPORT_DISABLED="1")
        env["PATH"] = str(ROOT) + os.pathsep + env["PATH"]
        generator = cls.fixture / "test_media.exe"
        build = subprocess.run(["v", "-cc", "gcc", "-no-retry-compilation", "-subsystem", "console",
                                "-o", str(generator), str(ROOT / "tools/test_media")],
                               cwd=ROOT, env=env, capture_output=True, timeout=60)
        if build.returncode:
            raise AssertionError(build.stdout.decode(errors="replace") + build.stderr.decode(errors="replace"))
        cls.clip = cls.fixture / "clip.mkv"
        cls.audio = cls.fixture / "tone.wav"
        for path in (cls.clip, cls.audio):
            subprocess.run([str(generator), str(path)], env=env, check=True,
                           capture_output=True, timeout=40, creationflags=subprocess.CREATE_NO_WINDOW)

    @classmethod
    def tearDownClass(cls):
        cls.fixture_folder.cleanup()

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="lunoir-native-ui-")
        self.addCleanup(self.folder.cleanup)
        self.scratch = Path(self.folder.name)
        self.profile = self.scratch / "Lunoir V"
        self.profile.mkdir()
        self.env = dict(os.environ, APPDATA=str(self.scratch), LOCALAPPDATA=str(self.scratch),
                        LUNOIR_V_EXIT_AFTER="20")
        # Only the standard Windows executables are visible to the packaged application.
        self.env["PATH"] = str(Path(os.environ["SystemRoot"]) / "System32")
        self.env.pop("PYTHONPATH", None)
        self.env.pop("LUNOIR_V_TRACE", None)
        self.settings = {"rememberWindow": False, "screenshotDir": str(self.scratch / "shots")}
        self.write_settings()
        self.processes = []
        self.logs = []
        self.addCleanup(self.cleanup_processes)

    def write_settings(self):
        (self.profile / "settings.json").write_text(json.dumps(self.settings), encoding="utf-8")

    def tearDown(self):
        if OPTIONS.artifacts:
            destination = OPTIONS.artifacts.resolve() / self._testMethodName
            destination.mkdir(parents=True, exist_ok=True)
            for path in self.scratch.glob("*.json"):
                shutil.copy2(path, destination / path.name)
            snapshots = self.scratch / "snapshots"
            if snapshots.is_dir():
                shutil.copytree(snapshots, destination / "snapshots", dirs_exist_ok=True)

    def cleanup_processes(self):
        for process in self.processes:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=10)
        for log in self.logs:
            log.close()

    def launch(self, steps, targets=(), seconds=20, screenshots=False):
        script = self.scratch / f"steps-{len(self.processes)}.json"
        script.write_text(json.dumps(steps), encoding="utf-8")
        env = dict(self.env, LUNOIR_V_TEST_SCRIPT=str(script), LUNOIR_V_EXIT_AFTER=str(seconds))
        if screenshots:
            env.update(LUNOIR_V_SNAPSHOTS=str(self.scratch / "snapshots"),
                       LUNOIR_V_SNAPSHOT_INTERVAL="1000")
        log = (self.scratch / f"controller-{len(self.processes)}.log").open("wb")
        self.logs.append(log)
        process = subprocess.Popen([str(EXE), *map(str, targets)], cwd=self.scratch, env=env,
                                   stdout=log, stderr=log, creationflags=subprocess.CREATE_NO_WINDOW)
        self.processes.append(process)
        return process

    def state(self, name):
        return json.loads((self.scratch / name).read_text(encoding="utf-8"))

    def test_playback_ui_second_launch_and_profile(self):
        clip = self.scratch / "clip.mkv"
        second = self.scratch / "second.mkv"
        shutil.copyfile(self.clip, clip)
        shutil.copyfile(self.clip, second)
        subtitle = self.scratch / "English.srt"
        subtitle.write_text("1\n00:00:00,000 --> 00:00:35,000\nNative V subtitle\n", encoding="utf-8")
        for name, value in {
            "positions.json": {str(clip): 9},
            "audio-selections.json": {str(clip): {"type": "external", "path": str(self.audio)}},
            "subtitle-selections.json": {str(clip): {"type": "external", "path": str(subtitle),
                                                    "externalPaths": [str(subtitle)]}},
        }.items():
            (self.profile / name).write_text(json.dumps(value), encoding="utf-8")
        steps = [
            {"at": 1500, "action": "command", "args": ["set_property", "pause", True]},
            {"at": 1800, "action": "volume_start"},
            {"at": 1900, "action": "volume_change", "data": 37},
            {"at": 2000, "action": "volume_end", "data": 37},
            {"at": 2500, "action": "snapshot_state", "state": str(self.scratch / "first.json")},
            {"at": 3000, "action": "toggle_panel", "args": ["tracks"]},
            {"at": 5000, "action": "toggle_panel", "args": ["playlist"]},
            {"at": 6500, "action": "toggle_panel", "args": ["menu"]},
            {"at": 8000, "action": "toggle_panel", "args": ["info"]},
            {"at": 9500, "action": "toggle_panel", "args": ["library"]},
            {"at": 11000, "action": "toggle_panel", "args": ["settings"]},
            {"at": 12000, "action": "settings_tab", "args": ["interface"]},
            {"at": 13000, "action": "setting_select", "args": ["uiLanguage"], "data": "de"},
            {"at": 14000, "action": "command", "args": ["seek", 12, "absolute"]},
            {"at": 14200, "action": "command", "args": ["set_property", "pause", True]},
            {"at": 15000, "action": "screenshot"},
            {"at": 16000, "action": "open_url"},
            {"at": 17000, "action": "dialog_close"},
            {"at": 18000, "action": "snapshot_state", "state": str(self.scratch / "last.json")},
        ]
        process = self.launch(steps, [clip], seconds=20, screenshots=True)
        until(lambda: (self.scratch / "first.json").exists())
        first = self.state("first.json")
        self.assertEqual(first["volume"], 37)
        self.assertTrue(first["pause"])
        self.assertGreater(first["time-pos"], 8)
        self.assertTrue(first["_thumb_ready"])
        tracks = first["track-list"]
        self.assertTrue(any(t.get("type") == "audio" and t.get("external") for t in tracks))
        self.assertTrue(any(t.get("type") == "sub" and t.get("external") and t.get("selected") for t in tracks))
        forwarded = subprocess.run([str(EXE), "second.mkv"], cwd=self.scratch,
                                   env=self.env, capture_output=True, timeout=15,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        self.assertEqual(forwarded.returncode, 0)
        self.assertEqual(process.wait(timeout=30), 0)
        last = self.state("last.json")
        self.assertEqual(Path(last["path"]), second)
        self.assertEqual(last["_language"], "de")
        self.assertFalse(last["_dialog_open"])
        self.assertEqual(last["_dialog_controls"], 0)
        self.assertTrue(last["pause"])
        self.assertAlmostEqual(last["time-pos"], 12, delta=1)
        self.assertEqual(first["_controller_pid"], last["_controller_pid"])
        self.assertFalse(running(last["_flet_pid"]))
        self.assertTrue(list((self.scratch / "shots").glob("*.png")))
        saved = json.loads((self.profile / "settings.json").read_text(encoding="utf-8"))
        self.assertEqual(saved["uiLanguage"], "de")
        self.assertEqual(saved["volume"], 37)
        self.assertGreater(len(list((self.scratch / "snapshots").glob("*.png"))), 10)
        # A missing Flet control renders an almost empty red error page. The shell
        # schema itself is also checked across all locales by port_test.v.
        self.assertTrue(all(p.stat().st_size > 10000 for p in (self.scratch / "snapshots").glob("*.png")))

    def test_killing_v_controller_also_closes_flet(self):
        state = self.scratch / "alive.json"
        process = self.launch([{"at": 1000, "action": "snapshot_state", "state": str(state)}], seconds=45)
        until(state.exists)
        flet_pid = self.state("alive.json")["_flet_pid"]
        self.assertTrue(running(flet_pid))
        process.kill()
        process.wait(timeout=10)
        until(lambda: not running(flet_pid), timeout=5)

    def test_killing_flet_closes_v_controller(self):
        state = self.scratch / "alive.json"
        process = self.launch([{"at": 1000, "action": "snapshot_state", "state": str(state)}], seconds=45)
        until(state.exists)
        flet_pid = self.state("alive.json")["_flet_pid"]
        handle = KERNEL.OpenProcess(1, False, flet_pid)
        self.assertTrue(handle)
        KERNEL.TerminateProcess(handle, 1)
        KERNEL.CloseHandle(handle)
        self.assertEqual(process.wait(timeout=10), 0)


if __name__ == "__main__":
    unittest.main(argv=[__file__, *TEST_ARGS])
