"""One player per profile, like Lunoir's requestSingleInstanceLock.

A second launch ("Open with", a double-clicked file) hands its targets to the
running player over a named pipe, brings that window forward and exits. The lock
is keyed on the profile folder, as Electron's is on userData, so a run with a
scratch APPDATA stays separate from the real profile.
"""
from __future__ import annotations

import ctypes
import hashlib
import json
import logging
import os
from pathlib import Path
import threading
import time
from typing import Callable

import pywintypes
import win32api
import win32con
import win32event
import win32file
import win32gui
import win32pipe
import winerror

from .playlist import is_url

log = logging.getLogger(__name__)
_ASFW_ANY = 0xFFFFFFFF


def targets(argv: list[str], cwd: str | None = None) -> list[str]:
    """Lunoir's targetFromArgv, keeping every target: flags are skipped, URLs kept,
    paths made absolute against the launching directory and dropped if missing."""
    found = []
    for raw in argv:
        if not raw or raw.startswith("-"):
            continue
        if is_url(raw):
            found.append(raw)
            continue
        path = os.path.abspath(os.path.join(cwd or os.getcwd(), raw))
        if os.path.exists(path):
            found.append(path)
    return found


class Instance:
    def __init__(self, profile: Path) -> None:
        key = hashlib.sha1(os.path.normcase(os.path.abspath(profile)).encode("utf-8")).hexdigest()[:16]
        self.mutex_name = f"Local\\LunoirV-{key}"
        self.pipe_name = rf"\\.\pipe\lunoir-v-instance-{key}"
        self.mutex = None
        self.thread: threading.Thread | None = None

    def claim(self) -> bool:
        """True when this process is the profile's player."""
        self.mutex = win32event.CreateMutex(None, False, self.mutex_name)
        return win32api.GetLastError() != winerror.ERROR_ALREADY_EXISTS

    def forward(self, found: list[str], timeout: float = 15.0) -> bool:
        """Send targets to the running player and raise its window. False when it
        never answered (still starting past the timeout, or hung)."""
        # we were just launched by the user, so we may pass on the right to take focus
        ctypes.windll.user32.AllowSetForegroundWindow(_ASFW_ANY)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                handle = win32file.CreateFile(self.pipe_name, win32file.GENERIC_READ | win32file.GENERIC_WRITE,
                                              0, None, win32file.OPEN_EXISTING, 0, None)
            except pywintypes.error as error:
                # not serving yet (starting up) or busy with another launch
                if error.winerror not in (winerror.ERROR_FILE_NOT_FOUND, winerror.ERROR_PIPE_BUSY):
                    raise
                time.sleep(0.1)
                continue
            try:
                win32pipe.SetNamedPipeHandleState(handle, win32pipe.PIPE_READMODE_MESSAGE, None, None)
                win32file.WriteFile(handle, json.dumps(found).encode("utf-8"))
                _, reply = win32file.ReadFile(handle, 64)
            finally:
                win32file.CloseHandle(handle)
            raise_window(int(reply or b"0"))
            return True
        return False

    def serve(self, handler: Callable[[list[str]], int]) -> None:
        """Answer later launches on a daemon thread. handler gets their targets and
        returns the window to raise."""
        def run():
            while True:
                try:
                    pipe = win32pipe.CreateNamedPipe(
                        self.pipe_name, win32pipe.PIPE_ACCESS_DUPLEX,
                        win32pipe.PIPE_TYPE_MESSAGE | win32pipe.PIPE_READMODE_MESSAGE | win32pipe.PIPE_WAIT,
                        win32pipe.PIPE_UNLIMITED_INSTANCES, 4096, 4096, 0, None)
                except pywintypes.error:
                    log.exception("single-instance pipe unavailable")
                    return
                try:
                    try:
                        win32pipe.ConnectNamedPipe(pipe, None)
                    except pywintypes.error as error:
                        if error.winerror != winerror.ERROR_PIPE_CONNECTED:
                            raise
                    _, data = win32file.ReadFile(pipe, 65536)
                    found = json.loads(data.decode("utf-8"))
                    hwnd = handler([str(item) for item in found] if isinstance(found, list) else [])
                    win32file.WriteFile(pipe, str(hwnd or 0).encode("ascii"))
                    win32file.FlushFileBuffers(pipe)
                except (pywintypes.error, ValueError):
                    log.warning("bad request from a second launch", exc_info=True)
                finally:
                    try:
                        win32pipe.DisconnectNamedPipe(pipe)
                    except pywintypes.error:
                        pass
                    win32file.CloseHandle(pipe)

        self.thread = threading.Thread(target=run, name="lunoir-instance", daemon=True)
        self.thread.start()


def raise_window(hwnd: int) -> None:
    """Lunoir's focusMainWindow, done from the process the user just launched."""
    if not hwnd or not win32gui.IsWindow(hwnd):
        return
    try:
        if win32gui.IsIconic(hwnd):
            win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
        win32gui.SetForegroundWindow(hwnd)
    except pywintypes.error:
        pass  # Windows may refuse focus; the window still opened the file
