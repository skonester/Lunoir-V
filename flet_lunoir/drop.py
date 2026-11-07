"""OS file and link drops, which Flet 1.0.5 does not report.

The Flet window belongs to flet.exe, so no drop target can be registered on it from
here. Instead, while a drag that began outside the player hovers over it, an
almost transparent layered window of ours covers the client area and takes the
drop through OLE. It paints Lunoir's drop hint (styles.css `.drop-hint`) once OLE
says the drag carries files or a link. The window lives on its own thread with its
own message loop, so the drag source never waits on asyncio.

Like Lunoir's OverlayView onDrop: files win; otherwise the first http(s) line of a
dragged link or text (browsers hand over text, not a uri-list, on Windows).
"""
from __future__ import annotations

import ctypes
from ctypes import wintypes
import logging
import math
import re
import struct
import threading
from typing import Callable

import pythoncom
import pywintypes
import win32api
import win32clipboard
import win32con
import win32gui
from win32com.server.util import wrap

log = logging.getLogger(__name__)
_user = ctypes.windll.user32
_gdi = ctypes.windll.gdi32
_user.SetTimer.argtypes = (wintypes.HWND, ctypes.c_size_t, wintypes.UINT, ctypes.c_void_p)
_user.SetTimer.restype = ctypes.c_size_t
_user.KillTimer.argtypes = (wintypes.HWND, ctypes.c_size_t)
_user.GetDC.restype = wintypes.HDC
_user.ReleaseDC.argtypes = (wintypes.HWND, wintypes.HDC)
_user.UpdateLayeredWindow.argtypes = (wintypes.HWND, wintypes.HDC, ctypes.c_void_p, ctypes.c_void_p,
                                      wintypes.HDC, ctypes.c_void_p, wintypes.COLORREF, ctypes.c_void_p,
                                      wintypes.DWORD)
_gdi.CreateCompatibleDC.argtypes = (wintypes.HDC,)
_gdi.CreateCompatibleDC.restype = wintypes.HDC
_gdi.CreateDIBSection.argtypes = (wintypes.HDC, ctypes.c_void_p, wintypes.UINT,
                                  ctypes.POINTER(ctypes.c_void_p), wintypes.HANDLE, wintypes.DWORD)
_gdi.CreateDIBSection.restype = wintypes.HBITMAP
_gdi.SelectObject.argtypes = (wintypes.HDC, wintypes.HGDIOBJ)
_gdi.SelectObject.restype = wintypes.HGDIOBJ
_gdi.DeleteObject.argtypes = (wintypes.HGDIOBJ,)
_gdi.DeleteDC.argtypes = (wintypes.HDC,)

TICK_MS = 30
_DROPEFFECT_NONE, _DROPEFFECT_COPY, _DROPEFFECT_LINK = 0, 1, 4
# premultiplied BGRA. Clear keeps alpha 1: fully transparent pixels would not be hit
# by the drag, and 1/255 of black is invisible.
_CLEAR = bytes((0, 0, 0, 1))
_TINT = bytes((23, 10, 9, 23))        # rgba(96, 108, 255, 0.09)
_BORDER = bytes((191, 106, 92, 191))  # rgba(122, 142, 255, 0.75)
_URL_FORMAT = win32clipboard.RegisterClipboardFormat("UniformResourceLocatorW")
_targets: dict[int, "DropTarget"] = {}  # one window class, so messages are routed by hwnd


def _proc(hwnd, message, wparam, lparam):
    target = _targets.get(hwnd)
    if target:
        return target._message(hwnd, message, wparam, lparam)
    return win32gui.DefWindowProc(hwnd, message, wparam, lparam)


def hdrop_paths(raw: bytes | None) -> list[str]:
    """The paths in a CF_HDROP block (a DROPFILES header, then a NUL-separated list)."""
    if not raw or len(raw) < 20:
        return []
    offset, _x, _y, _nc, wide = struct.unpack_from("<IiiII", raw)
    body = raw[offset:]
    text = body.decode("utf-16-le", "replace") if wide else body.decode("mbcs", "replace")
    return [path for path in text.split("\0\0", 1)[0].split("\0") if path]


def first_url(text: str) -> str:
    return next((line.strip() for line in text.splitlines() if re.match(r"^https?://", line.strip(), re.I)), "")


def dropped_items(data) -> list[str]:
    def read(fmt):
        try:
            return data.GetData((fmt, None, pythoncom.DVASPECT_CONTENT, -1, pythoncom.TYMED_HGLOBAL)).data
        except pythoncom.com_error:
            return None
    paths = hdrop_paths(read(win32con.CF_HDROP))
    if paths:
        return paths
    for fmt in (win32con.CF_UNICODETEXT, _URL_FORMAT):
        raw = read(fmt)
        url = first_url(raw.decode("utf-16-le", "replace").split("\0", 1)[0]) if raw else ""
        if url:
            return [url]
    return []


