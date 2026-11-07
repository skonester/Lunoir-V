"""Flet reconstruction of Lunoir's window: home, OSC, side panels and library.

Reference: src/renderer/src and src/main/index.ts of https://github.com/zhbj420/Lunoir, by Yao666 (MIT).
Playback is performed exclusively by the V host through backend.MpvController.
"""
from __future__ import annotations

import asyncio
import logging
import os
from pathlib import Path
import random
import time

import flet as ft
import win32api
import win32con
import win32process

from . import formatting as fmt
from . import options, panels, playlist, ytdl
from .backend import MpvController, MpvError, tie_to_this_process
from .drop import DropTarget
from .i18n import Translator
from .instance import Instance
from .native_video import NativeVideo
from .playlist import Entry, is_url, media_name
from .profile import Profile, queue_key
from .thumbs import Thumbnails

TEXT = "#EEEEF0"
DIM = "#92929C"
PANEL = "#242429"
LINE = "#393940"
HEADER = 40
TRANSPORT_HEIGHT = 118
PANEL_WIDTH = 320
OSD_HEIGHT = 36
OSD_WIDTHS = {"volume": 218, "zoom": 94}  # padding + icon + gaps + bar + number
FRAME_STEP_SECONDS = 0.025
ASPECT_TARGETS = {"16:9": 16 / 9, "4:3": 4 / 3, "2.35": 2.35}
log = logging.getLogger(__name__)
SNAPSHOTS = os.environ.get("LUNOIR_V_SNAPSHOTS", "")


