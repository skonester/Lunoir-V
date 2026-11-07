"""Side panel contents: Lunoir's RightPanel, Library, SettingsPanel, menu and info.

Each builder fills app.panel_header and app.panel_body. The panel is a region hole in
the native video, so anything drawn here stays visible over the picture.
"""
from __future__ import annotations

import os
import re

import flet as ft

from . import formatting as fmt
from .i18n import LANG_OPTIONS
from .playlist import media_name

TEXT = "#EEEEF0"
DIM = "#92929C"
FAINT = "#6E6E79"
LINE = "#393940"
ACTIVE = "#3A3A42"
SPEEDS = (0.5, 0.75, 1, 1.25, 1.5, 2)

LANG_KEYS = {"eng": "english", "en": "english", "chi": "chinese", "zho": "chinese", "zh": "chinese",
             "jpn": "japanese", "ja": "japanese", "kor": "korean", "ko": "korean", "fre": "french",
             "fra": "french", "fr": "french", "ger": "german", "deu": "german", "de": "german",
             "spa": "spanish", "es": "spanish", "ita": "italian", "it": "italian", "rus": "russian",
             "ru": "russian", "por": "portuguese", "pt": "portuguese"}
AUDIO_FORMATS = {"truehd": "Dolby TrueHD", "eac3": "Dolby Digital Plus", "ac3": "Dolby Digital",
                 "dts": "DTS", "aac": "AAC", "flac": "FLAC", "alac": "ALAC", "opus": "Opus",
                 "vorbis": "Vorbis", "mp3": "MP3"}
SUB_FORMATS = {"subrip": "SRT", "srt": "SRT", "ass": "ASS", "ssa": "SSA", "webvtt": "VTT",
               "hdmv_pgs_subtitle": "PGS", "pgssub": "PGS", "dvd_subtitle": "VobSub",
               "dvdsub": "VobSub", "vobsub": "VobSub", "dvb_subtitle": "DVB", "dvbsub": "DVB",
               "dvb_teletext": "Teletext", "mov_text": "TX3G"}
SUB_FONTS = [("Microsoft YaHei", "微软雅黑 (Microsoft YaHei)"), ("Microsoft JhengHei", "微軟正黑體 (JhengHei)"),
             ("SimHei", "黑体 (SimHei)"), ("Source Han Sans SC", "思源黑体 (Source Han Sans)"),
             ("Noto Sans CJK SC", "Noto Sans CJK"), ("Yu Gothic UI", "游ゴシック (Yu Gothic)"),
             ("Segoe UI", "Segoe UI")]
BROWSERS = [("edge", "Edge"), ("chrome", "Chrome"), ("firefox", "Firefox"), ("brave", "Brave"), ("opera", "Opera")]
CODEPAGES = [("utf-8", "UTF-8"), ("cp1251", "Windows-1251"), ("cp1252", "Windows-1252"),
             ("cp1250", "Windows-1250"), ("koi8-r", "KOI8-R"), ("cp866", "CP866"),
             ("gb18030", "GB18030"), ("big5", "Big5"), ("shift_jis", "Shift_JIS"), ("cp949", "Windows-949")]
TRACK_LANGS = [("eng", "english"), ("chi,zho", "chinese"), ("jpn", "japanese"), ("kor", "korean"),
               ("fre", "french"), ("ger", "german"), ("spa", "spanish"), ("ita", "italian"),
               ("rus", "russian"), ("por", "portuguese")]


# ------------------------------------------------------------------- helpers
def section(text: str) -> ft.Control:
    return ft.Container(ft.Text(text.upper(), size=11, color=DIM, weight=ft.FontWeight.W_600),
                        padding=ft.Padding.only(top=10, bottom=2))


def empty(text: str) -> ft.Control:
    return ft.Container(ft.Text(text, size=13, color=DIM), padding=ft.Padding.symmetric(vertical=8))


def item(app, title: str, on_click, *, active=False, leading=None, trailing=None, subtitle=None) -> ft.Control:
    row = [ft.Container(leading, width=24, alignment=ft.Alignment.CENTER) if leading is not None else None,
           ft.Column([ft.Text(title, size=13, color=TEXT, max_lines=2, overflow=ft.TextOverflow.ELLIPSIS),
                      *( [ft.Text(subtitle, size=11, color=DIM, max_lines=1, overflow=ft.TextOverflow.ELLIPSIS)]
                         if subtitle else [])], spacing=1, expand=True),
           trailing]
    return ft.Container(ft.Row([c for c in row if c is not None], spacing=8),
                        bgcolor=ACTIVE if active else None, border_radius=10,
                        padding=ft.Padding.symmetric(horizontal=8, vertical=7),
                        on_click=on_click, ink=True)


