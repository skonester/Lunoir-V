"""The OSC's volume slider and the Update button, on the real methods with a stub UI."""
import asyncio
from types import SimpleNamespace
import unittest
from unittest import mock

from flet_lunoir import options
from flet_lunoir.app import Lunoir


def stub_app(volume=100, mute=False) -> Lunoir:
    app = Lunoir.__new__(Lunoir)
    for name in ("mute_button", "play_button", "seek", "time_text", "duration_text", "badges", "title", "page",
                 "toast", "toast_text"):
        setattr(app, name, mock.MagicMock())
    app.t = lambda key, **_: key
    app.settings = {}
    app.current, app.source_type, app.index, app.queue = "", "queue", -1, []
    app.dragging = app.volume_dragging = False
    app.properties = {"volume": volume, "mute": mute}
    app.volume = SimpleNamespace(value=float(volume))
    app.sent = []
    async def set_property(name, value):
        app.sent.append((name, value))
    app.set_property = set_property
    return app


def slide(value):
    # control.value deliberately disagrees: update_transport overwrites it between events
    return SimpleNamespace(data=value, control=SimpleNamespace(value=0.0))


class VolumeSliderTest(unittest.TestCase):
    def test_a_click_sets_the_clicked_value_not_the_old_one(self):
        app = stub_app()
        async def run():
            await app.volume_start(slide(100.0))
            await app.volume_change(slide(74.6))
            await app.volume_end(slide(74.6))
        asyncio.run(run())
        self.assertEqual(app.sent, [("volume", 75)])
        self.assertEqual(app.volume.value, 75)
        self.assertFalse(app.volume_dragging)

    def test_the_volume_follows_the_thumb_during_a_drag(self):
        app = stub_app()
        async def run():
            await app.volume_start(slide(100.0))
            for value in (90.2, 90.4, 80.0):
                await app.volume_change(slide(value))
        asyncio.run(run())
        self.assertEqual(app.sent, [("volume", 90), ("volume", 80)])

    def test_playback_updates_leave_a_held_thumb_alone(self):
        app = stub_app()
        app.volume_dragging = True
        app.volume.value = 42.0
        app.properties["volume"] = 100
        app.update_transport()
        self.assertEqual(app.volume.value, 42.0)
        app.volume_dragging = False
        app.update_transport()
        self.assertEqual(app.volume.value, 100)

    def test_muted_shows_empty_and_moving_it_unmutes(self):
        app = stub_app(mute=True)
        app.update_transport()
        self.assertEqual(app.volume.value, 0)
        asyncio.run(app.volume_end(slide(60.0)))
        self.assertEqual(app.sent, [("mute", False), ("volume", 60)])
        self.assertEqual(app.volume.value, 60)

    def test_muting_keeps_the_volume_for_unmuting(self):
        app = stub_app(volume=70, mute=True)
        app.update_transport()
        self.assertEqual(app.properties["volume"], 70)
        app.properties["mute"] = False
        app.update_transport()
        self.assertEqual(app.volume.value, 70)

    def test_the_icon_reads_muted_at_zero(self):
        import flet as ft
        app = stub_app(volume=0)
        app.update_transport()
        self.assertEqual(app.mute_button.icon, ft.Icons.VOLUME_OFF_ROUNDED)
        app.properties["volume"] = 5
        app.update_transport()
        self.assertEqual(app.mute_button.icon, ft.Icons.VOLUME_UP_ROUNDED)


class UpdateButtonTest(unittest.TestCase):
    def app_with(self, result, version="2030.01.02", replaced=True):
        app = stub_app()
        app.ytdl_state, app.panel_mode = "idle", ""
        app.notify = mock.MagicMock()
        app.fill_panel = mock.MagicMock()
        app.refresh = mock.MagicMock()
        app.try_set = mock.AsyncMock()
        app.ytdl = SimpleNamespace(refresh=mock.AsyncMock(return_value=result), version=version, replaced=replaced)
        return app

    def test_success_names_the_version_and_points_mpv_at_it(self):
        app = self.app_with("C:\\p\\yt-dlp.exe")
        asyncio.run(app.refresh_ytdl())
        self.assertEqual(app.ytdl_state, "done")
        app.try_set.assert_awaited_once_with("script-opts", "ytdl_hook-ytdl_path=C:/p/yt-dlp.exe")
        app.notify.assert_called_with("main.ytdlUpdated · yt-dlp 2030.01.02")

    def test_already_latest_does_not_claim_an_update(self):
        app = self.app_with("C:\\p\\yt-dlp.exe", replaced=False)
        asyncio.run(app.refresh_ytdl())
        app.notify.assert_called_with("set.ytdl.done · yt-dlp 2030.01.02")

    def test_failure_re_enables_the_button(self):
        app = self.app_with(None)
        asyncio.run(app.refresh_ytdl())
        self.assertEqual(app.ytdl_state, "error")
        app.notify.assert_called_with("main.ytdlFailed")

    def test_the_panel_shows_working_before_the_download_finishes(self):
        app = self.app_with("x")
        app.panel_mode = "settings"
        seen = []
        app.refresh.side_effect = lambda: seen.append(app.ytdl_state)
        asyncio.run(app.refresh_ytdl())
        self.assertEqual(seen[0], "working")
        self.assertEqual(seen[-1], "done")

    def test_a_second_click_while_working_is_ignored(self):
        app = self.app_with("x")
        app.ytdl_state = "working"
        asyncio.run(app.refresh_ytdl())
        app.ytdl.refresh.assert_not_awaited()


class QualityTest(unittest.TestCase):
    def test_best_quality_asks_for_separate_streams(self):
        # "" makes yt-dlp fall back to the best single file: 360p on YouTube
        self.assertEqual(options.properties_for("streamQuality", {"streamQuality": "best"}),
                         [("ytdl-format", "bestvideo+bestaudio/best")])


if __name__ == "__main__":
    unittest.main()
