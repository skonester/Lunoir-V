"""Lunoir-compatible JSON shapes (main/settings.ts), kept in a separate profile."""
from __future__ import annotations

import json
import os
from pathlib import Path
import time

# Lunoir's DEFAULTS. Keys the Flet port does not use yet are kept so a settings.json
# copied between the two apps round-trips without losing anything.
DEFAULTS = {
    "uiLanguage": "system", "scanFolderIntoPlaylist": False, "resumePlayback": True,
    "resumePlaylistItem": True, "keepPitch": True, "audioLang": "", "subLang": "",
    "subsDefaultOn": True, "autoLoadSubs": True, "subCodepage": "auto",
    "audioPassthrough": False, "passthroughCodecs": "ac3,eac3,truehd,dts,dts-hd",
    "oscHideDelay": 5, "oscStyle": "floating", "seekPreview": True, "frostStrength": 50,
    "subHdrPeak": 120, "hwdec": "auto", "enhance": False, "deblock": 3, "nr": 0,
    "sharpen": 0.2, "artcnn": False, "cfl": False, "deinterlace": "no",
    "streamQuality": "best", "useCookies": False, "cookiesBrowser": "edge",
    "subFont": "Microsoft YaHei", "subFontSize": 38, "subSpacing": 0, "subBold": False,
    "subOutline": 3, "subMarginY": 34, "timeFormat": "time", "timecodeOverlay": False,
    "screenshotSubs": True, "screenshotFormat": "png", "screenshotDir": "",
    "recordingDir": "", "hideTitleBar": False, "rememberWindow": True,
    "rememberVolume": True, "checkForUpdates": True, "experimentalTimeline": False,
    "pinOscInTrim": True, "volume": 100, "windowBounds": None,
}
RECENTS_CAP = 20


