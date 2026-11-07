"""Readouts and badges from Lunoir's Controls.tsx and OverlayView.tsx."""
from __future__ import annotations

import math
import re

# Release names carry technical tags that only bloat a screenshot's name.
TECH_TAG = re.compile(
    r"[.\s_-](\d{3,4}p|4k|web-?dl|web-?rip|blu-?ray|bd-?rip|br-?rip|hdtv|remux|dvdrip|x26[45]|"
    r"h\.?26[45]|hevc|avc|xvid|aac\d?|ac-?3|e-?ac-?3|ddp?\d?|dts(-hd)?|truehd|atmos|flac|opus|"
    r"\d{1,2}bits?|hdr\d*\+?|dv|hi10p?|repack|proper|internal|\d+audio)", re.I)
TIME_FORMATS = ("time", "timecode", "frame")
CODEC_SHORT = {"truehd": "TrueHD", "eac3": "DD+", "ac3": "DD", "dts": "DTS", "aac": "AAC",
               "flac": "FLAC", "alac": "ALAC", "opus": "Opus", "vorbis": "Vorbis", "mp3": "MP3"}


def _number(value) -> float:
    return float(value) if isinstance(value, (int, float)) and math.isfinite(value) else 0.0


def clock(seconds) -> str:
    """The OSC's readout: MM:SS, or H:MM:SS past an hour."""
    total = max(0, int(_number(seconds)))
    hours, rest = divmod(total, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}:{minutes:02}:{secs:02}" if hours else f"{minutes:02}:{secs:02}"


def duration_text(seconds) -> str:
    total = max(0, int(_number(seconds)))
    hours, rest = divmod(total, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}:{minutes:02}:{secs:02}" if hours else f"{minutes}:{secs:02}"


def current_frame(frame_number, position, fps) -> int:
    """mpv's own count when known; stepping parks time where floor(t * fps) is ambiguous."""
    if _number(frame_number) > 0:
        return round(frame_number)
    if _number(fps) > 0 and _number(position) > 0:
        return math.floor(position * fps)
    return 0


def timecode(frame: int, fps) -> str:
    """Non-drop HH:MM:SS:FF from the integer frame index at the nominal rate."""
    rate = max(1, round(_number(fps)) or 24)
    frame = max(0, int(frame))
    secs = frame // rate
    return f"{secs // 3600:02}:{secs // 60 % 60:02}:{secs % 60:02}:{frame % rate:02}"


def channel_layout(count) -> str:
    count = int(_number(count))
    if count >= 8:
        return "7.1"
    return {7: "6.1", 6: "5.1", 3: "2.1", 2: "2.0", 1: "Mono"}.get(count, "")


def audio_badge(codec: str, channels) -> str:
    if not codec:
        return ""
    lower = codec.lower()
    name = CODEC_SHORT.get(lower) or ("PCM" if lower.startswith("pcm") else codec.upper())
    layout = channel_layout(channels)
    return f"{name} {layout}" if layout else name


def hdr_label(gamma) -> str:
    return "HDR" if str(gamma or "").lower() in ("pq", "st2084", "hlg") else ""


def resolution_tier(width, height) -> int:
    width, height = int(_number(width)), int(_number(height))
    tier = max(height, round(width * 9 / 16) if width > 0 else 0)
    best = 0
    for standard in (4320, 2160, 1440, 1080, 720, 576, 540, 480, 360, 240):
        if abs(tier - standard) <= standard * 0.06 and (not best or abs(tier - standard) < abs(tier - best)):
            best = standard
    return best or tier


def total_channels(count) -> str:
    count = int(_number(count))
    names = {1: "1.0", 2: "2.0", 3: "2.1", 4: "4.0", 5: "4.1", 6: "5.1", 7: "6.1", 8: "7.1", 10: "9.1", 12: "11.1"}
    return names.get(count, f"{count} ch")


def bitrate(bps) -> str:
    bps = _number(bps)
    if bps >= 1_000_000:
        return f"{bps / 1_000_000:.1f} Mbps"
    if bps >= 1_000:
        return f"{bps / 1_000:.0f} kbps"
    return f"{bps:.0f} bps"


def file_size(size) -> str:
    size = _number(size)
    if size >= 1_073_741_824:
        return f"{size / 1_073_741_824:.2f} GB"
    if size >= 1_048_576:
        return f"{size / 1_048_576:.1f} MB"
    if size >= 1_024:
        return f"{size / 1_024:.0f} KB"
    return f"{size:.0f} B"


def clean_base_name(file_name: str) -> str:
    name = re.sub(r"\.[^.]+$", "", file_name or "")
    match = TECH_TAG.search(name)
    if match and match.start():
        name = name[:match.start()]
    name = re.sub(r"[.\s_-]+$", "", name)
    if len(name) > 50:
        name = re.sub(r"[.\s_-]+$", "", name[:50])
    return name.replace("%", "")  # % starts a specifier in mpv's template


def screenshot_template(file_name: str, position) -> str:
    """'<file>_<HH-MM-SS position>_<yymmdd>_<hhmmss>', so a film's shots sort in order."""
    seconds = max(0, int(_number(position)))
    where = f"{seconds // 3600:02}-{seconds // 60 % 60:02}-{seconds % 60:02}"
    return f"{clean_base_name(file_name) or '%F'}_{where}_%ty%tm%td_%tH%tM%tS"