def tabs(app, choices: list[tuple[str, str]], current: str, on_pick) -> ft.Control:
    buttons = []
    for value, label in choices:
        selected = value == current
        buttons.append(ft.Container(
            ft.Text(label, size=13, color=TEXT if selected else DIM,
                    weight=ft.FontWeight.W_600 if selected else ft.FontWeight.NORMAL),
            padding=ft.Padding.symmetric(horizontal=9, vertical=6), border_radius=8,
            bgcolor=ACTIVE if selected else None, on_click=app.callback(on_pick, value)))
    return ft.Row(buttons, spacing=2, run_spacing=2, wrap=True, expand=True)


def header(app, content: ft.Control) -> None:
    app.panel_header.controls = [content, ft.IconButton(ft.Icons.KEYBOARD_DOUBLE_ARROW_RIGHT_ROUNDED,
        tooltip=app.t("common.collapse"), icon_size=18, icon_color=DIM,
        on_click=app.callback(app.toggle_panel, ""))]


def title(text: str) -> ft.Control:
    return ft.Text(text, size=17, weight=ft.FontWeight.W_600, color=TEXT, expand=True,
                   max_lines=1, overflow=ft.TextOverflow.ELLIPSIS)


def lang_label(app, raw) -> str:
    if not raw:
        return ""
    parts = [p for p in re.split(r"[-_,\s]+", str(raw).lower()) if p]
    key = LANG_KEYS.get(parts[0]) if parts else None
    return app.t(f"opt.lang.{key}") if key else str(raw)


def looks_like_filename(text: str) -> bool:
    if re.search(r"\b(480p|576p|720p|1080p|2160p|bluray|remux|web-?dl|webrip|hdtv|x264|x265|hevc|avc)\b", text, re.I):
        return True
    return text.count(".") >= 3 and " " not in text


def audio_label(app, track: dict) -> str:
    codec = (track.get("codec") or "").lower()
    name = AUDIO_FORMATS.get(codec) or ("PCM" if codec.startswith("pcm") else codec.upper())
    channels = track.get("demux-channel-count")
    layout = fmt.channel_layout(channels) or (f"{channels}ch" if channels else "")
    main = " ".join(p for p in (lang_label(app, track.get("lang")), name, layout) if p)
    rate = track.get("demux-bitrate")
    if main and rate:
        main = f"{main}   {round(rate / 1000)} kbps"
    raw = track.get("title") or ""
    named = raw if raw and not looks_like_filename(raw) else ""
    if named and main:
        return f"{named} · {main}"
    return main or named or app.t("panel.trackN", n=track.get("id"))


def subtitle_label(app, track: dict) -> str:
    raw = track.get("title") or ""
    raw = raw if raw and not looks_like_filename(raw) else ""
    named = lang_label(app, track.get("lang"))
    if named:
        descriptors = " ".join(w for w in ("SDH", "Forced", "CC") if re.search(rf"\b{w}\b", raw, re.I))
        return " ".join(p for p in (named, descriptors) if p)
    cleaned = re.sub(r"\b(subrip|srt|sup|pgs|pgssub|vobsub|ass|ssa|webvtt|dvb)\b", " ",
                     re.sub(r"[._\-]+", " ", raw), flags=re.I)
    return re.sub(r"\s+", " ", cleaned).strip() or app.t("panel.trackN", n=track.get("id"))


def tag(text: str) -> ft.Control | None:
    if not text:
        return None
    return ft.Container(ft.Text(text, size=10, color=DIM), border=ft.Border.all(1, LINE),
                        border_radius=6, padding=ft.Padding.symmetric(horizontal=6, vertical=1))


# ------------------------------------------------------------------- dispatch
def fill(app) -> None:
    mode = app.panel_mode
    builders = {"tracks": tracks, "playlist": queue, "chapters": chapters, "library": library,
                "settings": settings, "menu": menu, "info": info}
    app.panel_header.controls, app.panel_body.controls = [], []
    if mode in builders:
        builders[mode](app)


def player_tabs(app) -> None:
    t = app.t
    choices = [("tracks", t("panel.tab.audioSub")),
               ("playlist", t("panel.tab.channels" if app.source_type == "iptv" else "panel.tab.playlist"))]
    if app.properties.get("chapter-list"):
        choices.append(("chapters", t("panel.tab.chapters")))
    header(app, tabs(app, choices, app.panel_mode, app.show_panel))