def hint_pixels(width: int, height: int, scale: float, hint: bool) -> bytearray:
    """Top-down BGRA for the overlay: clear, or Lunoir's dashed rounded hint
    (inset 14px, 2px border, radius 18px)."""
    pixels = bytearray(_CLEAR * (width * height))
    if not hint:
        return pixels
    inset, line, radius = round(14 * scale), max(1, round(2 * scale)), round(18 * scale)
    left, top, right, bottom = inset, inset, width - inset, height - inset
    if right - left < 2 * radius or bottom - top < 2 * radius:
        return pixels
    dash = 3 * line

    def put(x, y, colour):
        at = (y * width + x) * 4
        pixels[at:at + 4] = colour

    for y in range(top, bottom):
        row = y * width
        dy = top + radius - y if y < top + radius else y - (bottom - radius - 1) if y >= bottom - radius else 0
        if dy > 0:
            # corner rows: the span inside the circle, the border where it is thin
            for side in (0, 1):
                cx = left + radius if side == 0 else right - radius - 1
                for x in range(left, left + radius) if side == 0 else range(right - radius, right):
                    distance = math.hypot(x - cx, dy)
                    if distance <= radius:
                        put(x, y, _BORDER if distance > radius - line else _TINT)
            span_left, span_right = left + radius, right - radius
            on_edge = y < top + line or y >= bottom - line
            pixels[(row + span_left) * 4:(row + span_right) * 4] = _TINT * (span_right - span_left)
            if on_edge:
                for x in range(span_left, span_right):
                    if (x - span_left) // dash % 2 == 0:
                        put(x, y, _BORDER)
        else:
            pixels[(row + left) * 4:(row + right) * 4] = _TINT * (right - left)
            if (y - top - radius) // dash % 2 == 0:
                pixels[(row + left) * 4:(row + left + line) * 4] = _BORDER * line
                pixels[(row + right - line) * 4:(row + right) * 4] = _BORDER * line
    return pixels


class _Target:
    _com_interfaces_ = [pythoncom.IID_IDropTarget]
    _public_methods_ = ["DragEnter", "DragOver", "DragLeave", "Drop"]

    def __init__(self, owner: "DropTarget") -> None:
        self.owner = owner
        self.effect = _DROPEFFECT_NONE

    def _pick(self, allowed: int) -> int:
        return _DROPEFFECT_COPY if allowed & _DROPEFFECT_COPY else allowed & _DROPEFFECT_LINK

    def DragEnter(self, data, key_state, point, allowed):
        self.effect = self._pick(allowed) if dropped_items(data) else _DROPEFFECT_NONE
        self.owner.set_hint(bool(self.effect))
        return self.effect

    def DragOver(self, key_state, point, allowed):
        return self.effect

    def DragLeave(self):
        self.owner.set_hint(False)

    def Drop(self, data, key_state, point, allowed):
        self.owner.set_hint(False)
        items = dropped_items(data)
        if items:
            try:
                self.owner.on_drop(items)
            except Exception:
                log.exception("drop handler failed")
        return self._pick(allowed) if items else _DROPEFFECT_NONE


