import asyncio
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from flet_lunoir import ytdl


class YtdlTest(unittest.TestCase):
    def test_which_urls_go_through_ytdlp(self):
        self.assertTrue(ytdl.needs_ytdl("https://www.youtube.com/watch?v=abc"))
        self.assertTrue(ytdl.needs_ytdl("https://youtu.be/abc"))
        self.assertFalse(ytdl.needs_ytdl("https://cdn.example/live/index.m3u8?token=1"))
        self.assertFalse(ytdl.needs_ytdl("https://cdn.example/a.mp4#t=5"))
        self.assertFalse(ytdl.needs_ytdl("rtmp://example/live"))
        self.assertTrue(ytdl.is_playlist_url("https://www.youtube.com/playlist?list=PL123&si=x"))
        self.assertFalse(ytdl.is_playlist_url("https://www.youtube.com/watch?v=abc&list=PL123"))
        self.assertEqual(ytdl.playlist_key("https://www.youtube.com/playlist?list=PL123&si=x"), "list:PL123")

    def test_error_reason_drops_the_boilerplate(self):
        line = ("ERROR: [youtube] abc: Join this channel to get access to members-only content; "
                "please report this issue on https://github.com/yt-dlp/yt-dlp/issues")
        self.assertEqual(ytdl.error_text(line), "[youtube] abc: Join this channel to get access to members-only content")
        self.assertEqual(ytdl.error_text("youtube-dl failed: not found or not enough permissions"), "")
        self.assertTrue(ytdl.OUTDATED.search("ERROR: unable to extract; your yt-dlp version is out of date"))

    def test_playlist_entries_from_flat_print(self):
        with tempfile.TemporaryDirectory() as folder:
            tool = ytdl.Ytdl(Path(folder))
            tool.exe.parent.mkdir()
            tool.exe.write_bytes(b"")  # present and fresh: no download
            out = ("https://www.youtube.com/watch?v=a ||| Première vidéo\n"
                   "NA ||| private video\n"
                   "https://www.youtube.com/watch?v=b ||| \n").encode()
            with mock.patch.object(subprocess, "run", return_value=mock.Mock(stdout=out)) as run:
                entries = asyncio.run(tool.playlist("https://www.youtube.com/playlist?list=PL1"))
            self.assertIn("--flat-playlist", run.call_args.args[0])
            self.assertEqual([(e.path, e.title) for e in entries],
                             [("https://www.youtube.com/watch?v=a", "Première vidéo"),
                              ("https://www.youtube.com/watch?v=b", "https://www.youtube.com/watch?v=b")])


if __name__ == "__main__":
    unittest.main()
