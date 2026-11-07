"""The updater against a loopback copy of GitHub's release addresses."""
import asyncio
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest import mock

from flet_lunoir import ytdl

TAG = "2030.01.02"
NEW = b"MZ new yt-dlp" * 100


class Releases(BaseHTTPRequestHandler):
    body = NEW
    published = hashlib.sha256(NEW).hexdigest()
    claimed_length = None  # more than the body: the connection "drops" mid-download
    latest_status = 302
    downloads = 0

    def do_GET(self):
        if self.path == "/latest":
            self.send_response(self.latest_status)
            self.send_header("Location", f"/tag/{TAG}")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.path == f"/tag/{TAG}":
            self.reply(b"<html>release page</html>")
        elif self.path == f"/download/{TAG}/SHA2-256SUMS":
            self.reply(f"{'0' * 64}  yt-dlp\n{self.published}  yt-dlp.exe\n".encode())
        elif self.path == f"/download/{TAG}/yt-dlp.exe":
            type(self).downloads += 1
            self.reply(self.body, self.claimed_length)
        else:
            self.send_error(404)

    def reply(self, body, length=None):
        self.send_response(200)
        self.send_header("Content-Length", str(length or len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class UpdateTest(unittest.TestCase):
    def setUp(self):
        for name, value in (("body", NEW), ("published", hashlib.sha256(NEW).hexdigest()),
                            ("claimed_length", None), ("latest_status", 302), ("downloads", 0)):
            setattr(Releases, name, value)
        server = ThreadingHTTPServer(("127.0.0.1", 0), Releases)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        patch = mock.patch.object(ytdl, "RELEASES", f"http://127.0.0.1:{server.server_port}")
        patch.start()
        self.addCleanup(patch.stop)
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.tool = ytdl.Ytdl(Path(folder.name))

    def install_old(self) -> None:
        self.tool.exe.parent.mkdir()
        self.tool.exe.write_bytes(b"old copy")

    def refresh(self, version="2020.01.01"):
        async def run():
            return await self.tool.refresh()
        with mock.patch.object(ytdl, "installed_version", return_value=version):
            return asyncio.run(run())

    def leftovers(self):
        return [path.name for path in self.tool.exe.parent.iterdir() if path != self.tool.exe]

    def test_new_release_replaces_the_copy(self):
        self.install_old()
        self.assertEqual(self.refresh(), str(self.tool.exe))
        self.assertEqual(self.tool.exe.read_bytes(), NEW)
        self.assertEqual(self.tool.version, TAG)
        self.assertTrue(self.tool.replaced)
        self.assertEqual(self.leftovers(), [])

    def test_first_download_makes_the_folder(self):
        self.assertEqual(self.refresh(version=""), str(self.tool.exe))
        self.assertEqual(self.tool.exe.read_bytes(), NEW)

    def test_already_latest_skips_the_download_and_resets_the_age(self):
        self.install_old()
        os.utime(self.tool.exe, (time.time() - 30 * 86400,) * 2)
        self.assertTrue(self.tool.stale())
        self.assertEqual(self.refresh(version=TAG), str(self.tool.exe))
        self.assertEqual(Releases.downloads, 0)
        self.assertEqual(self.tool.exe.read_bytes(), b"old copy")
        self.assertFalse(self.tool.replaced)
        self.assertFalse(self.tool.stale())

    def test_dropped_connection_keeps_the_old_copy(self):
        self.install_old()
        Releases.claimed_length = len(NEW) * 2
        Releases.body = NEW[:100]
        self.assertIsNone(self.refresh())
        self.assertEqual(self.tool.exe.read_bytes(), b"old copy")
        self.assertEqual(self.leftovers(), [])

    def test_checksum_mismatch_keeps_the_old_copy(self):
        self.install_old()
        Releases.published = "f" * 64
        self.assertIsNone(self.refresh())
        self.assertEqual(self.tool.exe.read_bytes(), b"old copy")
        self.assertEqual(self.leftovers(), [])

    def test_failed_first_download_leaves_nothing_runnable(self):
        Releases.published = "f" * 64
        self.assertIsNone(self.refresh(version=""))
        self.assertFalse(self.tool.exe.exists())

    def test_unreachable_github_is_a_failure_not_an_exception(self):
        self.install_old()
        Releases.latest_status = 500
        self.assertIsNone(self.refresh())
        self.assertEqual(self.tool.exe.read_bytes(), b"old copy")

    def test_stale_copy_is_usable_at_once_while_it_updates_behind(self):
        self.install_old()
        os.utime(self.tool.exe, (time.time() - 30 * 86400,) * 2)
        async def run():
            path = await self.tool.ensure()
            still_old = self.tool.exe.read_bytes()
            self.assertTrue(self.tool.downloading)
            await self.tool.task
            return path, still_old
        with mock.patch.object(ytdl, "installed_version", return_value="2020.01.01"):
            path, still_old = asyncio.run(run())
        self.assertEqual((path, still_old), (str(self.tool.exe), b"old copy"))
        self.assertEqual(self.tool.exe.read_bytes(), NEW)

    def test_update_during_a_background_refresh_joins_it(self):
        self.install_old()
        async def run():
            first, second = self.tool.refresh(), self.tool.refresh()
            return await asyncio.gather(first, second)
        with mock.patch.object(ytdl, "installed_version", return_value="2020.01.01"):
            self.assertEqual(asyncio.run(run()), [str(self.tool.exe)] * 2)
        self.assertEqual(Releases.downloads, 1)

    def test_a_copy_that_does_not_run_has_no_version(self):
        self.install_old()
        self.assertEqual(ytdl.installed_version(self.tool.exe), "")
        self.assertEqual(ytdl.installed_version(self.tool.exe.with_name("missing.exe")), "")


if __name__ == "__main__":
    unittest.main()