# --------------------------------------------------------------- right panel
def tracks(app) -> None:
    t = app.t
    player_tabs(app)
    body = app.panel_body.controls
    all_tracks = app.properties.get("track-list") or []
    audio = [tr for tr in all_tracks if tr.get("type") == "audio"]
    subs = [tr for tr in all_tracks if tr.get("type") == "sub"]
    body.append(section(t("panel.sec.audio")))
    if not audio:
        body.append(empty(t("panel.empty.audio")))
    for track in audio:
        body.append(item(app, audio_label(app, track), app.callback(app.select_audio, track["id"]),
                         active=bool(track.get("selected")),
                         trailing=tag("EXT" if track.get("external") else "")))
    body.append(ft.TextButton(t("panel.addAudio"), icon=ft.Icons.ADD, on_click=app.add_audio))
    body.append(section(t("panel.sec.subtitles")))
    body.append(item(app, t("panel.subNone"), app.callback(app.select_subtitle, "no"),
                     active=not any(s.get("selected") for s in subs)))
    for track in subs:
        codec = (track.get("codec") or "").lower()
        body.append(item(app, subtitle_label(app, track), app.callback(app.select_subtitle, track["id"]),
                         active=bool(track.get("selected")),
                         trailing=tag(SUB_FORMATS.get(codec) or codec.upper())))
    body.append(ft.TextButton(t("panel.addSub"), icon=ft.Icons.ADD, on_click=app.add_subtitle))
    body.extend(adjustments(app))


def adjustments(app) -> list[ft.Control]:
    """Lunoir's Adjust strip: subtitle delay, position and size, plus a reset."""
    t, props = app.t, app.properties
    def stepper(label, value_text, minus_hint, plus_hint, minus, plus):
        return ft.Row([
            ft.Text(label, size=12, color=DIM, width=72),
            ft.IconButton(ft.Icons.REMOVE_ROUNDED, icon_size=16, tooltip=minus_hint, on_click=minus),
            ft.Text(value_text, size=12, color=TEXT, width=64, text_align=ft.TextAlign.CENTER),
            ft.IconButton(ft.Icons.ADD_ROUNDED, icon_size=16, tooltip=plus_hint, on_click=plus),
        ], spacing=0)
    delay = float(props.get("sub-delay") or 0)
    position = int(props.get("sub-pos") or 100)
    scale = float(props.get("sub-scale") or 1)
    active = abs(delay) > 0.001 or position != 100 or abs(scale - 1) > 0.001
    async def reset(_=None):
        for name, value in (("sub-delay", 0), ("sub-pos", 100), ("sub-scale", 1)):
            await app.set_property(name, value)
    return [
        section(t("adjust.active") if active else t("adjust.label")),
        stepper(t("adjust.delay"), f"{delay:+.1f}s", t("adjust.earlier"), t("adjust.later"),
                app.callback(app.command, "add", "sub-delay", -0.1), app.callback(app.command, "add", "sub-delay", 0.1)),
        stepper(t("adjust.position"), str(position), t("adjust.moveUp"), t("adjust.moveDown"),
                app.callback(app.command, "add", "sub-pos", -1), app.callback(app.command, "add", "sub-pos", 1)),
        stepper(t("adjust.size"), f"{scale:.2f}×", t("adjust.smaller"), t("adjust.larger"),
                app.callback(app.command, "add", "sub-scale", -0.05), app.callback(app.command, "add", "sub-scale", 0.05)),
        ft.TextButton(t("adjust.reset"), icon=ft.Icons.RESTART_ALT_ROUNDED, on_click=reset, disabled=not active),
    ]


