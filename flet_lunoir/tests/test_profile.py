import tempfile
import unittest
from pathlib import Path

from flet_lunoir.profile import Profile


class ProfileTest(unittest.TestCase):
    def test_resume_and_finished_media(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Profile(Path(directory))
            p.save_position("film.mkv", 24, 100, True)
            p.save_position("live", 30, 0, False)
            self.assertEqual(Profile(Path(directory)).positions, {"film.mkv": 24})
            p.save_position("film.mkv", 99, 100, True)
            self.assertNotIn("film.mkv", Profile(Path(directory)).positions)

    def test_recents_cap_deduplication_and_unicode(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Profile(Path(directory))
            for index in range(25):
                p.recent(str(index), f"影片 {index}")
            p.recent("5", "Renamed")
            restored = Profile(Path(directory))
            self.assertEqual(len(restored.recents), 20)
            self.assertEqual(restored.recents[0]["name"], "Renamed")
            self.assertEqual(sum(item["target"] == "5" for item in restored.recents), 1)
            self.assertIn("影片", (Path(directory) / "recents.json").read_text(encoding="utf-8"))

    def test_invalid_profile_falls_back_and_favourites_toggle(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "settings.json").write_text("[]", encoding="utf-8")
            p = Profile(path)
            self.assertEqual(p.settings["volume"], 100)
            p.toggle_favourite("one", "One")
            self.assertEqual(len(Profile(path).favourites), 1)
            p.toggle_favourite("one", "One")
            self.assertEqual(Profile(path).favourites, [])
