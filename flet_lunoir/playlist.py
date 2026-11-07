"""Playlist sources, ported from Lunoir's main/index.ts.

Lunoir keeps the queue itself and loads one file at a time with loadfile-replace,
so folders, local M3U queues and IPTV channel lists are all resolved here.
"""
from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
import re
import urllib.parse
import urllib.request

VIDEO_EXT = (
    "mp4", "mkv", "avi", "mov", "flv", "wmv", "webm", "m4v", "ts", "mpg", "mpeg",
    "m2ts", "rmvb", "3gp", "ogv", "mp3", "flac", "aac", "wav", "m4a", "ogg", "opus",
)
OPEN_EXT = VIDEO_EXT + ("m3u",)
AUDIO_EXT = ("aac", "ac3", "dts", "eac3", "flac", "m4a", "mka", "mp2", "mp3",
             "ogg", "opus", "thd", "truehd", "wav", "w64", "wv")
SUBTITLE_EXT = ("srt", "ass", "ssa", "vtt", "sub", "sup", "idx", "lrc")
MAX_FOLDER_SCAN = 500
# IPTV list servers commonly refuse requests that don't look like a browser.
IPTV_UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
           "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")


@dataclass
class Entry:
    path: str
    title: str = ""
    group: str = ""


def is_url(target: str) -> bool:
    return bool(re.match(r"^[a-z][a-z0-9+.-]*://", target, re.I))


def is_http(target: str) -> bool:
    return bool(re.match(r"^https?://", target, re.I))


def media_name(target: str) -> str:
    if is_url(target):
        tail = urllib.parse.unquote(target.rstrip("/").rsplit("/", 1)[-1].split("?", 1)[0])
        return tail or target
    return Path(target).name


def _natural(name: str):
    return [(0, int(part), "") if part.isdigit() else (1, 0, part.casefold())
            for part in re.split(r"(\d+)", name) if part]


def scan_folder(directory: str) -> list[str]:
    """Sorted media files directly inside a folder (non-recursive)."""
    try:
        names = [entry.name for entry in os.scandir(directory)
                 if entry.is_file() and entry.name.rsplit(".", 1)[-1].lower() in VIDEO_EXT
                 and "." in entry.name]
    except OSError:
        return []
    return [os.path.join(directory, name) for name in sorted(names, key=_natural)]


def _extinf_title(line: str) -> str:
    # The title follows the comma after the final quoted attribute, so a comma
    # inside an attribute value does not cut it short.
    quote = line.rfind('"')
    comma = line.find(",", quote if quote >= 0 else 0)
    return line[comma + 1:].strip() if comma >= 0 else ""


def parse_local_m3u(source: str, text: str | None = None) -> list[Entry]:
    """A local M3U as a queue; relative entries belong to the playlist's folder."""
    if text is None:
        text = Path(source).read_text(encoding="utf-8-sig", errors="replace")
    base = Path(source).resolve().parent
    entries, title = [], ""
    for raw in text.splitlines():
        line = raw.strip().lstrip("﻿")
        if re.match(r"^#EXTINF", line, re.I):
            title = _extinf_title(line)
            continue
        if not line or line.startswith("#"):
            continue
        target = line
        if len(target) >= 2 and target[0] == target[-1] and target[0] in "\"'":
            target = target[1:-1]
        if re.match(r"^file://", target, re.I):
            parsed = urllib.parse.urlparse(target)
            target = urllib.request.url2pathname(urllib.parse.unquote(parsed.netloc + parsed.path))
            if parsed.netloc:
                target = "\\\\" + target.lstrip("\\")
        elif not is_url(target):
            target = str((base / target).resolve())
        entries.append(Entry(target, title or media_name(target)))
        title = ""
    return entries


def parse_channel_list(text: str) -> list[Entry]:
    """Extended M3U (#EXTINF) or the txt `name,url` form with `group,#genre#` headers."""
    lines = text.splitlines()
    channels: list[Entry] = []
    m3u = bool(lines and re.match(r"^﻿?#EXTM3U", lines[0], re.I)) or \
        any(re.match(r"^#EXTINF", line.strip(), re.I) for line in lines)
    if m3u:
        pending = None
        for raw in lines:
            line = raw.strip()
            if re.match(r"^#EXTINF", line, re.I):
                group = re.search(r'group-title="([^"]*)"', line, re.I)
                pending = (_extinf_title(line), group.group(1).strip() if group else "")
            elif line and not line.startswith("#"):
                if is_http(line):
                    channels.append(Entry(line, (pending and pending[0]) or line, (pending and pending[1]) or ""))
                pending = None
    else:
        group = ""
        for raw in lines:
            line = raw.strip()
            left, comma, right = line.partition(",")
            if not comma:
                continue
            left, right = left.strip(), right.strip()
            if right == "#genre#":
                group = left
            elif is_http(right):
                channels.append(Entry(right, left or right, group))
    return channels


def read_source(source: str, user_agent: str = "") -> str:
    """Blocking: fetch a remote list or read a local one. Run it off the UI loop."""
    if is_http(source):
        request = urllib.request.Request(source, headers={"User-Agent": user_agent or IPTV_UA})
        with urllib.request.urlopen(request, timeout=20) as response:
            charset = response.headers.get_content_charset() or "utf-8"
            return response.read().decode(charset, errors="replace")
    return Path(source).read_text(encoding="utf-8-sig", errors="replace")


def is_local_queue(target: str) -> bool:
    return not is_url(target) and target.lower().endswith(".m3u")


def is_channel_list(target: str) -> bool:
    """Lunoir's CHANNEL_LIST_EXT: .m3u/.txt lists; .m3u8 is a stream manifest."""
    return bool(re.search(r"\.(m3u|txt)(\?|#|$)", target, re.I))