def queue(app) -> None:
    t = app.t
    player_tabs(app)
    body = app.panel_body.controls
    body.append(ft.Row([
        ft.TextButton(t(f"panel.repeat.{app.repeat}"), on_click=app.cycle_repeat),
        ft.TextButton(t("panel.shuffle.on" if app.shuffle else "panel.shuffle.off"), on_click=app.toggle_shuffle),
    ], spacing=0, wrap=True))
    entries = list(enumerate(app.queue))
    if app.source_type == "iptv":
        async def search(event):
            app.channel_query = event.control.value or ""
            app.fill_panel()
            app.page.update()
        body.append(ft.TextField(value=app.channel_query, hint_text=t("panel.searchChannels"), dense=True,
                                 prefix_icon=ft.Icons.SEARCH, on_change=search, border_radius=10))
        query = app.channel_query.casefold().strip()
        if query:
            entries = [(i, e) for i, e in entries if query in e.title.casefold() or query in e.group.casefold()]
            if not entries:
                body.append(empty(t("panel.noMatches")))
    if not app.queue:
        body.append(empty(t("panel.empty.queue")))
    group = None
    for index, entry in entries[:1500]:
        if app.source_type == "iptv" and entry.group != group:
            group = entry.group
            body.append(section(group or t("panel.ungrouped")))
        current = index == app.index
        body.append(item(app, entry.title or media_name(entry.path), app.callback(app.play_index, index),
            active=current,
            leading=ft.Icon(ft.Icons.PLAY_ARROW_ROUNDED, size=16, color=TEXT) if current
                    else ft.Text(str(index + 1), size=11, color=FAINT),
            trailing=ft.IconButton(ft.Icons.CLOSE_ROUNDED, icon_size=15, icon_color=FAINT,
                                   tooltip=t("lib.remove"), on_click=app.callback(app.remove_item, index))))
    collection = app.collection_key()
    saved = bool(collection) and app.profile.is_favourite(collection)
    body.append(ft.Row([
        ft.TextButton(t("panel.addFiles"), icon=ft.Icons.ADD, on_click=app.add_files),
        ft.TextButton(t("menu.home"), icon=ft.Icons.HOME_OUTLINED, on_click=app.go_home),
        ft.IconButton(ft.Icons.STAR_ROUNDED if saved else ft.Icons.STAR_BORDER_ROUNDED, icon_size=18,
                      icon_color=TEXT if saved else DIM, disabled=not collection, on_click=app.save_collection,
                      tooltip=t("panel.saveSource" if app.source_type == "iptv" else "panel.savePlaylist")),
    ], wrap=True, spacing=0))


def chapters(app) -> None:
    t = app.t
    player_tabs(app)
    body = app.panel_body.controls
    chapter_list = app.properties.get("chapter-list") or []
    current = app.properties.get("chapter")
    if not chapter_list:
        body.append(empty(t("panel.empty.chapters")))
    for index, chapter in enumerate(chapter_list):
        active = index == current
        body.append(item(app, chapter.get("title") or t("panel.chapterN", n=index + 1),
            app.callback(app.set_property, "chapter", index), active=active,
            leading=ft.Icon(ft.Icons.PLAY_ARROW_ROUNDED, size=16, color=TEXT) if active
                    else ft.Text(str(index + 1), size=11, color=FAINT),
            trailing=ft.Text(fmt.clock(chapter.get("time")), size=11, color=DIM)))


# ------------------------------------------------------------------ library
def library(app) -> None:
    t, profile = app.t, app.profile
    async def pick(tab):
        app.library_tab = tab
        app.fill_panel()
        app.page.update()
    header(app, tabs(app, [("recent", t("lib.recent")), ("saved", t("lib.favourites")),
                           ("playlists", t("lib.playlists")), ("live", t("lib.live"))],
                     app.library_tab, pick))
    body = app.panel_body.controls
    icons = {"list": ft.Icons.LIVE_TV_ROUNDED, "url": ft.Icons.LINK_ROUNDED, "playlist": ft.Icons.QUEUE_MUSIC_ROUNDED}
    if app.library_tab == "recent":
        if not profile.recents:
            body.append(empty(t("lib.emptyRecent")))
        for entry in profile.recents:
            saved = profile.is_favourite(entry["target"])
            body.append(item(app, entry.get("name") or entry["target"], app.callback(app.open_saved, entry),
                leading=ft.Icon(icons.get(entry.get("kind"), ft.Icons.HISTORY_ROUNDED), size=18, color=DIM),
                subtitle=entry["target"],
                trailing=ft.Row([
                    ft.IconButton(ft.Icons.STAR_ROUNDED if saved else ft.Icons.STAR_BORDER_ROUNDED, icon_size=15,
                                  icon_color=DIM if saved else FAINT, tooltip=t("lib.addFav"), disabled=saved,
                                  on_click=app.callback(app.favourite_recent, entry["target"])),
                    ft.IconButton(ft.Icons.CLOSE_ROUNDED, icon_size=15, icon_color=FAINT, tooltip=t("lib.remove"),
                                  on_click=app.callback(remove_recent, app, entry["target"])),
                ], spacing=0, tight=True)))
        if profile.recents:
            body.append(ft.TextButton(t("lib.clearRecents"), icon=ft.Icons.DELETE_SWEEP_OUTLINED,
                                      on_click=app.callback(confirm_clear, app)))
        return
    # one store of favourites, split by kind across the tabs (Lunoir's Library)
    kinds = {"saved": ("file", "url"), "playlists": ("playlist",), "live": ("list",)}[app.library_tab]
    entries = [entry for entry in profile.favourites if entry.get("kind", "file") in kinds]
    if app.library_tab == "saved" and app.has_media:
        saved = profile.is_favourite(app.open_target_kind[0])
        body.append(ft.TextButton(t("menu.favourite"), on_click=app.favourite_current,
                                  icon=ft.Icons.STAR_ROUNDED if saved else ft.Icons.STAR_BORDER_ROUNDED))
    if not entries:
        body.append(empty(t({"saved": "lib.emptyFav", "playlists": "lib.emptyPlaylists",
                             "live": "lib.emptyLive"}[app.library_tab])))
    for entry in entries:
        count = len(entry.get("channels") or entry.get("items") or [])
        body.append(item(app, entry.get("name") or entry["target"], app.callback(app.open_saved, entry),
            leading=ft.Icon(icons.get(entry.get("kind"), ft.Icons.MOVIE_OUTLINED), size=18, color=DIM),
            subtitle=f"{count} · {entry['target']}" if count else entry["target"],
            trailing=ft.Row([
                ft.IconButton(ft.Icons.EDIT_OUTLINED, icon_size=15, icon_color=FAINT, tooltip=t("lib.rename"),
                              on_click=app.callback(rename_favourite, app, entry)),
                ft.IconButton(ft.Icons.CLOSE_ROUNDED, icon_size=15, icon_color=FAINT, tooltip=t("lib.remove"),
                              on_click=app.callback(remove_favourite, app, entry)),
            ], spacing=0, tight=True)))


