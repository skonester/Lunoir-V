import asyncio
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import win32api
import win32con
import win32event

from flet_lunoir.backend import ROOT, MpvController, MpvError


def alive(pid: int) -> bool:
    try:
        handle = win32api.OpenProcess(win32con.SYNCHRONIZE, False, pid)
    except win32api.error:
        return False
    try:
        return win32event.WaitForSingleObject(handle, 0) == win32event.WAIT_TIMEOUT
    finally:
        win32api.CloseHandle(handle)


class BackendTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.backend = MpvController(log_directory=Path(self.directory.name))
        await self.backend.start(extra_args=["--vo=null", "--ao=null"])

    async def asyncTearDown(self):
        await self.backend.close()

    async def event(self, kind, predicate=lambda event: True):
        async with asyncio.timeout(10):
            while True:
                event = await self.backend.events.get()
                if event.get("event") == kind and predicate(event):
                    return event

    async def test_v_binding_playback_and_property_events(self):
        await self.backend.command("loadfile", "av://lavfi:testsrc=duration=30:size=320x180:rate=24")
        await self.event("file-loaded")
        await self.backend.set("pause", True)
        await self.event("property-change", lambda e: e.get("name") == "pause" and e.get("data") is True)
        await self.backend.command("seek", 10, "absolute+exact")
        await self.event("playback-restart")
        position = await self.backend.command("get_property", "time-pos")
        self.assertAlmostEqual(position, 10, delta=0.1)
        await self.backend.set("volume", 73)
        self.assertEqual(await self.backend.command("get_property", "volume"), 73)
        self.assertEqual(await self.backend.command("get_property", "width"), 320)
        await self.backend.command("stop")

    async def test_concurrent_replies_and_errors(self):
        values = await asyncio.gather(*(
            self.backend.command("get_property", "mpv-version") for _ in range(20)
        ))
        self.assertTrue(all(value.startswith("mpv ") for value in values))
        with self.assertRaises(MpvError):
            await self.backend.command("get_property", "not-a-real-property")
        self.assertEqual(self.backend.pending, {})

    async def test_host_dies_with_a_killed_front_end(self):
        # a front end that dies without close() must not leave the host behind
        script = ("import asyncio, sys\n"
                  "from flet_lunoir.backend import MpvController\n"
                  "async def main():\n"
                  "    b = MpvController(log_directory=__import__('pathlib').Path(sys.argv[1]))\n"
                  "    await b.start(extra_args=['--vo=null', '--ao=null'])\n"
                  "    print(b.process.pid, flush=True)\n"
                  "    await asyncio.sleep(60)\n"
                  "asyncio.run(main())\n")
        # The base interpreter, not the venv's python.exe redirector: killing the
        # redirector would let its own cleanup end the host and hide a missing job.
        packages = next(p for p in sys.path if p.endswith("site-packages"))
        child = subprocess.Popen([getattr(sys, "_base_executable", sys.executable), "-c", script,
                                  self.directory.name], cwd=ROOT, stdout=subprocess.PIPE, text=True,
                                 env={**os.environ, "PYTHONPATH": os.pathsep.join([str(ROOT), packages])})
        try:
            host_pid = int(child.stdout.readline())
            self.assertTrue(alive(host_pid))
        finally:
            child.kill()
            child.wait()
        for _ in range(50):
            if not alive(host_pid):
                break
            await asyncio.sleep(0.1)
        survived = alive(host_pid)
        if survived:
            subprocess.run(["taskkill", "/F", "/PID", str(host_pid)], capture_output=True)
        self.assertFalse(survived)

    def test_host_without_work_exits(self):
        # like mpv.exe: no file, no IPC server, no --idle -> exit instead of idling invisibly
        result = subprocess.run([str(ROOT / "flet_lunoir/runtime/vmpv-host.exe")], timeout=10)
        self.assertEqual(result.returncode, 0)

    async def test_shutdown_releases_process_and_pipe(self):
        process = self.backend.process
        await self.backend.close()
        self.assertIsNotNone(process.poll())
        self.assertIsNone(self.backend.writer)
        self.assertIsNone(self.backend.reader_task)
        await self.backend.close()
