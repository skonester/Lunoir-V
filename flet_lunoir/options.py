"""Lunoir settings to mpv properties: applyMpvSettings and settings:set in main/index.ts."""
from __future__ import annotations

import os
from pathlib import Path

SUB_FONT_FALLBACK = "Microsoft YaHei"
YTDL_FORMAT = {
    # Not "" as in Lunoir: with no format and no ffmpeg to merge, yt-dlp picks the best
    # single file, which on YouTube is 360p. mpv plays separate streams without merging.
    "best": "bestvideo+bestaudio/best",
    "2160": "bestvideo[height<=?2160]+bestaudio/best[height<=?2160]",
    "1080": "bestvideo[height<=?1080]+bestaudio/best[height<=?1080]",
    "720": "bestvideo[height<=?720]+bestaudio/best[height<=?720]",
    "480": "bestvideo[height<=?480]+bestaudio/best[height<=?480]",
}
# Applied once on connect, in Lunoir's order.
APPLIED = ("deinterlace", "hwdec", "audioLang", "subLang", "subsDefaultOn", "autoLoadSubs",
           "subCodepage", "subFont", "subFontSize", "subSpacing", "subBold", "subOutline",
           "subMarginY", "subHdrPeak", "keepPitch", "streamQuality", "useCookies",
           "audioPassthrough", "screenshotDir", "screenshotFormat")


def sub_font_chain(font: str) -> str:
    font = (font or "").strip()
    if not font or font == "sans-serif":
        return "sans-serif"
    return font if font == SUB_FONT_FALLBACK else f"{font},{SUB_FONT_FALLBACK}"


def pictures_folder() -> Path:
    try:
        from win32com.shell import shell, shellcon
        return Path(shell.SHGetFolderPath(0, shellcon.CSIDL_MYPICTURES, None, 0))
    except Exception:
        return Path(os.environ.get("USERPROFILE", Path.home())) / "Pictures"


def screenshot_dir(settings: dict) -> str:
    return settings.get("screenshotDir") or str(pictures_folder() / "Lunoir")


def properties_for(key: str, s: dict) -> list[tuple[str, object]]:
    """The mpv properties one setting controls; [] for UI-only settings."""
    if key == "deinterlace":
        return [("deinterlace", s["deinterlace"])]
    if key == "hwdec":
        return [("hwdec", s["hwdec"])]
    if key == "audioLang":
        return [("alang", s["audioLang"])]
    if key == "subLang":
        return [("slang", s["subLang"])]
    if key == "subsDefaultOn":
        return [("sub-visibility", bool(s["subsDefaultOn"]))]
    if key == "autoLoadSubs":
        return [("sub-auto", "fuzzy" if s["autoLoadSubs"] else "no")]
    if key == "subCodepage":
        return [("sub-codepage", s["subCodepage"])]
    if key == "subFont":
        return [("sub-font", sub_font_chain(s["subFont"]))] if s["subFont"] else []
    if key == "subFontSize":
        return [("sub-font-size", s["subFontSize"])] if s["subFontSize"] > 0 else []
    if key == "subSpacing":
        return [("sub-spacing", s["subSpacing"])]
    if key == "subBold":
        return [("sub-bold", bool(s["subBold"]))]
    if key == "subOutline":
        return [("sub-outline-size", s["subOutline"])]
    if key == "subMarginY":
        return [("sub-margin-y", int(s["subMarginY"]))]
    if key == "subHdrPeak":
        # text subtitles and bitmap (PGS/VOBSUB) subtitles have separate properties
        return [("sub-hdr-peak", s["subHdrPeak"]), ("image-subs-hdr-peak", s["subHdrPeak"])]
    if key == "keepPitch":
        return [("audio-pitch-correction", bool(s["keepPitch"]))]
    if key == "streamQuality":
        return [("ytdl-format", YTDL_FORMAT.get(s["streamQuality"], ""))]
    if key in ("useCookies", "cookiesBrowser"):
        return [("ytdl-raw-options", f"cookies-from-browser={s['cookiesBrowser']}" if s["useCookies"] else "")]
    if key in ("audioPassthrough", "passthroughCodecs"):
        return [("audio-spdif", s["passthroughCodecs"] if s["audioPassthrough"] else "")]
    if key == "screenshotDir":
        return [("screenshot-directory", screenshot_dir(s))]
    if key == "screenshotFormat":
        result = [("screenshot-format", s["screenshotFormat"])]
        if s["screenshotFormat"] == "jpg":
            result.append(("screenshot-jpeg-quality", 95))
        return result
    return []


def startup_properties(s: dict) -> list[tuple[str, object]]:
    result = []
    for key in APPLIED:
        result.extend(properties_for(key, s))
    if s.get("rememberVolume"):
        result.append(("volume", s["volume"]))
    return result