async def remove_recent(app, target: str) -> None:
    app.profile.remove_recent(target)
    app.fill_panel()
    app.page.update()


async def confirm_clear(app) -> None:
    async def close(_=None):
        app.dialog_open = False
        app.page.pop_dialog()
        app.refresh()
    async def clear(_=None):
        app.profile.clear_recents()
        await close()
        app.fill_panel()
        app.page.update()
    app.dialog_open = True
    app.layout()
    app.page.show_dialog(ft.AlertDialog(modal=True, title=ft.Text(app.t("lib.clearConfirm")),
        actions=[ft.TextButton(app.t("common.close"), on_click=close),
                 ft.Button(app.t("lib.clearRecents"), on_click=clear)], on_dismiss=close))


async def remove_favourite(app, entry: dict) -> None:
    app.profile.toggle_favourite(entry["target"], entry.get("name", ""))
    app.fill_panel()
    app.page.update()


async def rename_favourite(app, entry: dict) -> None:
    field = ft.TextField(value=entry.get("name", ""), width=420, autofocus=True)
    async def close(_=None):
        app.dialog_open = False
        app.page.pop_dialog()
        app.refresh()
    async def save(_=None):
        app.profile.rename_favourite(entry["target"], field.value or "")
        await close()
        app.fill_panel()
        app.page.update()
    field.on_submit = save
    app.dialog_open = True
    app.layout()
    app.page.show_dialog(ft.AlertDialog(modal=True, title=ft.Text(app.t("lib.rename")), content=field,
        actions=[ft.TextButton(app.t("common.close"), on_click=close),
                 ft.Button(app.t("lib.rename"), on_click=save)], on_dismiss=close))


