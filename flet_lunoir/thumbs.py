"""Seek-bar preview, ported from Lunoir's main/thumb.ts.

A second, silent vmpv-host plays the same local file paused and seeks in place
(how MPC-HC does it; Lunoir found screenshots-to-file followed the pointer in
jumps). Lunoir gives it its own top-level window; here it embeds with --wid into a
second child of the Flet window, above the main video, like the main picture. A
native window covers whatever Flet draws under it, so it needs no hole. mpv's OSD
writes the time in the strip under the frame. Sizes are physical pixels, as in Lunoir.
"""
from __future__ import annotations

import asyncio
import contextlib
import logging
import math
import time

import win32gui

from .backend import MpvController, MpvError
from .native_video import NativeVideo

THUMB_W, THUMB_H, TIME_H = 320, 180, 22
FLOAT_GAP, DOCK_GAP = 8, 12
MIN_SEEK = 0.07
RADIUS = 8
log = logging.getLogger(__name__)
# Lunoir's THUMB_ARGS without the options for its own top-level window
THUMB_ARGS = [
    "--ao=null", "--volume=0", "--pause", "--keepaspect=yes",
    f"--video-margin-ratio-bottom={TIME_H / (THUMB_H + TIME_H)}",
    "--background=color", "--background-color=#FF3A3A3A",
    "--sid=no", "--aid=no", "--sub-auto=no", "--osd-bar=no", "--osd-level=1",
    "--osd-scale-by-window=no", "--osd-font=Segoe UI Semibold", "--osd-font-size=18.5",
    "--osd-spacing=0.6", "--osd-bold=no", "--osd-color=#FFCDCDD3", "--osd-outline-size=0",
    "--osd-shadow-offset=0", "--osd-back-color=#00000000", "--osd-align-x=center",
    "--osd-align-y=bottom", "--osd-margin-y=4", "--cursor-autohide=always",
]


def clock(seconds: float) -> str:
    """Lunoir's fmtTime: m:ss under an hour, h:mm:ss above."""
    seconds = max(0, int(seconds)) if math.isfinite(seconds) else 0
    h, m, s = seconds // 3600, seconds // 60 % 60, seconds % 60
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


