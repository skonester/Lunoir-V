"""Lunoir's own translations, read from lunoir/src/shared/i18n/*.ts.

The locale files are flat `'key': 'value'` object literals, so they are parsed here
instead of being copied: a string fixed upstream reaches the Flet port unchanged.
Lookup follows Lunoir's translate(): requested locale, then English, then the key.
"""
from __future__ import annotations

import ctypes
import locale as pylocale
import re
from pathlib import Path

from .backend import ROOT

I18N_DIR = ROOT / "lunoir/src/shared/i18n"
LOCALES = ("en", "zh-CN", "fr", "de", "es", "pt", "ru", "ja", "ko")
# Each label is in its own language (Lunoir's LANG_OPTIONS); 'system' is translated.
LANG_OPTIONS = [("system", "System"), ("en", "English"), ("zh-CN", "简体中文"),
                ("fr", "Français"), ("de", "Deutsch"), ("es", "Español"),
                ("pt", "Português"), ("ru", "Русский"), ("ja", "日本語"), ("ko", "한국어")]

_ENTRY = re.compile(r"""^\s*'([^']+)'\s*:\s*('(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")""", re.M)
_ESCAPE = re.compile(r"\\(u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)", re.S)
_SIMPLE = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}


def _unescape(body: str) -> str:
    def replace(match: re.Match) -> str:
        code = match.group(1)
        if code[0] in "ux" and len(code) > 1:
            return chr(int(code[1:].strip("{}"), 16))
        return _SIMPLE.get(code, code)
    return _ESCAPE.sub(replace, body)


def parse_locale(text: str) -> dict[str, str]:
    return {key: _unescape(value[1:-1]) for key, value in _ENTRY.findall(text)}


def resolve_system_locale(tag: str) -> str:
    """Lunoir's resolveSystemLocale: Traditional Chinese falls back to English."""
    tag = tag.replace("_", "-")
    if re.match(r"^zh(-)?(hans|cn|sg)?$", tag, re.I) or re.match(r"^zh-hans", tag, re.I):
        return "zh-CN"
    base = tag[:2].lower()
    return base if base in ("fr", "de", "es", "pt", "ru", "ja", "ko") else "en"


def system_locale_tag() -> str:
    try:
        kernel = ctypes.windll.kernel32
        buffer = ctypes.create_unicode_buffer(85)
        if kernel.LCIDToLocaleName(kernel.GetUserDefaultUILanguage(), buffer, 85, 0):
            return buffer.value
    except (AttributeError, OSError):
        pass
    return pylocale.getlocale()[0] or "en"


_cache: dict[str, dict[str, str]] = {}


def dictionary(code: str) -> dict[str, str]:
    if code not in _cache:
        try:
            _cache[code] = parse_locale((I18N_DIR / f"{code}.ts").read_text(encoding="utf-8"))
        except OSError:
            _cache[code] = {}
    return _cache[code]


class Translator:
    def __init__(self, setting: str = "system", system_tag: str | None = None) -> None:
        self.system_tag = system_tag
        self.set_language(setting)

    def set_language(self, setting: str) -> None:
        if setting in LOCALES:
            self.locale = setting
        else:
            self.locale = resolve_system_locale(self.system_tag or system_locale_tag())
        self.strings = dictionary(self.locale)
        self.fallback = dictionary("en")

    def __call__(self, key: str, **values) -> str:
        text = self.strings.get(key) or self.fallback.get(key) or key
        if values:
            text = re.sub(r"\{(\w+)\}", lambda m: str(values.get(m.group(1), m.group(0))), text)
        return text