# ----------------------------------------------------------------- settings
def settings(app) -> None:
    t, s = app.t, app.settings
    choices = [("playback", t("set.tab.playback")), ("subs", t("set.tab.subs")),
               ("interface", t("set.tab.interface")), ("general", t("set.tab.general"))]
    async def pick(tab):
        app.settings_tab = tab
        app.fill_panel()
        app.page.update()
    header(app, tabs(app, choices, app.settings_tab, pick))
    body = app.panel_body.controls

    def row(label, control, desc=None):
        parts = [ft.Row([ft.Text(label, size=13, color=TEXT, expand=True), control],
                        vertical_alignment=ft.CrossAxisAlignment.CENTER)]
        if desc:
            parts.append(ft.Text(desc, size=11, color=DIM))
        return ft.Container(ft.Column(parts, spacing=2), padding=ft.Padding.only(right=8, bottom=6))

    def toggle(key, label, desc=None, refill=False):
        async def change(event):
            await app.change_setting(key, bool(event.control.value))
            if refill:  # rows that depend on this one appear or go
                app.fill_panel()
                app.page.update()
        return row(label, ft.Switch(value=bool(s.get(key)), on_change=change, scale=0.8), desc)

    def select(key, label, opts, desc=None, width=172):
        async def change(event):
            await app.change_setting(key, event.control.value)
            app.fill_panel()
            app.page.update()
        return row(label, ft.Dropdown(value=str(s.get(key)), width=width, dense=True, text_size=12,
                                      options=[ft.DropdownOption(key=v, text=l) for v, l in opts],
                                      on_select=change), desc)

    def slider(key, label, low, high, step, desc=None, digits=0):
        value = min(high, max(low, float(s.get(key) or 0)))
        reading = ft.Text(f"{value:.{digits}f}", size=12, color=DIM, width=40, text_align=ft.TextAlign.RIGHT)
        async def moving(event):
            reading.value = f"{float(event.control.value):.{digits}f}"
            reading.update()
        async def change(event):
            number = round(float(event.control.value), digits)
            await app.change_setting(key, int(number) if digits == 0 else number)
        control = ft.Row([ft.Slider(min=low, max=high, value=value, divisions=round((high - low) / step),
                                    width=150, on_change=moving, on_change_end=change), reading],
                         spacing=0, tight=True)
        return row(label, control, desc)

    tab = app.settings_tab
    if tab == "playback":
        body += [section(t("set.sec.playlist")),
                 toggle("scanFolderIntoPlaylist", t("set.scanFolder.label"), t("set.scanFolder.desc")),
                 toggle("resumePlayback", t("set.resume.label"), t("set.resume.desc")),
                 toggle("resumePlaylistItem", t("set.resumePlaylist.label"), t("set.resumePlaylist.desc")),
                 section(t("set.sec.audio")),
                 toggle("keepPitch", t("set.keepPitch.label"), t("set.keepPitch.desc")),
                 toggle("audioPassthrough", t("set.passthrough.label"), t("set.passthrough.desc")),
                 select("audioLang", t("set.audioLang.label"), track_langs(app), t("set.audioLang.desc")),
                 section(t("set.sec.video")),
                 select("hwdec", t("set.hwdec.label"),
                        [("auto", t("opt.hwdec.auto")), ("auto-copy", t("opt.hwdec.autoCopy")), ("no", t("opt.hwdec.off"))],
                        {"auto": t("set.hwdec.auto"), "auto-copy": t("set.hwdec.autoCopy"), "no": t("set.hwdec.off")}.get(s.get("hwdec"))),
                 select("deinterlace", t("set.deint.label"),
                        [("auto", t("opt.deint.auto")), ("yes", t("opt.deint.on")), ("no", t("opt.deint.off"))],
                        t("set.deint.desc")),
                 select("streamQuality", t("set.quality.label"),
                        [("best", t("opt.quality.best")), ("2160", "2160p (4K)"), ("1080", "1080p"),
                         ("720", "720p"), ("480", "480p")], t("set.quality.desc")),
                 toggle("useCookies", t("set.cookies.label"), t("set.cookies.desc"), refill=True)]
        if s.get("useCookies"):
            body.append(select("cookiesBrowser", t("set.cookiesFrom.label"), BROWSERS))
    elif tab == "subs":
        body += [section(t("set.sec.subtitles")),
                 select("subLang", t("set.subLang.label"), track_langs(app), t("set.subLang.desc")),
                 toggle("subsDefaultOn", t("set.subsDefault.label")),
                 toggle("autoLoadSubs", t("set.autoLoadSubs.label"), t("set.autoLoadSubs.desc")),
                 select("subCodepage", t("set.subCodepage.label"), [("auto", t("opt.subCodepage.auto"))] + CODEPAGES,
                        t("set.subCodepage.desc")),
                 slider("subHdrPeak", t("set.hdrSubPeak.label"), 50, 400, 5, t("set.hdrSubPeak.desc")),
                 section(t("set.sec.subAppearance")),
                 select("subFont", t("set.subFont.label"), SUB_FONTS + [("sans-serif", t("opt.subFont.system"))],
                        t("set.subFont.desc"), width=190),
                 slider("subFontSize", t("set.subSize.label"), 20, 80, 1),
                 slider("subSpacing", t("set.subSpacing.label"), -3, 10, 0.5, t("set.subSpacing.desc"), 1),
                 slider("subOutline", t("set.subOutline.label"), 0, 10, 0.5, t("set.subOutline.desc"), 1),
                 toggle("subBold", t("set.subBold.label")),
                 slider("subMarginY", t("set.subMargin.label"), 0, 200, 2, t("set.subMargin.desc"))]
    elif tab == "interface":
        body += [section(t("set.sec.interface")),
                 select("uiLanguage", t("set.uiLang.label"),
                        [(v, t("opt.uiLang.system") if v == "system" else l) for v, l in LANG_OPTIONS],
                        t("set.uiLang.desc")),
                 section(t("set.sec.controls")),
                 select("oscStyle", t("set.oscStyle.label"),
                        [("floating", t("opt.oscStyle.floating")), ("docked", t("opt.oscStyle.docked"))],
                        f"{t('set.oscStyle.desc1')}\n{t('set.oscStyle.desc2')}"),
                 slider("oscHideDelay", t("set.oscDelay.label"), 1, 15, 1,
                        f"{t('set.oscDelay.desc1')}\n{t('set.oscDelay.desc2')}"),
                 toggle("seekPreview", t("set.seekPreview.label"), t("set.seekPreview.desc")),
                 section(t("set.sec.window")),
                 toggle("rememberWindow", t("set.rememberWindow.label")),
                 toggle("rememberVolume", t("set.rememberVolume.label"))]
    else:
        async def browse(_=None):
            folder = await app.with_dialog(lambda: ft.FilePicker().get_directory_path(
                dialog_title=t("dlg.chooseShotDir"), initial_directory=s.get("screenshotDir") or None))
            if folder:
                await app.change_setting("screenshotDir", folder)
                app.fill_panel()
                app.page.update()
        body += [section(t("set.sec.screenshots")),
                 toggle("screenshotSubs", t("set.shotSubs.label"), t("set.shotSubs.desc")),
                 select("screenshotFormat", t("set.shotFormat.label"),
                        [("png", t("opt.shot.png")), ("jpg", t("opt.shot.jpg"))], t("set.shotFormat.desc")),
                 row(t("set.shotDir.label"), ft.TextButton(t("set.shotDir.browse"), on_click=browse),
                     f"{s.get('screenshotDir')}\n{t('set.shotDir.desc')}"),
                 section(t("set.sec.about")),
                 # yt-dlp refreshes itself every 14 days; this is for a site breaking it sooner
                 row(t("set.ytdl.label"), ft.TextButton(t("set.ytdl.update"), on_click=app.refresh_ytdl,
                                                        disabled=app.ytdl_state == "working"),
                     {"working": t("set.ytdl.working"), "done": t("set.ytdl.done"),
                      "error": t("set.ytdl.failed")}.get(app.ytdl_state, t("set.ytdl.desc"))
                     + (f"\nyt-dlp {app.ytdl.version}" if app.ytdl.version else "")),
                 ft.Text("Lunoir 0.9.4 by Yao666 (MIT) · Flet front end · V libmpv binding (GPL-3.0-or-later)\n"
                         "github.com/skonester/Lunoir-V", size=11, color=DIM, selectable=True)]
        app.show_ytdl_version()


