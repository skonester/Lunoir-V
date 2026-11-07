"""Checks an unpacked portable build with nothing but itself.

Run with the build's own python/python.exe, and PATH cut to Windows' folders. It plays a
synthetic source through vmpv-host and libmpv-2.dll. It opens no windows, so Flet's
interface itself is not exercised here.
"""
import asyncio
from pathlib import Path
import struct
import sys
import tempfile

ROOT = Path(sys.executable).resolve().parent.parent
X86_64 = 0x8664
PROGRAMS = ("Lunoir-V.exe", "python/python.exe", "flet_lunoir/runtime/vmpv-host.exe",
            "flet_lunoir/runtime/libmpv-2.dll", "flet_lunoir/runtime/flet/flet/flet.exe")
FILES = ("LICENSE", "README.md", "lunoir/LICENSE", "lunoir/CREDITS.md", "lunoir/src/renderer/src/assets/logo.png")


def machine(path: Path) -> int:
    with path.open("rb") as program:
        program.seek(0x3C)
        program.seek(struct.unpack("<I", program.read(4))[0] + 4)
        return struct.unpack("<H", program.read(2))[0]


async def play() -> str:
    from flet_lunoir.backend import MpvController
    with tempfile.TemporaryDirectory() as logs:
        player = MpvController(Path(logs))
        await player.start(extra_args=["--vo=null", "--ao=null"], observe=False)
        try:
            await player.command("loadfile", "av://lavfi:testsrc=duration=2:size=64x64:rate=10")
            while (await asyncio.wait_for(player.events.get(), 30)).get("event") != "file-loaded":
                pass
            return await player.command("get_property", "mpv-version")
        finally:
            await player.close()


def main() -> None:
    for name in PROGRAMS:
        assert machine(ROOT / name) == X86_64, f"{name} is not x86_64"
    for name in FILES:
        assert (ROOT / name).is_file(), f"{name} is missing"

    import flet  # noqa: F401
    import flet_lunoir
    import win32api  # noqa: F401
    from flet_lunoir import app, i18n, ytdl  # noqa: F401
    source = Path(flet_lunoir.__file__).resolve()
    assert source.is_relative_to(ROOT), f"loaded the app from {source}, not this build"
    assert Path(flet.__file__).resolve().is_relative_to(ROOT), "loaded Flet from outside this build"
    assert len(i18n.LOCALES) == 9 and i18n.dictionary("en"), "the translations did not load"

    print("mpv:", asyncio.run(play()))
    # the yt-dlp updater depends on this build's TLS and certificates
    print("latest yt-dlp:", ytdl.latest_tag())
    print("The portable build is good.")


if __name__ == "__main__":
    main()
