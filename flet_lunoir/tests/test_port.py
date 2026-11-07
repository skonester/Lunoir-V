import re
import tempfile
import unittest
from pathlib import Path

from flet_lunoir import formatting as fmt
from flet_lunoir import options, playlist
from flet_lunoir.i18n import I18N_DIR, LOCALES, Translator, dictionary, parse_locale, resolve_system_locale
from flet_lunoir.profile import Profile, queue_key


class I18nTest(unittest.TestCase):
    def test_every_lunoir_key_parses_in_every_locale(self):
        for code in LOCALES:
            source = (I18N_DIR / f"{code}.ts").read_text(encoding="utf-8")
            keys = set(re.findall(r"^\s*'([a-zA-Z0-9_.]+)'\s*:", source, re.M))
            self.assertTrue(keys, code)
            self.assertEqual(keys, set(dictionary(code)), code)

    def test_escapes_placeholders_and_fallbacks(self):
        parsed = parse_locale("  'a': 'it\\'s\\nfine',\n  'b':\n    \"x \\u00e9\",\n")
        self.assertEqual(parsed, {"a": "it's\nfine", "b": "x é"})
        t = Translator("de")
        self.assertEqual(t("osc.back", n=10), dictionary("de")["osc.back"].replace("{n}", "10"))
        self.assertEqual(t("not.a.key"), "not.a.key")
        self.assertEqual(Translator("system", system_tag="zh-Hans-CN").locale, "zh-CN")
        self.assertEqual(resolve_system_locale("zh-TW"), "en")
        self.assertEqual(resolve_system_locale("pt_BR"), "pt")


