import os
from pathlib import Path
import struct
import tempfile
import threading
import unittest

import pythoncom
import win32con
import win32gui
from win32com.server.exception import COMException
from win32com.server.util import wrap
import winerror

from flet_lunoir import drop
from flet_lunoir.instance import Instance, targets


class FakeData:
    """An IDataObject holding fixed formats, served to the drop target over COM."""
    _com_interfaces_ = [pythoncom.IID_IDataObject]
    _public_methods_ = ["GetData"]

    def __init__(self, formats: dict[int, bytes]) -> None:
        self.formats = formats

    def GetData(self, fe):
        if fe[0] not in self.formats:
            raise COMException(hresult=winerror.DV_E_FORMATETC)
        medium = pythoncom.STGMEDIUM()
        medium.set(pythoncom.TYMED_HGLOBAL, self.formats[fe[0]])
        return medium


def hdrop(paths: list[str]) -> bytes:
    return struct.pack("<IiiII", 20, 0, 0, 0, 1) + ("\0".join(paths) + "\0\0").encode("utf-16-le")


class SecondLaunch(unittest.TestCase):
    def test_targets_follow_lunoir_argv_rules(self):
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, "a b.mkv").write_bytes(b"")
            found = targets(["--flag", "a b.mkv", "missing.mkv", "https://x.test/live.m3u8", ""], folder)
            self.assertEqual(found, [os.path.join(folder, "a b.mkv"), "https://x.test/live.m3u8"])

    def test_one_player_per_profile_and_forwarding(self):
        with tempfile.TemporaryDirectory() as folder:
            first, second = Instance(Path(folder, "one")), Instance(Path(folder, "one"))
            self.assertTrue(first.claim())
            self.assertFalse(second.claim())
            self.assertTrue(Instance(Path(folder, "other")).claim())
            received, done = [], threading.Event()

            def handler(paths):
                received.append(paths)
                done.set()
                return 0
            first.serve(handler)
            self.assertTrue(second.forward([r"C:\v\film.mkv", "https://x.test/ä"], timeout=5))
            self.assertTrue(done.wait(5))
            self.assertEqual(received, [[r"C:\v\film.mkv", "https://x.test/ä"]])
            # the server keeps answering later launches
            self.assertTrue(second.forward([], timeout=5))

    def test_forward_gives_up_without_a_server(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertFalse(Instance(Path(folder)).forward(["x"], timeout=0.3))


class Drops(unittest.TestCase):
    def test_parsing_matches_lunoir(self):
        self.assertEqual(drop.hdrop_paths(hdrop([r"C:\a.mkv", r"D:\电影\b.mp4"])), [r"C:\a.mkv", r"D:\电影\b.mp4"])
        self.assertEqual(drop.hdrop_paths(b""), [])
        self.assertEqual(drop.first_url("# list\r\n  HTTPS://x.test/a.m3u \nhttp://y"), "HTTPS://x.test/a.m3u")
        self.assertEqual(drop.first_url("ftp://x\nplain"), "")

    def test_drop_target_over_com(self):
        got = []
        owner = type("Owner", (), {"set_hint": lambda self, on: got.append(("hint", on)),
                                   "on_drop": lambda self, items: got.append(("drop", items))})()
        target = wrap(drop._Target(owner), pythoncom.IID_IDropTarget)
        files = wrap(FakeData({win32con.CF_HDROP: hdrop([r"C:\a.mkv"])}), pythoncom.IID_IDataObject)
        link = wrap(FakeData({win32con.CF_UNICODETEXT: "https://x.test/v\0".encode("utf-16-le")}),
                    pythoncom.IID_IDataObject)
        nothing = wrap(FakeData({}), pythoncom.IID_IDataObject)
        copy_move_link = 1 | 2 | 4
        self.assertEqual(target.DragEnter(files, 0, (5, 5), copy_move_link), 1)
        self.assertEqual(target.DragOver(0, (6, 6), copy_move_link), 1)
        self.assertEqual(target.Drop(files, 0, (6, 6), copy_move_link), 1)
        self.assertEqual(target.DragEnter(link, 0, (5, 5), 4), 4)  # a link-only source
        target.DragLeave()
        self.assertEqual(target.DragEnter(nothing, 0, (5, 5), copy_move_link), 0)
        self.assertEqual(target.Drop(link, 0, (5, 5), copy_move_link), 1)
        self.assertEqual(got, [("hint", True), ("hint", False), ("drop", [r"C:\a.mkv"]), ("hint", True),
                               ("hint", False), ("hint", False), ("hint", False), ("drop", ["https://x.test/v"])])

    def test_hint_pixels(self):
        width, height = 200, 120
        clear = drop.hint_pixels(width, height, 1.0, False)
        self.assertEqual(len(clear), width * height * 4)
        self.assertEqual(set(clear[3::4]), {1})  # every pixel stays hit-testable
        hint = drop.hint_pixels(width, height, 1.0, True)

        def pixel(x, y):
            return bytes(hint[(y * width + x) * 4:(y * width + x) * 4 + 4])
        self.assertEqual(pixel(5, 60), drop._CLEAR)          # outside the 14px inset
        self.assertEqual(pixel(14, 14), drop._CLEAR)         # cut off by the rounded corner
        self.assertEqual(pixel(100, 60), drop._TINT)
        self.assertIn(drop._BORDER, (pixel(14, 32), pixel(14, 40)))  # dashed left edge
        self.assertIn(drop._BORDER, (pixel(32, 14), pixel(40, 14)))  # dashed top edge

    def test_overlay_window_lifecycle(self):
        parent = win32gui.CreateWindowEx(0, "STATIC", "drop test parent", win32con.WS_POPUP,
                                         0, 0, 300, 200, 0, 0, 0, None)
        try:
            target = drop.DropTarget(parent, lambda items: None)
            self.assertTrue(target.hwnd and win32gui.IsWindow(target.hwnd))
            self.assertEqual(win32gui.GetWindow(target.hwnd, win32con.GW_OWNER), parent)
            self.assertFalse(win32gui.IsWindowVisible(target.hwnd))  # parent hidden: never shown
            # off screen, so nothing flashes on the desktop
            win32gui.SetWindowPos(parent, 0, -4000, -4000, 300, 200, win32con.SWP_NOACTIVATE)
            for hint in (False, True):
                target.set_hint(hint)
                target.shown = True
                target._paint()
                self.assertEqual(target.painted, (-4000, -4000, 300, 200, hint))
            target.hint = target.shown = False
            target.close()
            target.thread.join(5)
            self.assertFalse(target.thread.is_alive())
            self.assertFalse(win32gui.IsWindow(target.hwnd))
        finally:
            win32gui.DestroyWindow(parent)


if __name__ == "__main__":
    unittest.main()