class DropTarget:
    def __init__(self, parent: int, on_drop: Callable[[list[str]], None]) -> None:
        self.parent, self.on_drop = parent, on_drop
        self.hwnd = 0
        self.hint = self.shown = False
        self.was_down = self.press_outside = False
        self.painted: tuple | None = None
        self.ready = threading.Event()
        self.thread = threading.Thread(target=self._run, name="lunoir-drop", daemon=True)
        self.thread.start()
        self.ready.wait(5)

    # ------------------------------------------------------------- the thread
    def _run(self) -> None:
        pythoncom.OleInitialize()
        try:
            instance = win32api.GetModuleHandle(None)
            wc = win32gui.WNDCLASS()
            wc.lpszClassName = "LunoirVDrop"
            wc.hInstance = instance
            wc.lpfnWndProc = _proc
            wc.hCursor = win32gui.LoadCursor(0, win32con.IDC_ARROW)
            try:
                win32gui.RegisterClass(wc)
            except pywintypes.error as error:
                if error.winerror != 1410:  # ERROR_CLASS_ALREADY_EXISTS
                    raise
            # owned by the Flet window: always above it, minimised and closed with it
            self.hwnd = win32gui.CreateWindowEx(
                win32con.WS_EX_LAYERED | win32con.WS_EX_TOOLWINDOW | win32con.WS_EX_NOACTIVATE,
                "LunoirVDrop", "Lunoir V drop", win32con.WS_POPUP, 0, 0, 1, 1,
                self.parent, 0, instance, None)
            _targets[self.hwnd] = self
            pythoncom.RegisterDragDrop(self.hwnd, wrap(_Target(self), pythoncom.IID_IDropTarget))
            _user.SetTimer(self.hwnd, 1, TICK_MS, None)
        except Exception:
            log.exception("file drops unavailable")
            self.hwnd = 0
            return
        finally:
            self.ready.set()
        try:
            win32gui.PumpMessages()
        finally:
            pythoncom.CoUninitialize()  # pairs with OleInitialize

    def _message(self, hwnd, message, wparam, lparam):
        if message == win32con.WM_TIMER:
            self._tick()
            return 0
        if message == win32con.WM_MOUSEACTIVATE:
            return win32con.MA_NOACTIVATE
        if message == win32con.WM_CLOSE:
            _user.KillTimer(hwnd, 1)
            try:
                pythoncom.RevokeDragDrop(hwnd)
            except pythoncom.com_error:
                pass
            win32gui.DestroyWindow(hwnd)
            return 0
        if message == win32con.WM_DESTROY:
            _targets.pop(hwnd, None)
            win32gui.PostQuitMessage(0)
            return 0
        return win32gui.DefWindowProc(hwnd, message, wparam, lparam)

    def _over_player(self, point) -> bool:
        try:
            under = win32gui.WindowFromPoint(point)
            root = win32gui.GetAncestor(under, win32con.GA_ROOT) if under else 0
        except pywintypes.error:
            return False
        return root in (self.parent, self.hwnd)

    def _tick(self) -> None:
        if not win32gui.IsWindow(self.parent):
            win32gui.PostMessage(self.hwnd, win32con.WM_CLOSE, 0, 0)
            return
        down = any(win32api.GetAsyncKeyState(key) & 0x8000 for key in (win32con.VK_LBUTTON, win32con.VK_RBUTTON))
        try:
            point = win32gui.GetCursorPos()
        except pywintypes.error:
            return
        over = self._over_player(point)
        if down and not self.was_down:
            # a press inside the player is our own click or drag, never a file drop
            self.press_outside = not over
        self.was_down = down
        usable = win32gui.IsWindowVisible(self.parent) and not win32gui.IsIconic(self.parent)
        self._show(usable and (self.hint or (down and self.press_outside and over)))

    def _show(self, visible: bool) -> None:
        if visible:
            self._paint()
            if not self.shown:
                win32gui.ShowWindow(self.hwnd, win32con.SW_SHOWNA)
        elif self.shown:
            win32gui.ShowWindow(self.hwnd, win32con.SW_HIDE)
        self.shown = visible

    def set_hint(self, hint: bool) -> None:
        # called on this thread by OLE, between DragEnter and DragLeave/Drop
        self.hint = hint
        if self.shown:
            self._paint()

    def _paint(self) -> None:
        left, top, right, bottom = win32gui.GetClientRect(self.parent)
        x, y = win32gui.ClientToScreen(self.parent, (left, top))
        width, height = right - left, bottom - top
        if width <= 0 or height <= 0:
            return
        state = (x, y, width, height, self.hint)
        if state == self.painted:
            return
        try:
            scale = _user.GetDpiForWindow(self.parent) / 96 or 1.0
        except (AttributeError, OSError):
            scale = 1.0
        pixels = hint_pixels(width, height, scale, self.hint)
        header = struct.pack("<IiiHHIIiiII", 40, width, -height, 1, 32, 0, 0, 0, 0, 0, 0)
        screen = _user.GetDC(None)
        memory = _gdi.CreateCompatibleDC(screen)
        bits = ctypes.c_void_p()
        bitmap = _gdi.CreateDIBSection(memory, header, 0, ctypes.byref(bits), None, 0)
        try:
            if not bitmap:
                return
            ctypes.memmove(bits, bytes(pixels), len(pixels))
            previous = _gdi.SelectObject(memory, bitmap)
            position, size, origin = wintypes.POINT(x, y), wintypes.SIZE(width, height), wintypes.POINT(0, 0)
            blend = struct.pack("<BBBB", 0, 0, 255, 1)  # AC_SRC_OVER, per-pixel alpha
            if _user.UpdateLayeredWindow(self.hwnd, screen, ctypes.byref(position), ctypes.byref(size),
                                         memory, ctypes.byref(origin), 0, blend, 2):  # ULW_ALPHA
                self.painted = state
            else:
                log.warning("drop overlay paint failed: %s", ctypes.GetLastError())
            _gdi.SelectObject(memory, previous)
        finally:
            if bitmap:
                _gdi.DeleteObject(bitmap)
            _gdi.DeleteDC(memory)
            _user.ReleaseDC(None, screen)

    def close(self) -> None:
        if self.hwnd and win32gui.IsWindow(self.hwnd):
            win32gui.PostMessage(self.hwnd, win32con.WM_CLOSE, 0, 0)
