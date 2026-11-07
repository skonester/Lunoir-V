"""A video surface only: Flet draws every visible UI control.

libmpv embeds into this child HWND. No Python mpv library or Flet video decoder
is used. The child cannot take focus away from Flet's keyboard shortcuts.

Flet cannot paint over a native window, so controls floating over the picture are
shown through holes: the child's window region excludes their rounded rectangles,
and Flet's own drawing shows there. mpv's D3D11 output is clipped by the region.
"""
from __future__ import annotations

import ctypes

import win32con
import win32gui

_gdi = ctypes.windll.gdi32
_user = ctypes.windll.user32
_RGN_DIFF = 4
_HANDLE = ctypes.c_void_p
_gdi.CreateRectRgn.restype = _HANDLE
_gdi.CreateRoundRectRgn.restype = _HANDLE
_gdi.CombineRgn.argtypes = (_HANDLE, _HANDLE, _HANDLE, ctypes.c_int)
_gdi.DeleteObject.argtypes = (_HANDLE,)
_user.SetWindowRgn.argtypes = (_HANDLE, _HANDLE, ctypes.c_bool)


class NativeVideo:
    def __init__(self, title: str = "", parent: int = 0, radius: float = 0) -> None:
        """Inside the window titled `title`, or a known `parent`. `radius` rounds the
        child's own corners (the seek preview)."""
        self.parent = parent or win32gui.FindWindow(None, title)
        if not self.parent:
            raise RuntimeError("Flet's desktop window is not ready yet.")
        self.radius = radius
        self.hwnd = win32gui.CreateWindowEx(
            0, "STATIC", "Lunoir V video", win32con.WS_CHILD | win32con.WS_DISABLED | win32con.SS_BLACKRECT,
            0, 0, 1, 1, self.parent, 0, 0, None,
        )
        self.bounds = None
        self.logical = (0.0, 0.0, 1.0, 1.0)
        self.scale = 1.0
        self.holes: tuple = ()
        self.visible = False

    def layout(self, x: float, y: float, width: float, height: float, page_width: float) -> bool:
        # Comparing physical client pixels to Flet's logical page width also
        # handles moving between monitors with different DPI scaling.
        client = win32gui.GetClientRect(self.parent)
        self.scale = (client[2] - client[0]) / max(1, page_width)
        self.logical = (x, y, width, height)
        bounds = tuple(round(v * self.scale) for v in (x, y, width, height))
        if bounds != self.bounds:
            win32gui.SetWindowPos(self.hwnd, win32con.HWND_TOP, bounds[0], bounds[1],
                                  max(1, bounds[2]), max(1, bounds[3]), win32con.SWP_NOACTIVATE)
            self.bounds = bounds
            self._apply_region()
            return True
        return False

    def set_holes(self, holes: list[tuple[float, float, float, float, float]]) -> bool:
        """Rounded rectangles (x, y, width, height, radius) in Flet page coordinates.
        Returns True when the region changed."""
        holes = tuple(holes)
        if holes == self.holes:
            return False
        self.holes = holes
        self._apply_region()
        return True

    def _apply_region(self) -> None:
        if not self.bounds:
            return
        s, (ox, oy) = self.scale, self.logical[:2]
        if not self.holes and not self.radius:
            _user.SetWindowRgn(self.hwnd, None, True)
            return
        if self.radius:
            corner = round(2 * self.radius * s)
            region = _gdi.CreateRoundRectRgn(0, 0, self.bounds[2] + 1, self.bounds[3] + 1, corner, corner)
        else:
            region = _gdi.CreateRectRgn(0, 0, self.bounds[2], self.bounds[3])
        for x, y, width, height, radius in self.holes:
            left, top = round((x - ox) * s), round((y - oy) * s)
            hole = _gdi.CreateRoundRectRgn(left, top, left + round(width * s) + 1,
                                           top + round(height * s) + 1,
                                           round(2 * radius * s), round(2 * radius * s))
            _gdi.CombineRgn(region, region, hole, _RGN_DIFF)
            _gdi.DeleteObject(hole)
        # The system owns the region after SetWindowRgn succeeds.
        if not _user.SetWindowRgn(self.hwnd, region, True):
            _gdi.DeleteObject(region)

    def raise_(self) -> None:
        win32gui.SetWindowPos(self.hwnd, win32con.HWND_TOP, 0, 0, 0, 0,
                              win32con.SWP_NOMOVE | win32con.SWP_NOSIZE | win32con.SWP_NOACTIVATE)

    def show(self, visible: bool) -> None:
        if visible != self.visible:
            win32gui.ShowWindow(self.hwnd, win32con.SW_SHOWNA if visible else win32con.SW_HIDE)
            self.visible = visible

    def cursor(self) -> tuple[float, float] | None:
        """The pointer in Flet page coordinates while it is over this window, else None."""
        try:
            point = win32gui.GetCursorPos()
            under = win32gui.WindowFromPoint(point)
        except win32gui.error:
            return None
        if under != self.parent and under != self.hwnd and not win32gui.IsChild(self.parent, under):
            return None
        x, y = win32gui.ScreenToClient(self.parent, point)
        return x / self.scale, y / self.scale

    def focused(self) -> bool:
        return win32gui.GetForegroundWindow() == self.parent

    def pump(self) -> None:
        win32gui.PumpWaitingMessages()

    def close(self) -> None:
        if win32gui.IsWindow(self.hwnd):
            win32gui.DestroyWindow(self.hwnd)