class PlaylistTest(unittest.TestCase):
    def test_local_m3u_titles_relative_paths_and_file_urls(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "list.m3u"
            text = ('\ufeff#EXTM3U\n#EXTINF:-1 tvg-name="a, b",Episode 1\nshow/one.mkv\n'
                    '"two.mp4"\nfile:///C:/Media/three%20x.mkv\nhttps://example.com/v.mp4\n')
            entries = playlist.parse_local_m3u(str(source), text)
        self.assertEqual(entries[0].title, "Episode 1")
        self.assertEqual(entries[0].path, str((Path(directory) / "show/one.mkv").resolve()))
        self.assertEqual(entries[1].title, "two.mp4")
        self.assertEqual(entries[2].path, r"C:\Media\three x.mkv")
        self.assertEqual(entries[3].path, "https://example.com/v.mp4")

    def test_channel_lists_in_m3u_and_txt_forms(self):
        m3u = ('#EXTM3U\n#EXTINF:-1 group-title="News",World, Live\nhttp://a/1.m3u8\n'
               '#EXTINF:-1,No group\nhttps://a/2\n#EXTINF:-1,Skipped\nrtmp://not-http\n')
        channels = playlist.parse_channel_list(m3u)
        self.assertEqual([(c.title, c.group) for c in channels], [("World, Live", "News"), ("No group", "")])
        txt = "Sport,#genre#\nOne,http://b/1\nbad line\nTwo,https://b/2\n"
        self.assertEqual([(c.title, c.path, c.group) for c in playlist.parse_channel_list(txt)],
                         [("One", "http://b/1", "Sport"), ("Two", "https://b/2", "Sport")])

    def test_routing_and_folder_scan(self):
        self.assertTrue(playlist.is_local_queue(r"C:\a\b.M3U"))
        self.assertFalse(playlist.is_local_queue("http://x/b.m3u"))
        self.assertTrue(playlist.is_channel_list("http://x/list.txt?token=1"))
        self.assertFalse(playlist.is_channel_list("http://x/live.m3u8"))
        with tempfile.TemporaryDirectory() as directory:
            for name in ("ep10.mkv", "ep2.mkv", "ep1.MP4", "notes.txt", "noext"):
                (Path(directory) / name).write_text("")
            (Path(directory) / "sub.mkv").mkdir()
            names = [Path(p).name for p in playlist.scan_folder(directory)]
        self.assertEqual(names, ["ep1.MP4", "ep2.mkv", "ep10.mkv"])


class OptionsTest(unittest.TestCase):
    def test_settings_map_to_lunoir_properties(self):
        s = dict(Profile(Path(tempfile.mkdtemp())).settings, screenshotDir="D:/shots")
        self.assertEqual(options.properties_for("subFont", s), [("sub-font", "Microsoft YaHei")])
        s["subFont"] = "Segoe UI"
        self.assertEqual(options.properties_for("subFont", s), [("sub-font", "Segoe UI,Microsoft YaHei")])
        self.assertEqual(options.properties_for("autoLoadSubs", s), [("sub-auto", "fuzzy")])
        self.assertEqual(options.properties_for("audioPassthrough", s), [("audio-spdif", "")])
        s["screenshotFormat"] = "jpg"
        self.assertIn(("screenshot-jpeg-quality", 95), options.properties_for("screenshotFormat", s))
        self.assertEqual(options.properties_for("oscStyle", s), [])
        startup = dict(options.startup_properties(s))
        self.assertEqual(startup["screenshot-directory"], "D:/shots")
        self.assertEqual(startup["volume"], 100)
        self.assertEqual(startup["image-subs-hdr-peak"], 120)


class FormattingTest(unittest.TestCase):
    def test_readouts_and_badges(self):
        self.assertEqual(fmt.clock(65), "01:05")
        self.assertEqual(fmt.clock(3725), "1:02:05")
        self.assertEqual(fmt.timecode(fmt.current_frame(0, 10.5, 24), 23.976), "00:00:10:12")
        self.assertEqual(fmt.audio_badge("eac3", 6), "DD+ 5.1")
        self.assertEqual(fmt.audio_badge("pcm_s16le", 2), "PCM 2.0")
        self.assertEqual(fmt.resolution_tier(1920, 800), 1080)
        self.assertEqual(fmt.resolution_tier(960, 544), 540)
        self.assertEqual(fmt.screenshot_template("Show.S01E02.1080p.WEB-DL.x264-GRP.mkv", 3725),
                         "Show.S01E02_01-02-05_%ty%tm%td_%tH%tM%tS")
        self.assertEqual(fmt.clean_base_name("100%.mkv"), "100")


class QueueKeyTest(unittest.TestCase):
    def test_matches_lunoirs_javascript_hash(self):
        # values from Lunoir's hashStr under Node, including a surrogate pair
        paths = ["C:/v/\u7535\u5f71 01.mkv", "https://www.youtube.com/watch?v=a", "\U0001F600.mp4"]
        self.assertEqual(queue_key(paths), "pl:hhu0et")
        self.assertEqual(queue_key([""]), "pl:0")


class ProfileSelectionsTest(unittest.TestCase):
    def test_track_choices_survive_and_keep_attached_files(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            p = Profile(path)
            p.save_audio("film.mkv", {"type": "embedded", "id": 2})
            p.save_subtitle("film.mkv", {"type": "external", "path": "C:/s/en.srt"})
            p.save_subtitle("film.mkv", {"type": "none"})
            p.save_audio("film.mkv", {"type": "embedded", "id": "bad"})
            restored = Profile(path)
            self.assertEqual(restored.audio["film.mkv"], {"type": "embedded", "id": 2})
            self.assertEqual(restored.subtitles["film.mkv"]["type"], "none")
            self.assertEqual(restored.subtitle_files("film.mkv"), ["C:/s/en.srt"])
            (path / "audio-selections.json").write_text('{"x": {"type": "external"}}', encoding="utf-8")
            self.assertEqual(Profile(path).audio, {})

    def test_playlist_progress_and_recent_rename(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Profile(Path(directory))
            p.save_playlist_item("file:c:\\list.m3u", "b.mkv")
            p.recent("https://x/v", "https://x/v", "url")
            p.rename_recent("https://x/v", "Real title")
            restored = Profile(Path(directory))
            self.assertEqual(restored.playlist_items, {"file:c:\\list.m3u": "b.mkv"})
            self.assertEqual(restored.recents[0]["name"], "Real title")
            self.assertTrue(p.toggle_favourite("list.m3u", "List", "list", channels=[]))
            self.assertEqual(Profile(Path(directory)).favourites[0]["kind"], "list")