class Lunoir:
    def __init__(self, page: ft.Page, startup: list[str], instance: Instance | None = None) -> None:
        self.page, self.startup, self.instance = page, startup, instance
        self.backend = MpvController()
        self.profile = Profile()
        self.ytdl = ytdl.Ytdl(self.profile.directory)
        self.ytdl_error = ""  # yt-dlp's reason for the current load failing
        self.ytdl_state = "idle"  # the Settings refresh button: idle, working, done, error
        self.ytdl_version_task: asyncio.Task | None = None
        self.volume_dragging = False
        self.settings = self.profile.settings
        if not self.settings.get("screenshotDir"):
            self.profile.set("screenshotDir", options.screenshot_dir(self.settings))
        self.t = Translator(self.settings["uiLanguage"])
        self.surface: NativeVideo | None = None
        self.drop: DropTarget | None = None
        self.thumbs: Thumbnails | None = None
        self.preview_cursor = None
        self.ready = self.closed = self.has_media = self.dragging = self.dialog_open = False
        # playlist state, kept here as in Lunoir's main process
        self.queue: list[Entry] = []
        self.index = -1
        self.source_type = "queue"  # or "iptv"
        self.playlist_key = ""
        self.source_ua = ""
        self.open_target_kind = ("", "")
        self.recent_pending = False
        self.repeat, self.shuffle = "off", False
        self.shuffle_history: list[int] = []
        self.current = self.resume_target = ""
        self.pending_resume = ""
        self.subtitle_revision = 0
        self.aspect = "default"
        self.applied_aspect = (True, "")  # mpv's defaults: keepaspect, no crop
        # UI state
        self.panel_mode = ""
        self.settings_tab, self.library_tab = "playback", "recent"
        self.channel_query = ""
        self.url_mode = False
        self.info_data: dict = {}
        self.revealed = True
        self.last_activity = time.monotonic()
        self.last_cursor = None
        self.arrow_mode, self.last_arrow, self.last_step = "", 0.0, 0.0
        self.stepping_until = 0.0
        self.toast_task: asyncio.Task | None = None
        self.osd_task: asyncio.Task | None = None
        self.zoom = 0.0  # log2 of video-zoom's scale (0 = 100 %)
        self.pan = (0.0, 0.0)  # video-pan-x/y
        self.pan_origin: tuple[float, float, float, float] | None = None
        self.pan_was_playing = False
        self.repaint_task: asyncio.Task | None = None
        self.last_saved = 0.0
        self.properties = {"pause": False, "volume": self.settings["volume"], "duration": 0,
                           "time-pos": 0, "mute": False, "seekable": True, "speed": 1}
        self.caption = f"Lunoir · V · {os.getpid()}"
        page.title = self.caption
        page.theme_mode = ft.ThemeMode.DARK
        page.theme = ft.Theme(font_family="Segoe UI", color_scheme_seed="#A8A8AE")
        page.bgcolor = "#17171C"
        page.padding = page.spacing = 0
        page.enable_screenshots = bool(SNAPSHOTS)
        page.window.width, page.window.height = 1120, 760
        bounds = self.settings.get("windowBounds")
        if self.settings.get("rememberWindow") and isinstance(bounds, dict):
            page.window.left, page.window.top = bounds.get("x"), bounds.get("y")
            page.window.width = max(900, bounds.get("width") or 1120)
            page.window.height = max(560, bounds.get("height") or 760)
        page.window.min_width, page.window.min_height = 900, 560
        page.window.title_bar_hidden = True
        page.window.prevent_close = True
        page.window.on_event = self.window_event
        page.on_keyboard_event = self.keyboard
        page.on_resize = self.resize
        page.on_disconnect = self.disconnect
        self.build_ui()

    # ---------------------------------------------------------------- building
    def icon(self, icon, hint, callback, **kwargs):
        return ft.IconButton(icon, tooltip=hint, icon_size=21, icon_color=DIM,
                             on_click=callback, **kwargs)

    def callback(self, coroutine, *args):
        async def handler(_=None):
            await coroutine(*args)
        return handler

    def build_ui(self) -> None:
        t = self.t
        self.page.controls.clear()
        self.title = ft.Text(self.window_title(), size=12, color=DIM, max_lines=1,
                             overflow=ft.TextOverflow.ELLIPSIS)
        self.header = ft.Container(height=HEADER, left=0, right=0, top=0, bgcolor="#1E1E23",
            content=ft.Row([
                ft.WindowDragArea(ft.Container(ft.Row([
                    ft.Image(src="logo.png", width=22, height=22), self.title,
                ], spacing=10), padding=ft.Padding.only(left=16)), expand=True),
                self.icon(ft.Icons.REMOVE, t("win.minimize"), self.minimize, width=44),
                self.icon(ft.Icons.CROP_SQUARE, t("win.maximize"), self.maximize, width=44),
                self.icon(ft.Icons.CLOSE, t("win.close"), self.shutdown, width=44),
            ], spacing=0))
        self.home = ft.GestureDetector(left=0, top=HEADER, right=0, bottom=0,
            on_secondary_tap=self.toggle_url_mode,
            content=ft.Container(
                gradient=ft.RadialGradient(center=ft.Alignment(0, -0.25), radius=1.15,
                                           colors=["#33333B", "#17171D"]),
                alignment=ft.Alignment.CENTER, content=self.home_content()))
        self.home_entries = ft.Container(right=24, bottom=20, content=ft.Row([
            self.icon(ft.Icons.STAR_BORDER_ROUNDED, t("osc.library"), self.callback(self.toggle_panel, "library")),
            self.icon(ft.Icons.SETTINGS_OUTLINED, t("common.settings"), self.callback(self.toggle_panel, "settings")),
        ], spacing=8))
        # Flet draws nothing visible here; the native video child covers it. It
        # receives the clicks Windows passes through the disabled child window.
        self.video_area = ft.GestureDetector(visible=False, content=ft.Container(bgcolor="#000000"),
            on_tap=self.video_tap, on_double_tap=self.video_double_tap,
            on_secondary_tap=self.video_secondary, on_hover=self.pointer_moved, hover_interval=100,
            on_scroll=self.video_wheel, on_pan_start=self.pan_start, on_pan_update=self.pan_update,
            on_pan_end=self.pan_end, drag_interval=16)
        self.time_text = ft.Text("00:00", size=11, color=DIM)
        self.duration_text = ft.Text("00:00", size=11, color=DIM)
        self.badges = ft.Text("", size=11, color=DIM, max_lines=1, overflow=ft.TextOverflow.ELLIPSIS)
        # no padding: the track then spans the whole slider, so a pointer x maps
        # straight to a time for the seek preview (seek_rect)
        self.seek = ft.Slider(min=0, max=1, value=0, height=22, expand=True, padding=ft.Padding.all(0),
            active_color="#BDBDC4", inactive_color="#48484F", thumb_color=TEXT,
            on_change_start=self.seek_start, on_change_end=self.seek_end)
        self.play_button = ft.IconButton(ft.Icons.PLAY_ARROW_ROUNDED, icon_size=34,
            icon_color="#222227", bgcolor="#DEDEE3", width=48, height=48,
            tooltip=t("osc.play"), on_click=self.callback(self.command, "cycle", "pause"))
        self.mute_button = self.icon(ft.Icons.VOLUME_UP_ROUNDED, t("osc.mute"),
                                     self.callback(self.command, "cycle", "mute"))
        self.volume = ft.Slider(min=0, max=150, value=float(self.properties.get("volume") or 0),
            width=104, height=28, padding=ft.Padding.symmetric(horizontal=8),
            active_color="#BDBDC4", inactive_color="#48484F", on_change_start=self.volume_start,
            on_change=self.volume_change, on_change_end=self.volume_end)
        self.repeat_button = self.icon(ft.Icons.REPEAT_ROUNDED, t(f"panel.repeat.{self.repeat}"), self.cycle_repeat)
        self.shuffle_button = self.icon(ft.Icons.SHUFFLE_ROUNDED,
                                        t("panel.shuffle.on" if self.shuffle else "panel.shuffle.off"), self.toggle_shuffle)
        self.style_repeat_shuffle()
        self.transport = ft.Container(bottom=20, height=TRANSPORT_HEIGHT, border_radius=24,
            bgcolor=PANEL, border=ft.Border.all(1, LINE), padding=ft.Padding.symmetric(horizontal=22, vertical=12),
            visible=False, on_hover=self.pointer_moved, content=ft.Column([
                ft.Row([
                    ft.GestureDetector(self.time_text, on_tap=self.cycle_time_format,
                                       mouse_cursor=ft.MouseCursor.CLICK, tooltip=t("osc.timeFormat")),
                    ft.Container(expand=True), self.badges, ft.Container(width=8), self.duration_text,
                ], height=18),
                self.seek,
                ft.Row([
                    self.shuffle_button,
                    self.icon(ft.Icons.SKIP_PREVIOUS_ROUNDED, t("menu.previous"), self.callback(self.advance, -1)),
                    self.icon(ft.Icons.REPLAY_10_ROUNDED, t("osc.back", n=10), self.callback(self.command, "seek", -10, "relative")),
                    self.play_button,
                    self.icon(ft.Icons.FORWARD_10_ROUNDED, t("osc.forward", n=10), self.callback(self.command, "seek", 10, "relative")),
                    self.icon(ft.Icons.SKIP_NEXT_ROUNDED, t("menu.next"), self.callback(self.advance, 1)),
                    self.repeat_button, ft.Container(expand=True), self.mute_button, self.volume,
                    self.icon(ft.Icons.QUEUE_MUSIC_ROUNDED, t("osc.panel"), self.callback(self.toggle_panel, "tracks")),
                    self.icon(ft.Icons.STAR_BORDER_ROUNDED, t("osc.library"), self.callback(self.toggle_panel, "library")),
                    self.icon(ft.Icons.SETTINGS_OUTLINED, t("common.settings"), self.callback(self.toggle_panel, "settings")),
                    self.icon(ft.Icons.MORE_HORIZ_ROUNDED, None, self.callback(self.toggle_panel, "menu")),
                    self.icon(ft.Icons.FULLSCREEN_ROUNDED, t("menu.fullscreen"), self.fullscreen),
                ], spacing=0, height=48),
            ], spacing=3))
        self.panel_header = ft.Row([], spacing=4)
        self.panel_body = ft.Column(scroll=ft.ScrollMode.AUTO, expand=True, spacing=6)
        self.panel = ft.Container(right=16, width=PANEL_WIDTH, visible=False, on_hover=self.pointer_moved,
            bgcolor=PANEL, border=ft.Border.all(1, LINE), border_radius=18,
            padding=ft.Padding.only(left=18, right=10, top=12, bottom=14),
            content=ft.Column([self.panel_header, ft.Divider(color=LINE, height=12), self.panel_body], spacing=0))
        self.toast_text = ft.Text("", size=13, color=TEXT, text_align=ft.TextAlign.CENTER)
        self.toast = ft.Container(visible=False, height=44, bgcolor="#2E2E35", border_radius=12,
            border=ft.Border.all(1, LINE), alignment=ft.Alignment.CENTER,
            padding=ft.Padding.symmetric(horizontal=16), content=self.toast_text)
        # Lunoir's wheel OSDs (.vol-toast, .zoom-toast): icon, volume bar, number
        self.osd_icon = ft.Icon(ft.Icons.VOLUME_UP_ROUNDED, size=20, color=TEXT)
        self.osd_fill = ft.Container(width=0, height=4, bgcolor="#D9D9DA", border_radius=2)
        self.osd_bar = ft.Container(width=120, height=4, bgcolor="#434346", border_radius=2,
                                    alignment=ft.Alignment.CENTER_LEFT, content=self.osd_fill)
        self.osd_text = ft.Text("", size=13, weight=ft.FontWeight.W_500, color=TEXT)
        self.osd_number = ft.Container(width=30, alignment=ft.Alignment.CENTER_RIGHT, content=self.osd_text)
        self.osd_row = ft.Row([self.osd_icon, self.osd_bar, self.osd_number], spacing=10, tight=True)
        self.osd = ft.Container(visible=False, width=OSD_WIDTHS["volume"], height=OSD_HEIGHT, bgcolor="#1A1A1E",
            border_radius=8, padding=ft.Padding.symmetric(horizontal=14), content=self.osd_row)
        # Full-window backdrop; flipping its colour makes Flutter repaint everything.
        self.backdrop = ft.Container(left=0, top=0, right=0, bottom=0, bgcolor="#17171C")
        self.root = ft.Stack([self.backdrop, self.home, self.video_area, self.header,
                              self.home_entries, self.transport, self.panel, self.toast, self.osd], expand=True)
        self.page.add(self.root)
        self.fill_panel()
        self.update_transport()
        self.layout()

    def home_content(self) -> ft.Column:
        t = self.t
        if self.url_mode:
            self.url_field = ft.TextField(hint_text=t("empty.urlPlaceholder"), width=420, autofocus=True,
                border_radius=12, on_submit=self.submit_url, dense=True)
            self.ua_field = ft.TextField(label=t("url.userAgent"), width=420, dense=True, visible=False)
            async def advanced(_):
                self.ua_field.visible = not self.ua_field.visible
                self.page.update()
            cta = [
                ft.Row([self.url_field, ft.IconButton(ft.Icons.PLAY_ARROW_ROUNDED, tooltip=t("empty.urlPlay"),
                        on_click=self.submit_url)], alignment=ft.MainAxisAlignment.CENTER, tight=True),
                ft.TextButton(t("url.advanced"), on_click=advanced), self.ua_field,
                ft.Text(t("empty.urlBack"), size=11, color="#6E6E79"),
            ]
        else:
            button = ft.Container(width=180, height=44, border_radius=12, bgcolor="#38383E",
                alignment=ft.Alignment.CENTER, content=ft.Row([
                    ft.Icon(ft.Icons.FILE_UPLOAD_OUTLINED, size=17, color=TEXT),
                    ft.Text(t("empty.openFile"), color=TEXT, size=14),
                ], tight=True, spacing=8))
            cta = [ft.GestureDetector(button, mouse_cursor=ft.MouseCursor.CLICK,
                                      on_tap=self.open_files, on_double_tap=self.open_folder),
                   ft.Text(t("empty.hint"), size=11, color="#6E6E79")]
        return ft.Column([
            ft.Image(src="logo.png", width=104, height=104),
            ft.Image(src="Lunoir.png", width=232, height=68, color=TEXT),
            ft.Container(height=18), *cta,
        ], horizontal_alignment=ft.CrossAxisAlignment.CENTER, alignment=ft.MainAxisAlignment.CENTER,
           spacing=12, tight=True)

    # ------------------------------------------------------------------ layout
    def floating(self) -> bool:
        return self.settings.get("oscStyle") != "docked"

    def controls_shown(self) -> bool:
        return self.has_media and (not self.floating() or self.revealed or bool(self.panel_mode) or self.dragging)

    def layout(self) -> None:
        width, height = float(self.page.width or 1120), float(self.page.height or 760)
        full = bool(self.page.window.full_screen)
        top = 0 if full else HEADER
        panel_open = bool(self.panel_mode)
        available = width - (PANEL_WIDTH + 32 if panel_open else 0)
        if self.floating():
            video = (0, top, width, height - top)
        else:
            video = (16, top + 16, max(1, available - 32), max(1, height - top - 16 - TRANSPORT_HEIGHT - 36))
        self.header.visible = not full
        self.home.visible = self.home_entries.visible = not self.has_media
        self.home.top = top
        self.video_area.visible = self.has_media
        self.video_area.left, self.video_area.top, self.video_area.width, self.video_area.height = video
        self.transport.visible = self.controls_shown()
        self.transport.width = max(300, min(840, available - 40))
        self.transport.left = (available - self.transport.width) / 2
        self.panel.visible = panel_open
        self.panel.top, self.panel.bottom = top + 16, 16
        self.toast.width = min(460, width - 40)
        self.toast.left, self.toast.top = (width - self.toast.width) / 2, top + 16
        # 88px off the bottom like Lunoir, or just above the pill when it shows
        self.osd.left = (available - self.osd.width) / 2
        self.osd.top = (height - 20 - TRANSPORT_HEIGHT - 12 if self.transport.visible else height - 88) - OSD_HEIGHT
        holes = []
        if self.transport.visible:
            holes.append((self.transport.left, height - 20 - TRANSPORT_HEIGHT, self.transport.width, TRANSPORT_HEIGHT, 24))
        if self.panel.visible:
            holes.append((width - 16 - PANEL_WIDTH, top + 16, PANEL_WIDTH, height - top - 32, 18))
        if self.toast.visible:
            holes.append((self.toast.left, self.toast.top, self.toast.width, 44, 12))
        if self.osd.visible:
            holes.append((self.osd.left, self.osd.top, self.osd.width, OSD_HEIGHT, 8))
        if self.surface:
            moved = self.surface.layout(*video, width)
            if self.surface.set_holes(holes) or moved:
                self.schedule_repaint()
            self.surface.show(self.has_media and not self.dialog_open)

    def schedule_repaint(self) -> None:
        """A newly cut hole shows grey until Flutter repaints that area: Flutter only
        re-presents what changed in a frame (the clock, a hovered item), so the exposed
        rectangle stays stale. Flipping the backdrop between two shades no one
        can tell apart damages the whole window, which repaints every hole. (Flipping
        page.bgcolor instead rebuilds Flet's whole app and hung the session.)"""
        if self.repaint_task and not self.repaint_task.done():
            self.repaint_task.cancel()
        async def repaint():
            for delay in (0.03, 0.12, 0.3):
                await asyncio.sleep(delay)
                if self.closed:
                    return
                backdrop = self.backdrop
                backdrop.bgcolor = "#17171D" if backdrop.bgcolor == "#17171C" else "#17171C"
                backdrop.update()
        try:
            self.repaint_task = asyncio.get_running_loop().create_task(repaint())
        except RuntimeError:
            self.repaint_task = None

    def refresh(self) -> None:
        self.layout()
        self.page.update()

    # ---------------------------------------------------------------- startup
    async def start(self) -> None:
        try:
            for _ in range(100):
                try:
                    self.surface = NativeVideo(self.caption)
                    break
                except RuntimeError:
                    await asyncio.sleep(0.05)
            else:
                raise RuntimeError("Could not find Flet's desktop window.")
            # Flet's client (flet.exe) outlives a killed Python otherwise, stuck on "Working..."
            tie_to_this_process(win32process.GetWindowThreadProcessId(self.surface.parent)[1])
            self.layout()
            await self.backend.start(self.surface.hwnd)
            # ytdl_hook's errors carry yt-dlp's reason (Lunoir reads them from stderr)
            await self.try_command("request_log_messages", "error")
            os.makedirs(options.screenshot_dir(self.settings), exist_ok=True)
            for name, value in options.startup_properties(self.settings):
                await self.try_set(name, value)
            await self.try_set("screenshot-template", "%F_%wH-%wM-%wS")
            self.ready = True
            loop = asyncio.get_running_loop()
            def from_thread(paths):
                if not self.closed and not loop.is_closed():
                    asyncio.run_coroutine_threadsafe(self.open_paths(paths), loop)
            def second_launch(paths):
                # Lunoir's second-instance handler; that process raises the window
                from_thread(paths)
                return self.surface.parent
            self.drop = DropTarget(self.surface.parent, from_thread)
            self.thumbs = Thumbnails(self.surface.parent)
            if self.instance:
                self.instance.serve(second_launch)
            await self.open_paths(self.startup)
            await self.event_loop()
        except Exception as error:
            log.exception("playback loop stopped")
            if not self.closed:
                self.notify(str(error))
        finally:
            if not self.closed:
                await self.backend.close()

    async def try_set(self, name, value) -> None:
        try:
            await self.backend.set(name, value)
        except (MpvError, OSError, asyncio.TimeoutError):
            pass  # an unsupported option in this libmpv build must not stop startup

    # ------------------------------------------------------------- event loop
    async def event_loop(self) -> None:
        while not self.closed:
            changed = False
            if self.surface:
                self.surface.pump()
            while not self.backend.events.empty():
                changed |= await self.handle_event(self.backend.events.get_nowait())
                if not self.ready:
                    return
            changed |= self.watch_pointer()
            if changed:
                self.update_transport()
                self.layout()
                self.page.update()
            if self.current and time.monotonic() - self.last_saved > 5:
                self.persist()
            await asyncio.sleep(0.05)

    async def handle_event(self, event: dict) -> bool:
        kind = event.get("event")
        if kind == "property-change":
            return await self.on_property(event["name"], event.get("data"))
        if kind == "file-loaded":
            await self.on_file_loaded()
        elif kind == "playback-restart" and self.pending_resume:
            self.notify(self.t("main.resumed", time=self.pending_resume))
            self.pending_resume = ""
        elif kind == "start-file":
            self.subtitle_revision += 1
            self.ytdl_error = ""
        elif kind == "log-message" and event.get("prefix") == "ytdl_hook":
            self.ytdl_error = ytdl.error_text(event.get("text") or "") or self.ytdl_error
        elif kind == "end-file":
            self.subtitle_revision += 1
            if event.get("reason") == "error":
                # yt-dlp's own words (members-only, DRM, unavailable) say more than "couldn't load"
                why, self.ytdl_error = self.ytdl_error, ""
                self.notify(why or self.t("main.loadFailed"))
                if why and ytdl.OUTDATED.search(why):
                    asyncio.create_task(self.refresh_ytdl())
        elif kind == "backend-error":
            self.ready = False
            self.notify(event["error"])
        return False

    async def on_property(self, name: str, data) -> bool:
        if name == "pause" and data is False and time.monotonic() < self.stepping_until:
            return False  # frame-step briefly unpauses; keep the button steady
        self.properties[name] = data
        if name in ("track-list", "aid", "sid") and self.panel_mode == "tracks":
            self.fill_panel()
        elif name in ("chapter-list", "chapter") and self.panel_mode in ("chapters", "tracks", "menu"):
            self.fill_panel()
        elif name in ("ab-loop-a", "ab-loop-b", "speed") and self.panel_mode == "menu":
            self.fill_panel()
        elif name == "eof-reached" and data is True:
            await self.advance(1, ended=True)
        elif name == "media-title" and isinstance(data, str) and data and 0 <= self.index < len(self.queue) \
                and is_url(self.queue[self.index].path) and self.source_type != "iptv" \
                and data != media_name(self.queue[self.index].path):
            # mpv falls back to the file name when a stream has no title; that must
            # not replace an #EXTINF title from a playlist
            self.queue[self.index].title = data
            if self.open_target_kind[1] == "url":
                self.profile.rename_recent(self.open_target_kind[0], data)
            if self.panel_mode == "playlist":
                self.fill_panel()
        elif name == "seekable" and data is True and self.recent_pending and self.open_target_kind[1] == "url":
            # a URL enters recents only once it proves to be a seekable VOD
            target = self.open_target_kind[0]
            entry = self.queue[self.index] if 0 <= self.index < len(self.queue) else None
            self.profile.recent(target, (entry and entry.title) or target, "url")
            self.recent_pending = False
        elif name in ("video-params/aspect", "video-params/w", "video-params/h"):
            await self.apply_aspect()
        elif name == "path":
            self.sync_thumb()
        return True

    def sync_thumb(self) -> None:
        """Lunoir's syncThumb: local files only, never IPTV."""
        if not self.thumbs:
            return
        path = self.properties.get("path")
        ok = bool(self.settings.get("seekPreview")) and isinstance(path, str) and bool(path) \
            and not is_url(path) and not path.lower().endswith(".edl") and self.source_type != "iptv"
        asyncio.create_task(self.thumbs.sync_file(path if ok else None))

    async def on_file_loaded(self) -> None:
        # every file starts at 1x (Lunoir resets zoom and pan per title)
        self.zoom, self.pan, self.pan_origin = 0.0, (0.0, 0.0), None
        for name in ("video-zoom", "video-pan-x", "video-pan-y"):
            await self.try_command("set_property", name, 0.0)
        key = self.resume_target
        audio = self.profile.audio.get(key) if key else None
        if audio and audio["type"] == "embedded":
            await self.try_command("set_property", "aid", audio["id"])
        elif audio and audio["type"] == "external" and os.path.exists(audio["path"]):
            await self.try_command("audio-add", audio["path"], "select")
        asyncio.create_task(self.restore_subtitles(self.subtitle_revision, key))
        if self.settings.get("resumePlayback") and key and self.can_resume():
            position = self.profile.positions.get(key)
            if isinstance(position, (int, float)) and position > 5:
                await self.try_command("seek", position, "absolute")
                self.pending_resume = fmt.clock(position)
        elif key and not self.can_resume():
            self.profile.clear_position(key)

    async def restore_subtitles(self, revision: int, key: str) -> None:
        """Lunoir's restoreSubtitleSelection: re-attach files, then reselect the choice."""
        saved = self.profile.subtitles.get(key)
        if not saved:
            return
        def stale():
            return revision != self.subtitle_revision or key != self.resume_target
        tracks = await self.try_command("get_property", "track-list") or []
        added = False
        for path in self.profile.subtitle_files(key):
            if stale():
                return
            if not is_url(path) and not os.path.exists(path):
                continue
            if any(t.get("type") == "sub" and t.get("external") and t.get("external-filename") == path for t in tracks):
                continue
            added |= await self.try_command("sub-add", path, "auto") is not None
        if stale():
            return
        if added:
            tracks = await self.try_command("get_property", "track-list") or []
        if saved["type"] == "none":
            await self.try_command("set_property", "sid", "no")
        elif saved["type"] == "embedded":
            if any(t.get("type") == "sub" and not t.get("external") and t.get("id") == saved["id"] for t in tracks):
                await self.try_command("set_property", "sid", saved["id"])
        else:
            track = next((t for t in tracks if t.get("type") == "sub" and t.get("external")
                          and t.get("external-filename") == saved["path"]), None)
            if track:
                await self.try_command("set_property", "sid", track["id"])

    # -------------------------------------------------------- pointer, hiding
    def watch_pointer(self) -> bool:
        """Cursor polling works whether or not Flutter sees the moves over the video."""
        if not self.surface:
            return False
        cursor = self.surface.cursor()
        changed = False
        if cursor is not None and self.last_cursor is not None and cursor != self.last_cursor:
            changed = self.activity()
        self.last_cursor = cursor
        self.update_preview(cursor)
        delay = max(1, float(self.settings.get("oscHideDelay") or 5))
        if self.revealed and self.has_media and self.floating() and not self.panel_mode and not self.dragging \
                and time.monotonic() - self.last_activity > delay and not self.over_transport(cursor):
            self.revealed = False
            changed = True
        return changed

    def seek_rect(self) -> tuple[float, float, float, float]:
        """The seek bar in page coordinates: the pill's 1px border and 22/12 padding,
        then the 18px readout row and 3px spacing (build_ui)."""
        top = float(self.page.height or 760) - 20 - TRANSPORT_HEIGHT + 1 + 12 + 18 + 3
        return self.transport.left + 23, top, self.transport.width - 46, 22

    def update_preview(self, cursor) -> None:
        """Lunoir's hoverPreview, from the polled cursor: Flutter's hover events don't
        reach us over the native video."""
        if not self.thumbs:
            return
        if cursor == self.preview_cursor and self.thumbs.visible:
            return
        self.preview_cursor = cursor
        duration = float(self.properties.get("duration") or 0)
        held = any(win32api.GetAsyncKeyState(key) & 0x8000 for key in (win32con.VK_LBUTTON, win32con.VK_RBUTTON))
        left, top, width, height = self.seek_rect()
        if cursor is None or not self.transport.visible or self.seek.disabled or duration <= 0 \
                or self.dragging or held or self.dialog_open or width <= 0 \
                or not (left - 2 <= cursor[0] <= left + width + 2 and top - 4 <= cursor[1] <= top + height + 4):
            self.thumbs.hide()
            return
        t = max(0.0, min(1.0, (cursor[0] - left) / width)) * duration
        self.thumbs.preview(t, cursor[0], float(self.page.height or 760) - 20 - TRANSPORT_HEIGHT,
                            float(self.page.width or 1120), not self.floating())

    def over_transport(self, cursor) -> bool:
        if cursor is None or not self.transport.visible:
            return False
        height = float(self.page.height or 760)
        x, y = cursor
        return self.transport.left <= x <= self.transport.left + self.transport.width and \
            height - 20 - TRANSPORT_HEIGHT <= y <= height - 20

    def activity(self) -> bool:
        self.last_activity = time.monotonic()
        if not self.revealed:
            self.revealed = True
            return True
        return False

    async def pointer_moved(self, _=None) -> None:
        if self.activity():
            self.refresh()

    async def video_tap(self, _=None) -> None:
        await self.command("cycle", "pause")

    async def video_secondary(self, _=None) -> None:
        # a right-click dismisses an open panel first, else opens the menu (Lunoir)
        await self.toggle_panel("" if self.panel_mode else "menu")

    async def video_double_tap(self, _=None) -> None:
        if win32api.GetAsyncKeyState(win32con.VK_CONTROL) & 0x8000:
            await self.set_zoom(0.0)
            self.show_osd("zoom", 100, 0.8)
        else:
            await self.fullscreen()

    async def video_wheel(self, event: ft.ScrollEvent) -> None:
        """Lunoir's onWheel: volume, or zoom with Ctrl; neither pops the OSC."""
        dy = event.scroll_delta.y if event.scroll_delta else 0
        if not dy:
            return
        up = dy < 0
        if win32api.GetAsyncKeyState(win32con.VK_CONTROL) & 0x8000:
            # log2 steps of 0.1 (about 7 %), clamped to roughly 0.25x - 8x
            await self.set_zoom(min(3.0, max(-2.0, self.zoom + (0.1 if up else -0.1))))
            self.show_osd("zoom", round(2 ** self.zoom * 100), 1.0)
            return
        volume = round(min(150, max(0, float(self.properties.get("volume") or 0) + (5 if up else -5))))
        self.properties["volume"] = volume  # quick ticks build on this, not on mpv's echo
        await self.set_property("volume", volume)
        if not self.controls_shown():
            self.show_osd("volume", volume, 1.0)
        else:
            self.update_transport()
            self.page.update()

    async def set_zoom(self, zoom: float) -> None:
        if abs(zoom) < 0.01:  # back at 1x: re-centre the picture
            zoom, self.pan = 0.0, (0.0, 0.0)
            await self.set_property("video-pan-x", 0.0)
            await self.set_property("video-pan-y", 0.0)
        self.zoom = zoom
        await self.set_property("video-zoom", zoom)

    async def pan_start(self, event: ft.DragStartEvent) -> None:
        """Dragging pans the picture while zoomed in, paused for the drag (Lunoir)."""
        if self.zoom <= 0:
            return
        # handlers overlap: record the drag before awaiting, or a quick release that
        # runs during the await would not see it and leave the video paused
        self.pan_origin = (event.global_position.x, event.global_position.y, *self.pan)
        self.pan_was_playing = not self.properties.get("pause")
        if self.pan_was_playing:
            await self.set_property("pause", True)

    async def pan_update(self, event: ft.DragUpdateEvent) -> None:
        if not self.pan_origin:
            return
        x, y, pan_x, pan_y = self.pan_origin
        # Lunoir's scale: the cursor delta over half the surface times the zoom factor
        scale = 2 ** self.zoom
        half_w = max(1.0, float(self.video_area.width or 1) / 2)
        half_h = max(1.0, float(self.video_area.height or 1) / 2)
        self.pan = (pan_x + (event.global_position.x - x) / (half_w * scale),
                    pan_y + (event.global_position.y - y) / (half_h * scale))
        await self.set_property("video-pan-x", self.pan[0])
        await self.set_property("video-pan-y", self.pan[1])

    async def pan_end(self, _=None) -> None:
        resume = bool(self.pan_origin) and self.pan_was_playing
        self.pan_origin, self.pan_was_playing = None, False
        if resume:
            await self.set_property("pause", False)

    # -------------------------------------------------------------- transport
    def window_title(self) -> str:
        props = self.properties
        entry = self.queue[self.index] if 0 <= self.index < len(self.queue) else None
        if not entry:
            return "Lunoir"
        if self.source_type == "iptv":
            return entry.title or "Lunoir"
        if playlist.is_http(entry.path):
            base = props.get("media-title") or entry.title or "Lunoir"
            author = props.get("metadata/by-key/uploader")
            return f"{base} · {author}" if author else base
        return props.get("filename") or props.get("media-title") or media_name(entry.path)

    def is_live(self) -> bool:
        return self.source_type == "iptv" or (playlist.is_http(self.current)
                                              and self.properties.get("seekable") is False)

    def update_transport(self) -> None:
        t, props = self.t, self.properties
        paused = bool(props.get("pause"))
        self.play_button.icon = ft.Icons.PLAY_ARROW_ROUNDED if paused else ft.Icons.PAUSE_ROUNDED
        self.play_button.tooltip = t("osc.play") if paused else t("osc.pause")
        muted = bool(props.get("mute"))
        volume = max(0.0, min(150.0, float(props.get("volume") or 0)))
        self.mute_button.icon = ft.Icons.VOLUME_OFF_ROUNDED if muted or not volume else ft.Icons.VOLUME_UP_ROUNDED
        self.mute_button.tooltip = t("osc.unmute") if muted else t("osc.mute")
        duration = max(0.0, float(props.get("duration") or 0))
        position = max(0.0, float(props.get("time-pos") or 0))
        live = self.is_live()
        self.seek.disabled = live or duration <= 0
        self.seek.opacity = 0 if live else 1  # Lunoir shows no seek bar for live streams
        if not self.dragging:
            self.seek.value = min(1, position / duration) if duration else 0
        style = self.settings.get("timeFormat", "time")
        fps = props.get("container-fps")
        if live:
            self.time_text.value, self.duration_text.value = "● LIVE", ""
        elif style == "timecode":
            frame = fmt.current_frame(props.get("estimated-frame-number"), position, fps)
            self.time_text.value = fmt.timecode(frame, fps)
            self.duration_text.value = fmt.timecode(props.get("estimated-frame-count") or 0, fps)
        elif style == "frame":
            self.time_text.value = str(fmt.current_frame(props.get("estimated-frame-number"), position, fps))
            self.duration_text.value = str(int(props.get("estimated-frame-count") or 0))
        else:
            self.time_text.value, self.duration_text.value = fmt.clock(position), fmt.clock(duration)
        if not self.volume_dragging:
            self.volume.value = 0 if muted else volume  # Lunoir's range input: empty while muted
        badges = []
        if playlist.is_http(self.current) and props.get("video-params/h"):
            tier = fmt.resolution_tier(props.get("video-params/w"), props.get("video-params/h"))
            badges.append(f"{tier}{'' if self.source_type == 'iptv' else 'p'}")
        badges.append(fmt.hdr_label(props.get("video-params/gamma")))
        badges.append(fmt.audio_badge(props.get("audio-codec-name") or "", props.get("audio-params/channel-count")))
        a, b = props.get("ab-loop-a"), props.get("ab-loop-b")
        if isinstance(a, (int, float)):
            badges.append(f"A {fmt.clock(a)}" + (f" – B {fmt.clock(b)}" if isinstance(b, (int, float)) else ""))
        speed = props.get("speed") or 1
        if abs(speed - 1) > 0.01:
            badges.append(f"{speed:g}×")
        self.badges.value = "  ·  ".join(badge for badge in badges if badge)
        self.title.value = self.window_title()

    async def cycle_time_format(self, _=None) -> None:
        order = fmt.TIME_FORMATS
        current = self.settings.get("timeFormat", "time")
        self.profile.set("timeFormat", order[(order.index(current) + 1) % 3] if current in order else "time")
        self.update_transport()
        self.page.update()

    # --------------------------------------------------------------- commands
    async def command(self, *args):
        if not self.ready:
            self.notify("The playback backend is not ready.")
            return None
        try:
            return await self.backend.command(*args)
        except (MpvError, OSError, asyncio.TimeoutError) as error:
            self.notify(str(error) or "The playback command timed out.")
            return None

    async def run(self, *args) -> bool:
        """Like command(), but says whether it worked (a reply's data may be None)."""
        if not self.ready:
            self.notify("The playback backend is not ready.")
            return False
        try:
            await self.backend.command(*args)
            return True
        except (MpvError, OSError, asyncio.TimeoutError) as error:
            self.notify(str(error) or "The playback command timed out.")
            return False

    async def try_command(self, *args):
        """For best-effort restores: failures are expected and stay silent."""
        if not self.ready:
            return None
        try:
            result = await self.backend.command(*args)
            return True if result is None else result
        except (MpvError, OSError, asyncio.TimeoutError):
            return None

    async def set_property(self, name, value) -> None:
        await self.command("set_property", name, value)

    def can_resume(self) -> bool:
        return self.source_type != "iptv" and self.properties.get("seekable") is not False

    # ------------------------------------------------------------ opening media
    async def open_target(self, target: str, user_agent: str = "") -> None:
        """Lunoir's openMedia: route a path or URL to a queue, list or single item."""
        if not self.ready:
            return
        self.persist()
        self.source_ua = user_agent
        playlist_url = ytdl.is_playlist_url(target)
        kind = "list" if playlist.is_channel_list(target) or playlist_url else "url" if is_url(target) else "file"
        self.open_target_kind = (target, kind)
        self.recent_pending = False
        self.source_type, self.playlist_key = "queue", ""
        if kind == "file":
            self.profile.recent(target, media_name(target) or target, "file")
        elif kind == "url":
            self.recent_pending = True
        if playlist_url:
            await self.load_playlist_url(target)
            return
        if playlist.is_local_queue(target):
            await self.load_local_playlist(target)
            return
        if kind == "list":
            await self.load_channel_list(target)
            return
        if os.path.isdir(target):
            files = playlist.scan_folder(target)
            if not files:
                self.notify(self.t("main.noMedia"))
                return
            if len(files) > playlist.MAX_FOLDER_SCAN:
                self.notify(self.t("main.folderTruncated", count=len(files), max=playlist.MAX_FOLDER_SCAN))
                files = files[:playlist.MAX_FOLDER_SCAN]
            self.set_queue([Entry(path) for path in files])
            await self.play_index(0)
        elif is_url(target) or not self.settings.get("scanFolderIntoPlaylist"):
            self.set_queue([Entry(target)])
            await self.play_index(0)
        else:
            # "scan folder": queue the siblings and start on the opened file
            files = playlist.scan_folder(os.path.dirname(target))
            if not files or len(files) > playlist.MAX_FOLDER_SCAN:
                files = [target]
            norm = os.path.normcase(os.path.abspath(target))
            start = next((i for i, f in enumerate(files) if os.path.normcase(os.path.abspath(f)) == norm), 0)
            self.set_queue([Entry(path) for path in files])
            await self.play_index(start)

    async def open_paths(self, paths: list[str]) -> None:
        """Launch arguments, a second launch's arguments, or a drop. Lunoir opens only
        the first; several media files become the queue, as from the open dialog."""
        if not paths:
            return
        media = [path for path in paths if not is_url(path) and os.path.isfile(path)
                 and path.rsplit(".", 1)[-1].lower() in playlist.VIDEO_EXT]
        if len(paths) > 1 and len(media) == len(paths):
            await self.open_queue(paths)
        else:
            await self.open_target(paths[0])

    async def open_queue(self, paths: list[str]) -> None:
        if not self.ready or not paths:
            return
        self.persist()
        self.open_target_kind = (paths[0], "file")
        self.source_type, self.playlist_key, self.source_ua = "queue", "", ""
        self.profile.recent(paths[0], media_name(paths[0]), "file")
        self.set_queue([Entry(path) for path in paths])
        await self.play_index(0)

    def set_queue(self, entries: list[Entry]) -> None:
        self.queue = entries
        self.index = -1
        self.shuffle_history = []
        self.channel_query = ""

    async def load_local_playlist(self, source: str) -> None:
        try:
            entries = await asyncio.to_thread(playlist.parse_local_m3u, source)
        except OSError:
            entries = []
        if not entries:
            self.notify(self.t("main.playlistFailed"))
            return
        if all(playlist.is_http(entry.path) for entry in entries):
            await self.load_channel_list(source)  # a local IPTV list, not a media queue
            return
        self.set_queue(entries)
        self.playlist_key = "file:" + os.path.normcase(os.path.abspath(source))
        await self.play_index(self.resume_index())

    async def load_playlist_url(self, url: str) -> None:
        """Lunoir's loadPlaylistUrl: a YouTube-style playlist URL becomes the queue."""
        self.notify(self.t("main.loadingPlaylist"))
        if not await self.ensure_ytdl():
            return
        entries = await self.ytdl.playlist(url)
        if not entries:
            self.notify(self.t("main.playlistFailed"))
            return
        self.set_queue(entries)
        self.playlist_key = ytdl.playlist_key(url)
        await self.play_index(self.resume_index())

    def resume_index(self) -> int:
        """The queue's last-watched item, when resumePlaylistItem is on and it's still there."""
        if not self.settings.get("resumePlaylistItem"):
            return 0
        last = self.profile.playlist_items.get(self.playlist_key)
        return next((i for i, entry in enumerate(self.queue) if entry.path == last), 0)

    async def ensure_ytdl(self) -> str | None:
        """yt-dlp for a site URL, pointed to by ytdl_hook; fetched on first use."""
        if not self.ytdl.exe.is_file():
            self.notify(self.t("main.fetchingYtdl"))
        path = await self.ytdl.ensure()
        if path:
            await self.try_set("script-opts", "ytdl_hook-ytdl_path=" + path.replace("\\", "/"))
        else:
            self.notify(self.t("main.ytdlFailed"))
        return path

    async def refresh_ytdl(self, _=None) -> None:
        """Lunoir's refreshYtdl: the Settings button, or yt-dlp reporting itself outdated."""
        if self.ytdl_state == "working":
            return
        self.ytdl_state = "working"
        self.notify(self.t("main.fetchingYtdl"))
        self.refill_settings()
        path = await self.ytdl.refresh()
        self.ytdl_state = "done" if path else "error"
        if path:
            await self.try_set("script-opts", "ytdl_hook-ytdl_path=" + path.replace("\\", "/"))
            said = self.t("main.ytdlUpdated" if self.ytdl.replaced else "set.ytdl.done")
            self.notify(f"{said} · yt-dlp {self.ytdl.version}")
        else:
            self.notify(self.t("main.ytdlFailed"))
        self.refill_settings()

    def refill_settings(self) -> None:
        if self.panel_mode == "settings":
            self.fill_panel()
            self.refresh()

    def show_ytdl_version(self) -> None:
        """The General tab names the installed yt-dlp; running it to ask takes a moment."""
        if self.ytdl.version is None and not self.ytdl_version_task and self.ytdl.exe.is_file():
            async def read():
                await self.ytdl.read_version()
                self.ytdl_version_task = None
                self.refill_settings()
            self.ytdl_version_task = asyncio.create_task(read())

    async def load_channel_list(self, source: str) -> None:
        self.notify(self.t("main.loadingPlaylist"))
        try:
            text = await asyncio.to_thread(playlist.read_source, source, self.source_ua)
            channels = playlist.parse_channel_list(text)
        except (OSError, ValueError):
            channels = []
        saved = next((f for f in self.profile.favourites if f.get("target") == source), None)
        if len(channels) < 2 and saved and saved.get("channels"):
            # the source is down: fall back to the snapshot kept with the favourite
            channels = [Entry(c["url"], c.get("name", ""), c.get("group", "")) for c in saved["channels"]]
        if len(channels) < 2:
            self.set_queue([Entry(source)])  # not a channel list: play it as one item
            await self.play_index(0)
            return
        if saved:
            saved["channels"] = [{"name": c.title, "url": c.path, "group": c.group} for c in channels]
            self.profile.write("favourites.json", self.profile.favourites)
        self.set_queue(channels)
        self.source_type = "iptv"
        await self.play_index(0)

    async def play_index(self, index: int) -> None:
        skipped = 0
        while 0 <= index < len(self.queue) and not is_url(self.queue[index].path) \
                and not os.path.exists(self.queue[index].path):
            index += 1
            skipped += 1
        if not 0 <= index < len(self.queue):
            self.notify(self.t("main.noPlayable"))
            return
        if skipped:
            self.notify(self.t("main.skippedMissing"))
        self.persist()
        self.index = index
        entry = self.queue[index]
        self.current = self.resume_target = entry.path
        self.subtitle_revision += 1
        for name in ("time-pos", "duration", "filename", "media-title", "metadata/by-key/uploader",
                     "chapter-list", "track-list", "ab-loop-a", "ab-loop-b", "estimated-frame-number"):
            self.properties.pop(name, None)
        self.has_media = True
        self.revealed = True
        self.last_activity = time.monotonic()
        self.refresh()
        await self.try_set("user-agent", self.source_ua if self.source_type == "iptv" else "")
        if self.source_type == "iptv" and entry.title:
            await self.try_set("force-media-title", entry.title)
        else:
            await self.try_set("force-media-title", "")
        if ytdl.needs_ytdl(entry.path) and self.source_type != "iptv":
            # IPTV channels are direct streams that merely lack a media extension
            await self.ensure_ytdl()
            if not (0 <= self.index < len(self.queue) and self.queue[self.index] is entry):
                return  # another item was opened during the download
        await self.command("loadfile", entry.path, "replace")
        await self.set_property("pause", False)
        if self.playlist_key:
            self.profile.save_playlist_item(self.playlist_key, entry.path)
        self.fill_panel()
        self.update_transport()
        self.refresh()

    def next_index(self, step: int) -> int | None:
        count = len(self.queue)
        if self.shuffle and count > 1:
            if step < 0:
                return self.shuffle_history.pop() if self.shuffle_history else None
            self.shuffle_history.append(self.index)
            return random.choice([i for i in range(count) if i != self.index])
        index = self.index + step
        if self.repeat == "all":
            index %= count
        return index if 0 <= index < count else None

    async def advance(self, step: int, ended=False) -> None:
        if not self.queue:
            return
        if ended and self.repeat == "one":
            await self.command("seek", 0, "absolute")
            await self.set_property("pause", False)
            return
        index = self.next_index(step)
        if index is not None:
            await self.play_index(index)

    async def remove_item(self, index: int) -> None:
        if not 0 <= index < len(self.queue):
            return
        current = index == self.index
        del self.queue[index]
        self.shuffle_history = [i - (i > index) for i in self.shuffle_history if i != index]
        if index < self.index:
            self.index -= 1
        if not self.queue:
            await self.go_home()
            return
        if current:
            await self.play_index(min(index, len(self.queue) - 1))
        self.fill_panel()
        self.page.update()

    # ----------------------------------------------------------------- dialogs
    async def with_dialog(self, action):
        self.dialog_open = True
        self.layout()
        try:
            return await action()
        finally:
            self.dialog_open = False
            self.refresh()

    async def open_files(self, _=None) -> None:
        extensions = list(playlist.OPEN_EXT)
        files = await self.with_dialog(lambda: ft.FilePicker().pick_files(
            allow_multiple=True, dialog_title=self.t("dlg.openMedia"),
            file_type=ft.FilePickerFileType.CUSTOM, allowed_extensions=extensions))
        paths = [item.path for item in files or [] if item.path]
        if len(paths) == 1:
            await self.open_target(paths[0])
        elif paths:
            await self.open_queue(paths)

    async def open_folder(self, _=None) -> None:
        folder = await self.with_dialog(lambda: ft.FilePicker().get_directory_path(
            dialog_title=self.t("dlg.selectFolder")))
        if folder:
            await self.open_target(folder)

    async def add_files(self, _=None) -> None:
        files = await self.with_dialog(lambda: ft.FilePicker().pick_files(
            allow_multiple=True, dialog_title=self.t("dlg.addToPlaylist"),
            file_type=ft.FilePickerFileType.CUSTOM, allowed_extensions=list(playlist.VIDEO_EXT)))
        paths = [item.path for item in files or [] if item.path]
        if not paths:
            return
        if not self.queue:
            await self.open_queue(paths)
            return
        self.queue.extend(Entry(path) for path in paths)
        self.fill_panel()
        self.page.update()

    async def toggle_url_mode(self, _=None) -> None:
        self.url_mode = not self.url_mode
        self.home.content.content = self.home_content()
        self.page.update()

    async def submit_url(self, _=None) -> None:
        target = (self.url_field.value or "").strip()
        if target:
            await self.open_target(target, (self.ua_field.value or "").strip())

    async def open_url(self, _=None) -> None:
        self.dialog_open = True
        self.layout()
        field = ft.TextField(hint_text=self.t("empty.urlPlaceholder"), width=480, autofocus=True)
        agent = ft.TextField(label=self.t("url.userAgent"), width=480, dense=True)
        async def dismiss(_=None):
            if not self.dialog_open:
                return
            self.dialog_open = False
            self.page.pop_dialog()
            self.refresh()
        async def submit(_=None):
            target = (field.value or "").strip()
            if target:
                await dismiss()
                await self.open_target(target, (agent.value or "").strip())
        field.on_submit = submit
        self.page.show_dialog(ft.AlertDialog(modal=True, title=ft.Text(self.t("menu.openUrl")),
            content=ft.Column([field, agent], tight=True),
            actions=[ft.TextButton(self.t("common.close"), on_click=dismiss),
                     ft.Button(self.t("empty.urlPlay"), on_click=submit)],
            on_dismiss=dismiss))

    # ------------------------------------------------------------------ panels
    async def toggle_panel(self, mode: str) -> None:
        self.panel_mode = "" if self.panel_mode == mode else mode
        if self.panel_mode == "info":
            await panels.load_info(self)
        self.fill_panel()
        self.activity()
        self.refresh()

    async def show_panel(self, mode: str) -> None:
        self.panel_mode = mode
        self.fill_panel()
        self.refresh()

    def fill_panel(self) -> None:
        panels.fill(self)

    # ------------------------------------------------------------------ tracks
    async def select_audio(self, track_id: int) -> None:
        await self.set_property("aid", track_id)
        track = next((t for t in self.properties.get("track-list") or []
                      if t.get("type") == "audio" and t.get("id") == track_id), None)
        if track and track.get("external") and track.get("external-filename"):
            self.profile.save_audio(self.resume_target, {"type": "external", "path": track["external-filename"]})
        else:
            self.profile.save_audio(self.resume_target, {"type": "embedded", "id": track_id})

    async def select_subtitle(self, track_id) -> None:
        tracks = self.properties.get("track-list") or []
        track = next((t for t in tracks if t.get("type") == "sub" and t.get("id") == track_id), None)
        if track_id != "no" and not track:
            return
        self.subtitle_revision += 1
        await self.set_property("sid", track_id)
        if track_id == "no":
            self.profile.save_subtitle(self.resume_target, {"type": "none"})
        elif track.get("external") and track.get("external-filename"):
            self.profile.save_subtitle(self.resume_target, {"type": "external", "path": track["external-filename"]})
        else:
            self.profile.save_subtitle(self.resume_target, {"type": "embedded", "id": track_id})

    async def add_audio(self, _=None) -> None:
        files = await self.with_dialog(lambda: ft.FilePicker().pick_files(
            dialog_title=self.t("dlg.addAudio"), file_type=ft.FilePickerFileType.CUSTOM,
            allowed_extensions=list(playlist.AUDIO_EXT)))
        if files and files[0].path and await self.run("audio-add", files[0].path, "select"):
            self.profile.save_audio(self.resume_target, {"type": "external", "path": files[0].path})

    async def add_subtitle(self, _=None) -> None:
        key, revision = self.resume_target, self.subtitle_revision
        files = await self.with_dialog(lambda: ft.FilePicker().pick_files(
            dialog_title=self.t("dlg.addSubtitle"), file_type=ft.FilePickerFileType.CUSTOM,
            allowed_extensions=list(playlist.SUBTITLE_EXT)))
        if not files or not files[0].path or key != self.resume_target or revision != self.subtitle_revision:
            return
        self.subtitle_revision += 1
        if await self.run("sub-add", files[0].path, "select"):
            self.profile.save_subtitle(key, {"type": "external", "path": files[0].path})

    # ------------------------------------------------------------ menu actions
    async def screenshot(self, _=None) -> None:
        os.makedirs(options.screenshot_dir(self.settings), exist_ok=True)
        name = self.properties.get("filename") or media_name(self.current)
        await self.set_property("screenshot-template", fmt.screenshot_template(name, self.properties.get("time-pos")))
        mode = () if self.settings.get("screenshotSubs") else ("video",)
        if await self.run("screenshot", *mode):
            self.notify(self.t("toast.screenshotSaved"))

    async def set_speed(self, value: float) -> None:
        await self.set_property("speed", value)
        self.notify(self.t("toast.speedNormal") if value == 1 else self.t("toast.speed", v=f"{value:g}"))

    async def set_aspect(self, key: str) -> None:
        self.aspect = key
        await self.apply_aspect()
        self.fill_panel()
        self.page.update()

    async def apply_aspect(self) -> None:
        """Lunoir's applyAspect: centre-cut to the chosen frame; only Stretch distorts."""
        if not self.ready:
            return
        target = ASPECT_TARGETS.get(self.aspect)
        source = self.properties.get("video-params/aspect") or 0
        width, height = self.properties.get("video-params/w") or 0, self.properties.get("video-params/h") or 0
        crop = ""
        if target and source > 0 and width > 0 and height > 0:
            crop_w = round(width * target / source) if target < source else width
            crop_h = round(height * source / target) if target > source else height
            crop = f"{crop_w}x{crop_h}"
        applied = (self.aspect != "stretch", crop)
        if applied != self.applied_aspect:  # the video-params arrive as a burst
            self.applied_aspect = applied
            await self.try_set("keepaspect", applied[0])
            await self.try_set("video-crop", crop)

    def favourite_target(self, target: str) -> None:
        """Lunoir's favouriteTarget: what's open keeps its kind, channels and user agent;
        anything else (a recents row) is classified from the target."""
        if self.profile.is_favourite(target):
            return
        extra = {}
        if target == self.open_target_kind[0]:
            kind = self.open_target_kind[1]
            if kind == "list" and self.source_type == "iptv":
                extra["channels"] = [{"name": e.title, "url": e.path, "group": e.group} for e in self.queue]
            elif kind == "list":
                kind = "url"  # a list that played as one item, or a playlist URL (expands again on open)
            if self.source_ua:
                extra["userAgent"] = self.source_ua
            name = media_name(target) if kind == "list" else self.window_title()
        else:
            kind = "list" if playlist.is_channel_list(target) else "url" if is_url(target) else "file"
            recent = next((r for r in self.profile.recents if r.get("target") == target), None)
            name = (recent and recent.get("name")) or (target if kind == "url" else media_name(target) or target)
        self.profile.toggle_favourite(target, name, kind, **extra)

    async def favourite_current(self, _=None) -> None:
        """The menu's Save: add only; deleting is the library's job (Lunoir)."""
        target = self.open_target_kind[0]
        if not target:
            return
        if self.profile.is_favourite(target):
            self.notify(self.t("toast.alreadyFav"))
        else:
            self.favourite_target(target)
            self.notify(self.t("toast.favourited"))
        self.fill_panel()
        self.page.update()

    async def favourite_recent(self, target: str) -> None:
        self.favourite_target(target)
        self.fill_panel()
        self.page.update()

    def collection_key(self) -> str:
        """The list source for IPTV, else the queue's fingerprint (Lunoir's queueKey)."""
        if self.source_type == "iptv":
            return self.open_target_kind[0]
        return queue_key([entry.path for entry in self.queue]) if self.queue else ""

    def queue_name(self) -> str:
        """A folder queue is named after the folder, else after its first item."""
        first = self.queue[0] if self.queue else None
        if not first:
            return "Playlist"
        base = first.title or media_name(first.path)
        folder = "" if is_url(first.path) else os.path.basename(os.path.dirname(first.path))
        return folder if len(self.queue) > 1 and folder else base

    async def save_collection(self, _=None) -> None:
        """Lunoir's saveCollection, the playlist panel's button: save or unsave the IPTV
        source, or a snapshot of the queue as a 'playlist' favourite."""
        key = self.collection_key()
        if not key:
            return
        if self.profile.is_favourite(key):
            self.profile.toggle_favourite(key, "")
            saved = False
        elif self.source_type == "iptv":
            self.favourite_target(key)
            saved = True
        else:
            saved = self.profile.toggle_favourite(key, self.queue_name(), "playlist",
                items=[{"path": e.path, "name": e.title or media_name(e.path)} for e in self.queue])
        self.notify(self.t("toast.favourited" if saved else "toast.unfavourited"))
        self.fill_panel()
        self.page.update()

    async def open_saved(self, entry: dict) -> None:
        items = entry.get("items") or []
        if entry.get("kind") != "playlist" or not items:
            await self.open_target(entry["target"], entry.get("userAgent", ""))
            return
        # a saved playlist plays its snapshot (Lunoir's loadFavCollection)
        if not self.ready:
            return
        self.persist()
        self.open_target_kind = (entry["target"], "playlist")
        self.source_type, self.source_ua, self.recent_pending = "queue", "", False
        self.set_queue([Entry(item["path"], item.get("name", "")) for item in items if item.get("path")])
        self.playlist_key = entry["target"]
        await self.play_index(self.resume_index())

    async def go_home(self, _=None) -> None:
        self.persist()
        await self.command("stop")
        self.current = self.resume_target = ""
        self.set_queue([])
        self.source_type, self.playlist_key = "queue", ""
        self.open_target_kind = ("", "")
        self.has_media, self.panel_mode = False, ""
        self.properties = {key: value for key, value in self.properties.items() if key in ("volume", "mute")}
        self.update_transport()
        self.refresh()

    async def cycle_repeat(self, _=None) -> None:
        self.repeat = {"off": "all", "all": "one", "one": "off"}[self.repeat]
        self.style_repeat_shuffle()
        self.fill_panel()
        self.page.update()

    async def toggle_shuffle(self, _=None) -> None:
        self.shuffle = not self.shuffle
        self.shuffle_history = []
        self.style_repeat_shuffle()
        self.fill_panel()
        self.page.update()

    def style_repeat_shuffle(self) -> None:
        self.repeat_button.icon = ft.Icons.REPEAT_ONE_ROUNDED if self.repeat == "one" else ft.Icons.REPEAT_ROUNDED
        self.repeat_button.icon_color = TEXT if self.repeat != "off" else DIM
        self.repeat_button.tooltip = self.t(f"panel.repeat.{self.repeat}")
        self.shuffle_button.icon_color = TEXT if self.shuffle else DIM
        self.shuffle_button.tooltip = self.t("panel.shuffle.on" if self.shuffle else "panel.shuffle.off")

    async def seek_start(self, _=None) -> None:
        self.dragging = True

    async def seek_end(self, event) -> None:
        await self.command("seek", float(event.data) * float(self.properties.get("duration") or 0), "absolute+exact")
        self.dragging = False
        self.activity()

    # A slider's value comes from event.data: control.value is also what update_transport
    # writes mpv's volume to, so reading it here would set the old volume straight back.
    async def volume_start(self, _=None) -> None:
        self.volume_dragging = True

    async def volume_change(self, event) -> None:
        await self.slide_volume(event.data)

    async def volume_end(self, event) -> None:
        await self.slide_volume(event.data)
        self.volume_dragging = False
        self.update_transport()
        self.page.update()

    async def slide_volume(self, value) -> None:
        """Lunoir's setVolume, live as the thumb moves. Deviation: moving it unmutes,
        because a muted slider sits at 0 and would otherwise just snap back there."""
        volume = max(0, min(150, round(float(value))))
        if self.properties.get("mute"):
            self.properties["mute"] = False
            await self.set_property("mute", False)
        if volume != self.properties.get("volume"):
            self.properties["volume"] = volume
            await self.set_property("volume", volume)

    async def frame_step(self, forward: bool) -> None:
        self.stepping_until = time.monotonic() + 0.26
        await self.command("frame-step" if forward else "frame-back-step")
        async def resync():
            await asyncio.sleep(0.3)
            if time.monotonic() >= self.stepping_until:
                paused = await self.try_command("get_property", "pause")
                self.properties["pause"] = paused is True
                self.update_transport()
                self.page.update()
        asyncio.create_task(resync())

    # ---------------------------------------------------------------- settings
    async def change_setting(self, key: str, value) -> None:
        self.profile.set(key, value)
        for name, mpv_value in options.properties_for(key, self.settings):
            if self.ready:
                await self.try_set(name, mpv_value)
        if key == "screenshotDir":
            os.makedirs(options.screenshot_dir(self.settings), exist_ok=True)
        if key == "uiLanguage":
            self.t.set_language(value)
            self.build_ui()
            self.page.update()
        elif key == "oscStyle":
            self.revealed = True
            self.refresh()
        elif key == "seekPreview":
            self.sync_thumb()

    # ------------------------------------------------------------ window, keys
    async def fullscreen(self, _=None) -> None:
        self.page.window.full_screen = not self.page.window.full_screen
        self.refresh()

    async def minimize(self, _=None) -> None:
        self.page.window.minimized = True
        self.page.update()

    async def maximize(self, _=None) -> None:
        self.page.window.maximized = not self.page.window.maximized
        self.page.update()

    async def resize(self, _=None) -> None:
        self.refresh()

    async def keyboard(self, event: ft.KeyboardEvent) -> None:
        """Lunoir's useShortcuts."""
        if self.dialog_open:
            return
        key = event.key.upper()
        if key == "F9" and SNAPSHOTS:
            # developer aid: Flutter's own rendering, independent of screen capture
            image = await self.page.take_screenshot()
            Path(SNAPSHOTS, f"lunoir-{time.strftime('%H%M%S')}.png").write_bytes(image)
            return
        if event.ctrl and key == "O":
            await self.open_files()
            return
        if key in ("F", "F11"):
            await self.fullscreen()
            return
        if key == "ESCAPE":
            if self.page.window.full_screen:
                await self.fullscreen()
            return
        if not self.has_media:
            return
        if key in (" ", "SPACE", "K"):
            await self.command("cycle", "pause")
            return  # pausing does not pop the controls
        if key == "I":
            await self.toggle_panel("info")
            return
        if key in ("ARROW LEFT", "ARROW RIGHT"):
            forward = key.endswith("RIGHT")
            now = time.monotonic()
            held = now - self.last_arrow < 0.2
            self.last_arrow = now
            if not held or not self.arrow_mode:
                # decided once per hold: a frame-step briefly unpauses
                self.arrow_mode = "step" if self.properties.get("pause") else "seek"
            if self.arrow_mode == "step":
                if not held or now - self.last_step >= FRAME_STEP_SECONDS:
                    self.last_step = now
                    await self.frame_step(forward)
                return
            await self.command("seek", 5 if forward else -5, "relative")
        elif key in ("ARROW UP", "ARROW DOWN"):
            volume = float(self.properties.get("volume") or 0) + (5 if key.endswith("UP") else -5)
            await self.set_property("volume", max(0, min(150, int(volume + 0.5))))  # Math.round
        elif key == "M":
            await self.command("cycle", "mute")
        elif key in (".", ">"):
            await self.advance(1)
        elif key in (",", "<"):
            await self.advance(-1)
        else:
            return
        if self.activity():
            self.refresh()

    def persist(self) -> None:
        self.last_saved = time.monotonic()
        try:
            self.profile.save_position(self.current, float(self.properties.get("time-pos") or 0),
                float(self.properties.get("duration") or 0), self.can_resume())
            volume = self.properties.get("volume")
            if isinstance(volume, (int, float)) and self.settings.get("volume") != volume:
                self.profile.set("volume", volume)
        except OSError as error:
            self.notify(f"Could not save playback state: {error}")

    def notify(self, text: str) -> None:
        self.toast_text.value = text
        self.toast.visible = True
        if self.toast_task:
            self.toast_task.cancel()
        async def hide():
            await asyncio.sleep(3.2)
            self.toast.visible = False
            self.refresh()
        try:
            self.toast_task = asyncio.get_running_loop().create_task(hide())
        except RuntimeError:
            self.toast_task = None
        self.refresh()

    def show_osd(self, kind: str, value: int, seconds: float) -> None:
        """Lunoir's .vol-toast (icon, bar, number) or .zoom-toast (icon, percent)."""
        zoom = kind == "zoom"
        if zoom:
            self.osd_icon.icon = ft.Icons.ZOOM_IN_ROUNDED if value > 100 else ft.Icons.ZOOM_OUT_ROUNDED
        else:
            self.osd_icon.icon = ft.Icons.VOLUME_OFF_ROUNDED if value == 0 else ft.Icons.VOLUME_UP_ROUNDED
        self.osd_icon.size = 16 if zoom else 20
        self.osd_bar.visible = not zoom
        self.osd_fill.width = 1.2 * min(100, value)
        self.osd_number.width = 42 if zoom else 30
        self.osd_text.value = f"{value}%" if zoom else str(value)
        self.osd_row.spacing = 8 if zoom else 10
        self.osd.width = OSD_WIDTHS[kind]
        self.osd.visible = True
        if self.osd_task:
            self.osd_task.cancel()
        async def hide():
            await asyncio.sleep(seconds)
            self.osd.visible = False
            self.refresh()
        self.osd_task = asyncio.get_running_loop().create_task(hide())
        self.refresh()

    async def window_event(self, event) -> None:
        if event.type == ft.WindowEventType.CLOSE:
            await self.shutdown()
        elif event.type in (ft.WindowEventType.RESIZED, ft.WindowEventType.MAXIMIZE,
                            ft.WindowEventType.UNMAXIMIZE, ft.WindowEventType.RESTORE,
                            ft.WindowEventType.ENTER_FULL_SCREEN, ft.WindowEventType.LEAVE_FULL_SCREEN):
            self.refresh()

    async def disconnect(self, _=None) -> None:
        await self.shutdown(destroy=False)

    def save_window(self) -> None:
        window = self.page.window
        if not self.settings.get("rememberWindow") or window.full_screen or window.maximized or window.minimized:
            return
        if None not in (window.left, window.top, window.width, window.height):
            self.profile.set("windowBounds", {"x": round(window.left), "y": round(window.top),
                                              "width": round(window.width), "height": round(window.height)})

    async def shutdown(self, _=None, destroy=True) -> None:
        if self.closed:
            return
        self.persist()
        self.save_window()
        self.closed, self.ready = True, False
        if self.thumbs:
            await self.thumbs.close()
        await self.backend.close()
        if self.drop:
            self.drop.close()
        if self.surface:
            self.surface.close()
        if destroy:
            await self.page.window.destroy()


async def main(page: ft.Page, startup: list[str] | None = None, instance: Instance | None = None) -> None:
    app = Lunoir(page, startup or [], instance)
    page.run_task(app.start)