class Profile:
    def __init__(self, directory: Path | None = None) -> None:
        self.directory = directory or self.default_directory()
        self.settings = dict(DEFAULTS)
        self.settings.update(self.read("settings.json", {}))
        self.positions = self.read("positions.json", {})
        self.recents = self.read("recents.json", [])
        self.favourites = self.read("favourites.json", [])
        self.playlist_items = self.read("playlist-progress.json", {})
        self.audio = {key: value for key, value in self.read("audio-selections.json", {}).items()
                      if valid_audio(value)}
        self.subtitles = {key: value for key, value in self.read("subtitle-selections.json", {}).items()
                          if valid_subtitle(value)}

    @staticmethod
    def default_directory() -> Path:
        return Path(os.environ.get("APPDATA", Path.home())) / "Lunoir V"

    def read(self, name, default):
        try:
            value = json.loads((self.directory / name).read_text(encoding="utf-8"))
            return value if isinstance(value, type(default)) else default
        except (OSError, ValueError):
            return default

    def write(self, name, data) -> None:
        self.directory.mkdir(parents=True, exist_ok=True)
        path = self.directory / name
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        temporary.replace(path)

    def set(self, key: str, value) -> None:
        self.settings[key] = value
        self.write("settings.json", self.settings)

    # ---- resume positions: Lunoir saves past 5 s and forgets the last 10 s ----
    def save_position(self, target: str, seconds: float, duration: float, seekable: bool) -> None:
        if not target or not seekable or not self.settings.get("resumePlayback"):
            return
        near_end = duration > 0 and seconds > duration - 10
        if near_end:
            if self.positions.pop(target, None) is None:
                return
        elif seconds > 5:
            if self.positions.get(target) == seconds:
                return
            self.positions[target] = seconds
        else:
            return
        self.write("positions.json", self.positions)

    def clear_position(self, target: str) -> None:
        if self.positions.pop(target, None) is not None:
            self.write("positions.json", self.positions)

    # ---- per-file track choices (they survive finishing the video) ----
    def save_audio(self, target: str, selection: dict) -> None:
        if target and valid_audio(selection):
            self.audio[target] = selection
            self.write("audio-selections.json", self.audio)

    def subtitle_files(self, target: str) -> list[str]:
        saved = self.subtitles.get(target) or {}
        files = [p for p in saved.get("externalPaths", []) if isinstance(p, str) and p]
        if saved.get("type") == "external":
            files.append(saved["path"])
        return list(dict.fromkeys(files))

    def save_subtitle(self, target: str, selection: dict) -> None:
        if not target or not valid_subtitle(selection):
            return
        files = self.subtitle_files(target)
        if selection["type"] == "external":
            files.append(selection["path"])
        self.subtitles[target] = {**selection, "externalPaths": list(dict.fromkeys(files))}
        self.write("subtitle-selections.json", self.subtitles)

    # ---- which item of a playlist was reached ----
    def save_playlist_item(self, key: str, item: str) -> None:
        if key and self.playlist_items.get(key) != item:
            self.playlist_items[key] = item
            self.write("playlist-progress.json", self.playlist_items)

    # ---- recently played and favourites ----
    def recent(self, target: str, name: str, kind: str | None = None) -> None:
        entry = {"target": target, "name": name, "kind": kind or ("url" if "://" in target else "file"),
                 "at": int(time.time() * 1000)}
        self.recents = ([entry] + [item for item in self.recents if item.get("target") != target])[:RECENTS_CAP]
        self.write("recents.json", self.recents)

    def rename_recent(self, target: str, name: str) -> None:
        for item in self.recents:
            if item.get("target") == target and name and item.get("name") != name:
                item["name"] = name
                self.write("recents.json", self.recents)

    def remove_recent(self, target: str) -> None:
        self.recents = [item for item in self.recents if item.get("target") != target]
        self.write("recents.json", self.recents)

    def clear_recents(self) -> None:
        self.recents = []
        self.write("recents.json", self.recents)

    def is_favourite(self, target: str) -> bool:
        return any(item.get("target") == target for item in self.favourites)

    def toggle_favourite(self, target: str, name: str, kind: str | None = None, **extra) -> bool:
        """Returns True when the item is now saved."""
        if self.is_favourite(target):
            self.favourites = [item for item in self.favourites if item.get("target") != target]
            saved = False
        else:
            self.favourites.insert(0, {"target": target, "name": name,
                                       "kind": kind or ("url" if "://" in target else "file"),
                                       "at": int(time.time() * 1000), **extra})
            saved = True
        self.write("favourites.json", self.favourites)
        return saved

    def rename_favourite(self, target: str, name: str) -> None:
        name = name.strip()
        for item in self.favourites:
            if item.get("target") == target and name and item.get("name") != name:
                item["name"] = name
                self.write("favourites.json", self.favourites)


def queue_key(paths: list[str]) -> str:
    """Lunoir's queueKey: 'pl:' + its 31-multiplier hash of the joined paths, over
    UTF-16 code units as JavaScript counts them, in base 36."""
    data = "|".join(paths).encode("utf-16-le")
    h = 0
    for i in range(0, len(data), 2):
        h = (h * 31 + int.from_bytes(data[i:i + 2], "little")) & 0xFFFFFFFF
    digits = ""
    while True:
        h, r = divmod(h, 36)
        digits = "0123456789abcdefghijklmnopqrstuvwxyz"[r] + digits
        if not h:
            return "pl:" + digits


def valid_audio(value) -> bool:
    return isinstance(value, dict) and (
        (value.get("type") == "embedded" and isinstance(value.get("id"), int)) or
        (value.get("type") == "external" and isinstance(value.get("path"), str)))


def valid_subtitle(value) -> bool:
    return isinstance(value, dict) and (
        value.get("type") == "none" or
        (value.get("type") == "embedded" and isinstance(value.get("id"), int) and value["id"] > 0) or
        (value.get("type") == "external" and isinstance(value.get("path"), str) and bool(value["path"])))
