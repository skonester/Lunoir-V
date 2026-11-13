# Lunoir's native V application

App version **0.2.0** is sourced from root `VERSION` and embedded in the executable.
The General/About panel and startup log show it; the portable package includes the
same file. The separate `v_mpv` binding manifests remain at `0.1.0`.

This directory is the manual port of the existing `flet_lunoir/` Python application.
`Lunoir-V.exe` runs the application logic in V and uses the existing `mpv/` module
directly. Flet 1.0.5's Flutter desktop client retains Lunoir's interface. Python,
pywin32, the Python Flet package and `vmpv-host` are not runtime dependencies.

## Build and run

From the repository root, with V 0.5.2 and GCC on PATH:

```powershell
./build-native.ps1
./Lunoir-V.exe
./package-native.ps1 -SkipBuild -Zip
```

The first build downloads the official, checksum-pinned Flet desktop client if it is
missing. Later builds accept `-SkipDependencies`. The old `build-flet.ps1` and
`package-flet.ps1` names forward to these native scripts. The portable package contains
the V executable, libmpv, Flet/Flutter, assets, translations and licenses.

## Port map

| Python reference | V implementation |
|---|---|
| `app.py`, `panels.py`, `__main__.py` | `main.v`, `app.v`, `media.v`, `input.v`, `panels.v`, `library.v` |
| Flet SDK controls, transport and event handlers | `flet.v`, `msgpack.v`, embedded shell/settings templates and icon data |
| `backend.py` and asyncio host IPC | `backend.v`, direct `import mpv`, main-loop event processing |
| `native_video.py`, Win32 calls and process jobs | `native_video.v`, `platform_windows.c.v`, `platform_win.h` |
| `instance.py`, `drop.py` | `instance.v`, `drop_windows.c.v`, `drop_win.h` |
| `thumbs.py` | `thumbs.v`, a second in-process mpv handle |
| `profile.py`, `playlist.py`, `options.py`, `formatting.py`, `i18n.py`, `ytdl.py` | Corresponding V files |

The port includes floating/docked OSC, auto-hide, keyboard/mouse actions, zoom/pan,
file and URL dialogs, tracks and subtitle adjustments, playlists/IPTV, chapters, library,
four settings tabs, nine languages, resume and track memory, screenshots, previews,
single instance, OS drops and yt-dlp downloads/updates/playlist expansion. Existing
profile JSON formats and instance names are retained.

The JSON layouts are serialized control data from the existing Flet interface. They
contain translation-key markers and declarative event bindings, resolved entirely in
V. The original translations remain under `lunoir/src/shared/i18n/`; do not duplicate
them as V strings. Do not localize protocol fields such as `_c` (control class).

The original Lunoir features listed as unimplemented in the main README remain outside
this migration's scope; the Python implementation did not supply them either.

## Local validation

The user has since prohibited further local test-video runs and requested focusing
on yt-dlp. The commands below document earlier validation; do not rerun the media
suites unless that restriction is lifted.

The subsequent yt-dlp fix was checked against the supplied online video
`https://www.youtube.com/watch?v=A7kKxad9tWM`: a direct audio request returned HTTP
403, then the app's single automatic HLS retry played 1920x1080 video with AAC audio.
Two state-only checks in `ytdl_retry_test.v` cover host/quality selection, late HTTP
error delivery after `end-file`, and the one-retry limit. They do not start mpv or
open media. The selected quality cap is retained and normal selection is restored
for the next queue item. Detailed mpv diagnostics are opt-in through
`LUNOIR_V_MPV_LOG`; regular warnings/errors are now recorded in `native.log`.

Checked on 2026-11-13 with V 0.5.2/GCC 15.2: all three V test files (11 test
functions) and all three executable integration tests passed. The executable tests
also passed against a portable copy outside the checkout. A clean source copy
downloaded the pinned runtime and built through the compatibility entry point.
The portable folder is approximately 195 MiB; its zip is approximately 80 MiB.

```powershell
./tools/test-native.ps1
python tools/test-native-ui.py -v
python tools/test-native-ui.py --exe C:/portable/Lunoir-V/Lunoir-V.exe --artifacts dist/native-validation -v
```

Python in the last two commands is a development-only test runner. It creates media
fixtures through a small V/mpv program, launches the V executable, reads test state and
checks process lifetime. The tested application runs with PATH restricted to System32
and no Python in its package.

V tests cover formatting, natural ordering, playlist parsing, Unicode-compatible queue
hashes, profile persistence, track labels, all locales, Flet control schema, MessagePack
and malformed frames, real COM file/URL drop data objects, singleton forwarding, actual
libmpv playback/seek/preview/track restoration/screenshots, and HTTP update success,
checksum mismatch, truncated downloads and server errors. Download failure cases retain
the previous executable and remove partial files.

Executable integration tests cover external audio/subtitle restoration, resume, live
volume changes, panel rendering, runtime language switching, modal dismissal, screenshots,
a second launch from another working directory, saved settings, and cleanup when either
the V controller or Flet client is killed. Flutter captures can be retained with
`--artifacts` for visual inspection; native video is verified with mpv screenshots.

Real Explorer/browser dragging, physical mouse hover/wheel/pan, fullscreen and HiDPI
still need hands-on checking. The desktop input helper was unavailable during this
migration; COM tests and in-process handlers do not establish those physical input paths.

## Archived py2v attempt

`generated/py_flet_lunoir/`, `translation.txt`, `diagnostics.txt` and `conversion.json`
record the earlier automatic conversion: 16 files emitted, 619 compiler errors.
That output is not imported by the application or included in the portable package.
The working manual sources live directly in this directory.

`convert-python.ps1 -Py2v <py2v.exe>` regenerates only the archive and its reports.
`tools/py2v/prepare.ps1` can build the supplied transpiler in an isolated temporary copy
using a newer V compiler; it does not modify the manually ported application.