def track_langs(app) -> list[tuple[str, str]]:
    return [("", app.t("common.default"))] + [(code, app.t(f"opt.lang.{key}")) for code, key in TRACK_LANGS]


# --------------------------------------------------------------------- menu
def menu(app) -> None:
    """Lunoir's right-click menu, as a panel: Flet cannot draw a popup over the video."""
    t, props = app.t, app.properties
    header(app, title(app.window_title()))
    body = app.panel_body.controls
    multi = len(app.queue) > 1
    has_chapters = bool(props.get("chapter-list"))
    def action(label, handler, icon, disabled=False, checked=False):
        return ft.Container(ft.Row([
            ft.Icon(icon, size=18, color=FAINT if disabled else DIM),
            ft.Text(label, size=13, color=FAINT if disabled else TEXT, expand=True),
            ft.Icon(ft.Icons.CHECK_ROUNDED, size=16, color=TEXT) if checked else ft.Container(),
        ], spacing=12), padding=ft.Padding.symmetric(horizontal=8, vertical=8), border_radius=10,
            on_click=None if disabled else handler, ink=not disabled)
    def chips(options_, current, handler):
        return ft.Row([ft.Chip(label=ft.Text(label, size=12), selected=current == value,
                               on_select=app.callback(handler, value)) for value, label in options_],
                      wrap=True, spacing=6, run_spacing=6)
    paused = bool(props.get("pause"))
    a, b = props.get("ab-loop-a"), props.get("ab-loop-b")
    a_set, b_set = isinstance(a, (int, float)), isinstance(b, (int, float))
    loop_label = t("menu.abStart") if not a_set else t("menu.abEnd") if not b_set else t("menu.abClear")
    speed = props.get("speed") or 1
    current_speed = next((v for v in SPEEDS if abs(speed - v) < 0.01), None)
    body += [
        action(t("osc.play") if paused else t("osc.pause"), app.callback(app.command, "cycle", "pause"),
               ft.Icons.PLAY_ARROW_ROUNDED if paused else ft.Icons.PAUSE_ROUNDED),
        ft.Divider(color=LINE, height=8),
        action(t("menu.previous"), app.callback(app.advance, -1), ft.Icons.SKIP_PREVIOUS_ROUNDED, not multi),
        action(t("menu.next"), app.callback(app.advance, 1), ft.Icons.SKIP_NEXT_ROUNDED, not multi),
        action(t("menu.prevChapter"), app.callback(app.command, "add", "chapter", -1), ft.Icons.FIRST_PAGE_ROUNDED, not has_chapters),
        action(t("menu.nextChapter"), app.callback(app.command, "add", "chapter", 1), ft.Icons.LAST_PAGE_ROUNDED, not has_chapters),
        ft.Divider(color=LINE, height=8),
        section(t("menu.speed")),
        chips([(v, t("menu.speedNormal") if v == 1 else f"{v:g}×") for v in SPEEDS], current_speed, app.set_speed),
        section(t("menu.aspect")),
        chips([("default", t("common.default")), ("16:9", "16:9"), ("4:3", "4:3"), ("2.35", "2.35:1"),
               ("stretch", t("menu.aspectStretch"))], app.aspect, app.set_aspect),
        ft.Divider(color=LINE, height=8),
        action(loop_label, app.callback(app.command, "ab-loop"), ft.Icons.REPEAT_ROUNDED, checked=a_set and b_set),
        action(t("menu.screenshot"), app.screenshot, ft.Icons.PHOTO_CAMERA_OUTLINED),
        action(t("menu.favourite"), app.favourite_current, ft.Icons.STAR_BORDER_ROUNDED,
               checked=app.profile.is_favourite(app.open_target_kind[0])),
        action(t("info.title"), app.callback(app.toggle_panel, "info"), ft.Icons.INFO_OUTLINE_ROUNDED),
        ft.Divider(color=LINE, height=8),
        action(t("menu.home"), app.go_home, ft.Icons.HOME_OUTLINED),
        action(t("menu.openFile"), app.open_files, ft.Icons.FOLDER_OPEN_OUTLINED),
        action(t("appmenu.openFolder"), app.open_folder, ft.Icons.DRIVE_FOLDER_UPLOAD_OUTLINED),
        action(t("menu.openUrl"), app.open_url, ft.Icons.LINK_ROUNDED),
        ft.Divider(color=LINE, height=8),
        action(t("menu.fullscreen"), app.fullscreen, ft.Icons.FULLSCREEN_ROUNDED,
               checked=bool(app.page.window.full_screen)),
    ]


