"""yt-dlp on demand (Lunoir's main/index.ts: ensureYtdl, refreshYtdl, enumeratePlaylist).

mpv's built-in ytdl_hook resolves site URLs through yt-dlp. Like Lunoir, the player
does not bundle it: it downloads the latest release into the profile the first time
a site URL plays, and checks a copy older than 14 days in the background. A new copy
must match the release's published checksum before it replaces the old one."""
from __future__ import annotations

import asyncio
import hashlib
import logging
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.request

from .playlist import Entry, is_url

RELEASES = "https://github.com/yt-dlp/yt-dlp/releases"
STALE_SECONDS = 14 * 24 * 3600
MEDIA_URL_EXT = re.compile(
    r"\.(mp4|mkv|webm|m4v|mov|avi|flv|ts|m2ts|mpg|mpeg|m3u8|mpd|mp3|flac|aac|wav|ogg|opus|m4a)(\?|#|$)", re.I)
# Sites break yt-dlp regularly; when it says so, that is the one failure a refresh fixes.
OUTDATED = re.compile(r"out.?of.?date|outdated|update (yt-dlp|to the latest)|nightly", re.I)
log = logging.getLogger(__name__)


def needs_ytdl(url: str) -> bool:
    """A site URL (YouTube, etc.) mpv must resolve through yt-dlp, not a direct media file."""
    return bool(re.match(r"^https?://", url, re.I)) and not MEDIA_URL_EXT.search(url)


def is_playlist_url(url: str) -> bool:
    """An explicit playlist URL (YouTube /playlist?...), expanded into the queue."""
    return is_url(url) and bool(re.search(r"/playlist\?", url, re.I))


def playlist_key(url: str) -> str:
    """Its list= parameter, so extra parameters don't change the key."""
    match = re.search(r"[?&]list=([^&]+)", url, re.I)
    return "list:" + (match.group(1) if match else url)


def error_text(text: str) -> str:
    """yt-dlp's own reason from a ytdl_hook log line (members-only, DRM, unavailable),
    without its boilerplate tail; '' when the line carries none."""
    match = re.search(r"\bERROR:\s*(.+)$", text.strip(), re.I | re.S)
    if not match:
        return ""
    reason = re.sub(r"\s*;\s*please report this issue.*", "", match.group(1), flags=re.I | re.S)
    reason = re.sub(r"\s*You might want to use.*", "", reason, flags=re.I | re.S)
    return reason.strip()[:200]


def _open(url: str):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Lunoir-V"}), timeout=60)


def latest_tag() -> str:
    """The latest release's version, from where GitHub redirects /latest (no API quota)."""
    with _open(RELEASES + "/latest") as response:
        address = response.geturl()
    tag = address.rstrip("/").rsplit("/", 1)[-1]
    if not re.fullmatch(r"\d{4}\.\d{2}\.\d{2}(\.\d+)?", tag):
        raise ValueError(f"unexpected release address: {address}")
    return tag


def installed_version(exe: Path) -> str:
    """What the copy on disk reports; '' when it is missing or does not run."""
    try:
        result = subprocess.run([str(exe), "--version"], stdin=subprocess.DEVNULL, capture_output=True,
                                timeout=30, creationflags=subprocess.CREATE_NO_WINDOW)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return result.stdout.decode("ascii", errors="replace").strip() if result.returncode == 0 else ""


def _published_sha256(tag: str) -> str:
    with _open(f"{RELEASES}/download/{tag}/SHA2-256SUMS") as response:
        for line in response.read().decode("ascii", errors="replace").splitlines():
            digest, _, name = line.strip().partition(" ")
            if name.strip().lstrip("*") == "yt-dlp.exe":
                return digest.lower()
    raise ValueError(f"no checksum for yt-dlp.exe in release {tag}")


def _download(tag: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")  # a partial file must never be used
    try:
        expected = _published_sha256(tag)
        digest = hashlib.sha256()
        with _open(f"{RELEASES}/download/{tag}/yt-dlp.exe") as response, part.open("wb") as out:
            while chunk := response.read(1 << 16):  # ends quietly if the connection drops
                digest.update(chunk)
                out.write(chunk)
        if digest.hexdigest() != expected:
            raise ValueError(f"yt-dlp.exe {tag} does not match its published checksum")
        # Defender may hold the new file while it scans it, and a running yt-dlp holds
        # the old one until it finishes resolving a URL: retry the rename
        for attempt in range(8):
            time.sleep(0.5 * attempt)
            try:
                os.replace(part, dest)
                return
            except OSError:
                if attempt == 7:
                    raise
    finally:
        part.unlink(missing_ok=True)


class Ytdl:
    def __init__(self, profile_dir: Path):
        self.exe = profile_dir / "yt-dlp" / "yt-dlp.exe"
        self.task: asyncio.Task | None = None
        self.version: str | None = None  # None until read; '' when the copy does not run
        self.replaced = False  # whether the last update brought a new version

    def stale(self) -> bool:
        try:
            return time.time() - self.exe.stat().st_mtime > STALE_SECONDS
        except OSError:
            return True

    def _update(self) -> None:
        """Runs on a worker thread. Skips the download when already on the latest."""
        tag = latest_tag()
        self.replaced = installed_version(self.exe) != tag
        if self.replaced:
            _download(tag, self.exe)
        else:
            os.utime(self.exe)  # good for another 14 days
        self.version = tag

    async def _fetch(self) -> str | None:
        try:
            await asyncio.to_thread(self._update)
            return str(self.exe)
        except Exception as error:  # whatever went wrong, the old copy stays usable
            log.warning("yt-dlp update failed: %s", error)
            return None

    async def read_version(self) -> str:
        self.version = await asyncio.to_thread(installed_version, self.exe)
        return self.version

    def _start(self) -> asyncio.Task:
        if not self.task or self.task.done():
            self.task = asyncio.create_task(self._fetch())
        return self.task

    @property
    def downloading(self) -> bool:
        return bool(self.task and not self.task.done())

    async def ensure(self) -> str | None:
        """The existing copy at once (refreshing a stale one behind it), else wait for
        the first download. None when that failed."""
        if self.exe.is_file():
            if self.stale():
                self._start()
            return str(self.exe)
        return await self._start()

    async def refresh(self) -> str | None:
        """Update now, whatever the age (Settings, or yt-dlp saying it is outdated).
        Joins an update already running. None when it failed."""
        return await self._start()

    async def playlist(self, url: str) -> list[Entry]:
        """The playlist's entries, flat (no per-video resolve)."""
        exe = await self.ensure()
        if not exe:
            return []
        def run() -> str:
            result = subprocess.run(
                # utf-8 explicitly: a pipe otherwise gets the ANSI code page
                [exe, "--flat-playlist", "--no-warnings", "--encoding", "utf-8",
                 "--print", "%(url)s ||| %(title)s", url],
                stdin=subprocess.DEVNULL, capture_output=True, timeout=120,
                creationflags=subprocess.CREATE_NO_WINDOW)
            return result.stdout.decode("utf-8", errors="replace")
        try:
            out = await asyncio.to_thread(run)
        except (OSError, subprocess.TimeoutExpired):
            return []
        entries = []
        for line in out.splitlines():
            link, sep, title = line.partition(" ||| ")
            link = link.strip()
            if sep and re.match(r"^https?://", link, re.I):
                entries.append(Entry(link, title.strip() or link))
        return entries
