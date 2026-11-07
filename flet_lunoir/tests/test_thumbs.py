import asyncio
import os
import tempfile
import unittest
from unittest import mock

import win32con
import win32gui

from flet_lunoir import thumbs
from flet_lunoir.backend import MpvController
from flet_lunoir.thumbs import Thumbnails


class ThumbnailTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        patch = mock.patch.dict(os.environ, {"LOCALAPPDATA": folder.name})  # keep backend.log out of the real one
        patch.start()
        self.addCleanup(patch.stop)
        # a real file: lavfi sources cannot seek backwards. mpv's encoder makes it in under 1 s.
        self.clip = os.path.join(folder.name, "clip.mkv")
        encoder = MpvController()
        await encoder.start(extra_args=[f"--o={self.clip}", "--of=matroska", "--ovc=mjpeg",
                                        "--vo=null", "--ao=null", "--keep-open=no"], observe=False)
        await encoder.command("loadfile", "av://lavfi:testsrc=duration=60:size=160x120:rate=24")
        async with asyncio.timeout(30):
            while (await encoder.events.get()).get("event") != "end-file":
                pass
        await encoder.close()
        # a visible parent far off screen: the preview presents frames, but nothing flashes
        self.parent = win32gui.CreateWindowEx(
            win32con.WS_EX_TOOLWINDOW | win32con.WS_EX_NOACTIVATE, "STATIC", "thumb test",
            win32con.WS_POPUP | win32con.WS_VISIBLE, -4000, -4000, 800, 450, 0, 0, 0, None)
        self.thumbs = Thumbnails(self.parent)

    async def asyncTearDown(self):
        await self.thumbs.close()
        win32gui.DestroyWindow(self.parent)

    async def until(self, condition, seconds=10):
        async with asyncio.timeout(seconds):
            while not condition():
                await asyncio.sleep(0.02)

    async def position(self):
        return await self.thumbs.mpv.command("get_property", "time-pos")

    async def test_preview_warms_up_follows_and_hides(self):
        # 4:3, so the preview grows to Lunoir's 240px cap for 320px wide
        await self.thumbs.sync_file(self.clip)
        await self.until(lambda: self.thumbs.file_ready)
        await self.until(lambda: self.thumbs.video_h == 240)
        self.thumbs.preview(30, 400, 400, 800, False)
        self.assertTrue(self.thumbs.visible and self.thumbs.surface.visible)
        # the warm-up plays to present a first frame, then seeks the queued time again, paused
        await self.until(lambda: self.thumbs.has_frame and self.thumbs.queued is None)
        await asyncio.sleep(0.3)
        self.assertAlmostEqual(await self.position(), 30, delta=0.1)
        self.assertTrue(await self.thumbs.mpv.command("get_property", "pause"))
        # (400 - 160, 400 - 262 - 8): centred on the pointer, 8px above the pill
        self.assertEqual(self.thumbs.surface.bounds, (240, 130, 320, 262))

        await asyncio.sleep(thumbs.MIN_SEEK)
        self.thumbs.preview(12, 10, 400, 800, True)
        self.assertEqual(self.thumbs.surface.bounds[:2], (0, 126))  # clamped left; docked gap 12
        await self.until(lambda: self.thumbs.queued is None)
        await asyncio.sleep(0.3)
        self.assertAlmostEqual(await self.position(), 12, delta=0.1)
        self.assertTrue(await self.thumbs.mpv.command("get_property", "pause"))

        # moves faster than 70 ms collapse into one trailing seek to the last time
        for t in (40, 41, 42):
            self.thumbs.preview(t, 400, 400, 800, False)
        await asyncio.sleep(thumbs.MIN_SEEK + 0.3)
        self.assertAlmostEqual(await self.position(), 42, delta=0.1)

        self.thumbs.hide()
        self.assertFalse(self.thumbs.visible or self.thumbs.surface.visible)
        await self.thumbs.sync_file(None)
        self.thumbs.preview(5, 400, 400, 800, False)  # disabled: ignored
        self.assertFalse(self.thumbs.visible)

    def test_clock(self):
        self.assertEqual(thumbs.clock(65.9), "01:05")
        self.assertEqual(thumbs.clock(3725), "1:02:05")
        self.assertEqual(thumbs.clock(float("nan")), "00:00")
        self.assertEqual(thumbs.clock(float("inf")), "00:00")


if __name__ == "__main__":
    unittest.main()