class Thumbnails:
    def __init__(self, parent: int) -> None:
        self.parent = parent
        self.mpv: MpvController | None = None
        self.surface: NativeVideo | None = None
        self.events_task: asyncio.Task | None = None
        self.starting: asyncio.Task | None = None
        self.loaded = ""
        self.enabled = self.visible = self.file_ready = self.warming = self.has_frame = False
        self.loading = False
        self.video_h = THUMB_H
        self.queued: float | None = None
        self.last_seek = 0.0
        self.follow: asyncio.Task | None = None
        self.place_args: tuple | None = None

    # ------------------------------------------------------------- lifecycle
    async def _spawn(self) -> None:
        self.surface = NativeVideo(parent=self.parent, radius=RADIUS)
        mpv = MpvController()
        await mpv.start(self.surface.hwnd, THUMB_ARGS, observe=False)
        self.mpv = mpv
        self.events_task = asyncio.create_task(self._events())

    async def sync_file(self, path: str | None) -> None:
        """Preview this local file, or none (`syncFile`)."""
        if not path:
            self.enabled, self.loaded, self.file_ready = False, "", False
            self.hide()
            self._fire("stop")
            return
        self.enabled = True
        if not self.mpv:
            if not self.starting:
                self.starting = asyncio.create_task(self._spawn())
            try:
                await self.starting
            except (MpvError, OSError, RuntimeError):
                log.exception("seek preview player did not start")
                self.enabled, self.starting = False, None
                if self.surface:
                    self.surface.close()
                    self.surface = None
                return
        if path == self.loaded:
            return
        self.loaded = path
        self.file_ready = self.loading = self.warming = self.has_frame = False
        self._fire("loadfile", path, "replace")

    async def close(self) -> None:
        self.hide()
        if self.starting and not self.starting.done():
            self.starting.cancel()
        if self.events_task:
            self.events_task.cancel()
        if self.mpv:
            await self.mpv.close()
            self.mpv = None
        if self.surface:
            self.surface.close()
            self.surface = None
        self.enabled = False

    # --------------------------------------------------------------- the host
    def _fire(self, *args) -> None:
        """Commands are fire-and-forget, as Lunoir's `.catch(() => {})`."""
        if not self.mpv:
            return
        async def send():
            with contextlib.suppress(MpvError, OSError, asyncio.TimeoutError):
                await self.mpv.command(*args)
        asyncio.create_task(send())

    async def _events(self) -> None:
        while self.mpv:
            event = (await self.mpv.events.get()).get("event")
            if event == "file-loaded":
                # ready only after the load's own playback-restart; taken for the
                # warm-up's, it ended the warm-up mid-seek (a race thumb.ts has too)
                self.loading, self.has_frame = True, False
                await self._fit_aspect()
            elif event == "video-reconfig":
                await self._fit_aspect()
            elif event == "playback-restart" and self.loading:
                self.loading, self.file_ready = False, True
                if self.visible and self.queued is not None:
                    self._flush()
            elif event == "playback-restart" and self.warming:
                self.warming, self.has_frame = False, True
                self._fire("set_property", "pause", True)
                if self.visible and self.queued is not None:
                    self._flush()
                elif not self.visible:
                    self.hide()
            elif event == "backend-error":
                log.warning("seek preview player stopped")
                self.mpv, self.enabled = None, False
                self.hide()
                return

    async def _fit_aspect(self) -> None:
        try:
            aspect = await self.mpv.command("get_property", "video-params/aspect")
        except (MpvError, OSError, asyncio.TimeoutError, AttributeError):
            return
        if not isinstance(aspect, (int, float)) or not 0.2 < aspect < 6:
            aspect = 16 / 9
        height = max(90, min(240, round(THUMB_W / aspect)))
        if height == self.video_h:
            return
        self.video_h = height
        self._fire("set_property", "video-margin-ratio-bottom", TIME_H / (height + TIME_H))
        if self.visible and self.place_args:
            self._place(*self.place_args)

    # ---------------------------------------------------------------- preview
    def preview(self, t: float, x: float, osc_top: float, page_width: float, docked: bool) -> None:
        """Show the frame at t over the pointer's x, above the OSC (page coordinates)."""
        if not self.enabled or not self.mpv or not self.surface:
            return
        if not self.visible:
            self.visible = True
            self.surface.show(True)
            self.surface.raise_()
        self._place(x, osc_top, page_width, docked)
        self.queued = t
        wait = MIN_SEEK - (time.monotonic() - self.last_seek)
        if wait <= 0:
            self._flush()
        elif not self.follow or self.follow.done():
            async def follow():
                await asyncio.sleep(wait)
                self._flush()
            self.follow = asyncio.create_task(follow())

    def _flush(self) -> None:
        if self.follow and not self.follow.done() and self.follow is not asyncio.current_task():
            self.follow.cancel()
        if self.queued is None or not self.file_ready:
            return
        t = self.queued
        self.last_seek = time.monotonic()
        if not self.has_frame:
            # the first frame must be presented by a visible window (thumb.ts)
            self.warming = True
            self._fire("seek", t, "absolute+exact")
            self._fire("set_property", "pause", False)
            return
        self.queued = None
        self._fire("set_property", "pause", True)
        self._fire("seek", t, "absolute+exact")
        self._fire("show-text", clock(t), 100000)

    def hide(self) -> None:
        if self.follow and not self.follow.done():
            self.follow.cancel()
        self.queued = None
        if self.visible and self.surface:
            self.surface.show(False)
        self.visible = False

    def _place(self, x: float, osc_top: float, page_width: float, docked: bool) -> None:
        self.place_args = (x, osc_top, page_width, docked)
        left, _, right, _ = win32gui.GetClientRect(self.parent)
        scale = (right - left) / max(1, page_width)
        width, height = THUMB_W / scale, (self.video_h + TIME_H) / scale
        left = max(0, min(x - width / 2, page_width - width))
        top = max(0, osc_top - height - (DOCK_GAP if docked else FLOAT_GAP))
        self.surface.layout(left, top, width, height, page_width)