# --------------------------------------------------------------------- info
INFO_PROPERTIES = ("file-format", "duration", "file-size", "video-codec", "video-format",
                   "video-params/w", "video-params/h", "container-fps", "video-bitrate",
                   "video-params/pixelformat", "video-params/colormatrix", "video-params/primaries",
                   "video-params/gamma", "track-list")


async def load_info(app) -> None:
    """MediaInfo's fields as far as mpv knows them; Lunoir asks MediaInfo itself."""
    data = {}
    for name in INFO_PROPERTIES:
        value = await app.try_command("get_property", name)
        if value is not None and value is not True:
            data[name] = value
    app.info_data = data


def info(app) -> None:
    t = app.t
    data = app.info_data
    header(app, title(t("info.title")))
    body = app.panel_body.controls
    def line(label, value):
        if value in (None, "", 0):
            return
        body.append(ft.Row([ft.Text(label, size=12, color=DIM, width=110),
                            ft.Text(str(value), size=12, color=TEXT, expand=True, selectable=True)]))
    if not data:
        body.append(empty(t("info.noData")))
        return
    duration, size = data.get("duration"), data.get("file-size")
    line(t("info.container"), data.get("file-format"))
    line(t("info.duration"), fmt.duration_text(duration) if duration else None)
    line(t("info.fileSize"), fmt.file_size(size) if size else None)
    if size and duration:
        line(t("info.overallBitRate"), fmt.bitrate(size * 8 / duration))
    width, height = data.get("video-params/w"), data.get("video-params/h")
    if width or height:
        body.append(section(t("info.video")))
    line(t("info.codec"), data.get("video-codec") or data.get("video-format"))
    line(t("info.resolution"), f"{width} × {height}" if width and height else None)
    fps = data.get("container-fps")
    line(t("info.frameRate"), f"{fps:.3f}".rstrip("0").rstrip(".") + " fps" if fps else None)
    line(t("info.bitRate"), fmt.bitrate(data["video-bitrate"]) if data.get("video-bitrate") else None)
    pixel = str(data.get("video-params/pixelformat") or "")
    depth = re.search(r"p(\d{2})", pixel)
    line(t("info.bitDepth"), f"{depth.group(1) if depth else 8}-bit" if pixel else None)
    space = " / ".join(str(data[k]) for k in ("video-params/colormatrix", "video-params/primaries") if data.get(k))
    line(t("info.colorSpace"), space)
    line(t("info.hdr"), fmt.hdr_label(data.get("video-params/gamma")))
    audio = [tr for tr in data.get("track-list") or [] if tr.get("type") == "audio"]
    if audio:
        body.append(section(t("info.audio")))
    for track in audio:
        body.append(ft.Text(audio_label(app, track), size=12, color=TEXT if track.get("selected") else DIM))
