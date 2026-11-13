# AGENTS.md — v-mpv working notes

Everything needed to build, test and continue this project. `README.md` only says what
it is.

## Picking this up

Repository: https://github.com/skonester/Lunoir-V (private as of 2026-11-07, so the Actions
API needs a sign-in). `libmpv-2.dll` is 94 MiB: under GitHub's 100 MB limit, above its
50 MB warning. Exporting what git would add and running `build-flet.ps1` and the Python
tests there was checked 2026-11-07.

## Current application: manual V port (2026-11-13)

Testing restriction from the user (2026-11-13): do not run any further local test
video files; focus on yt-dlp. Do not run `tools/test-native.ps1`,
`tools/test-native-ui.py`, or the complete V app test suite while this restriction
applies: they create/play local media. Use targeted non-media checks and the supplied
online URL instead.

The user requested moving the existing Python application to V. `v_lunoir/` now
builds the player, including its Flet socket transport, UI state, settings/profile,
media queues, library, playback, previews, single instance, Windows drops and yt-dlp.
`Lunoir-V.exe` is the controller itself. It imports `mpv` directly; it does not launch
Python or `vmpv-host`. Flet/Flutter still draws Lunoir's interface. Keep that interface
and its assets; do not create a separate Win32 player.

```powershell
./build-native.ps1                     # V/GCC; downloads pinned Flet runtime if missing
./build-native.ps1 -SkipDependencies
./Lunoir-V.exe
./package-native.ps1 [-Zip] [-SkipBuild] # dist/Lunoir-V, no Python
./tools/test-native.ps1                # local V tests, including real libmpv/COM/HTTP
python tools/test-native-ui.py -v       # optional development-only executable integration tests
```

`build-flet.ps1` and `package-flet.ps1` are compatibility wrappers for the native
scripts. CI uses the native scripts with pinned V 0.5.2/GCC 15.2, without Python setup.
Preserve the user's rule: CI builds/packages/releases; run tests locally, never add
test gates between a push and the zip.

Implementation notes:

- The app version is `0.2.0`, sourced from root `VERSION`, embedded by
  `v_lunoir/version.v`, shown in General/About and the startup log, and included in
  the portable package. Bump `VERSION` for app releases (`v0.2.0` for this version).
  Root and `mpv/v.mod` describe the binding, which remains version `0.1.0`.
- `flet.v`/`msgpack.v` implement the Flet 1.0.5 desktop protocol. The embedded
  `shell.json`, `ui_templates.json` and `icons.json` retain the Python app's control
  layouts and event bindings; they are data, not Python execution. Localized text
  resolves through the existing TypeScript translation files. Never translate `_c`
  control class names or other schema fields.
- `backend.v` drives the existing `mpv/` binding directly. All mutable app state and
  mpv event processing stay on the main loop; download/socket workers communicate
  through channels. The main and preview mpv handles run inside the V process.
- YouTube 403 recovery: extraction can succeed while mpv's direct audio request is
  refused. `media.v` records HTTP failures and `ytdl.v` retries a YouTube load once
  with HLS video/audio, preserving the selected height cap. Each new queue item
  resets this fallback and restores normal format selection. Warnings/errors now
  go to `native.log`; `LUNOIR_V_MPV_LOG=<path>` enables detailed mpv/ytdl diagnostics.
- `platform_win.h`, `drop_win.h` and their V wrappers replace pywin32/ctypes. Flet
  joins a kill-on-close Windows job. Single-instance names and profile formats remain
  compatible with the Python implementation. Native video regions preserve the
  floating OSC/panel airspace strategy described in the historical notes below.
- Use `json_decode`/`json_encode` in `json.v`; the pinned generic JSON2 decoder expects
  sum-type tags that ordinary profile/mpv JSON does not contain. `object`/`list_value`
  must reject scalar variants; JSON2's coercing `.as_map()`/`.as_array()` are unsuitable.
- V tests require `-subsystem console` for visible diagnostics; the test script sets
  the DLL search path. Avoid implicit conversion of unary `!x` into `json2.Any`: the
  pinned compiler generates invalid C for it. Assign the bool to a local first.
- Test hooks: `LUNOIR_V_TEST_SCRIPT` runs timed app actions on scratch profiles;
  `LUNOIR_V_EXIT_AFTER` limits a test run. F9 captures Flutter rendering with
  `LUNOIR_V_SNAPSHOTS`; timed captures additionally require
  `LUNOIR_V_SNAPSHOT_INTERVAL` (ms). Native video is absent from Flutter captures;
  use mpv's screenshot command to verify decoded frames.
- `flet_lunoir/` and `host/` remain reference implementations. Python is needed only
  to run their development tools/tests. The old py2v output under
  `v_lunoir/generated/` and its conversion reports are archival, unbuildable output;
  they are neither imported nor packaged. `convert-python.ps1` touches that archive,
  not the manual V sources. See `v_lunoir/README.md` for validation and limitations.

## Historical state as of 2026-10-25

- The `mpv/` module binds the whole go-mpv API and is tested against our
  `libmpv-2.dll` with GCC and TCC. Copied alone into another project, it builds and runs.
- `flet_lunoir/` rebuilds Lunoir's interface in Flet/Python, with the existing V
  binding host as its playback backend. `build-flet.ps1` builds the host and
  `Lunoir-V.exe`, a console-free V entry point. Double-click that executable.
  Second pass done: floating auto-hiding OSC, translations, full settings, track
  memory, M3U/IPTV, menu actions (details below). 2026-10-28: single instance
  per profile, OS file/link drops, a self-contained package, seek-bar previews.
- Unproven: the OpenGL render path (written, never run), Linux/macOS (`#pkgconfig`
  path never built), and any real V app on the binding beyond `host/`.
- `host/ipc.v` now uses an atomic closing flag and wakes the event thread on pipe
  write failure; the earlier unsynchronised flag has been fixed.
- Not packaged: the module is a folder in this repo, not installable with `v install`.

The user rejected a separate native Win32 player and chose Flet for Lunoir's interface.
The later V migration retains Flet and replaces its Python controller. Do not recreate
the separate `player/` application. The behavior/design reference is Lunoir 0.9.4 at
https://github.com/zhbj420/Lunoir. Notes below that name `main/mpv.ts`, `Library.tsx` and
so on mean that repo. Only what the app reads at run time is kept in `lunoir/`.

## Historical Python Flet port (2026-10-25)

The commands, packaging and Python architecture in this section describe the previous
implementation. The current build/package entry points above produce the native V app.

```powershell
./build-flet.ps1                       # venv, dependencies, Flet desktop runtime, V backend + launcher
./build-flet.ps1 -SkipDependencies     # rebuild with installed dependencies
./package-flet.ps1 [-Zip] [-SkipBuild] # self-contained dist/Lunoir-V (about 250 MB)
./Lunoir-V.exe                         # console-free desktop launch
.venv/Scripts/python.exe -m flet_lunoir # console diagnostics
.venv/Scripts/python.exe -m unittest discover -s flet_lunoir/tests -v
```

- Dependencies: Python 3.10+, Flet 1.0.5, pywin32 312, V and GCC. Setup downloads
  Flet's matching official Windows desktop runtime into the ignored
  `flet_lunoir/runtime/` folder. No Electron or Node is used by this front end.
- `flet_lunoir/backend.py` ports Lunoir's `main/mpv.ts` IPC controller to Python.
  It starts `runtime/vmpv-host.exe` on a unique named pipe and uses asyncio's
  overlapped pipe transport. All commands/events pass through V's `import mpv`.
- Host lifetime: closing the window sends `quit` and waits (then kills). As a safety
  net every host, and Flet's own `flet.exe` client, joins a kill-on-close job object
  held by the Python process, so a crash or kill of Python still ends them (without
  it a killed Python left `flet.exe` open on "Working...") (`test_host_dies_with_a_killed_front_end`;
  it kills the base interpreter, because the venv's `python.exe` redirector cleans
  up its children itself and would hide a missing job). `vmpv-host` started with no
  file, no `--input-ipc-server` and no `--idle` exits at once, as `mpv.exe` does;
  before 2026-10-25 a double-clicked host idled invisibly forever. Open quirk
  (2026-10-29): started *with* a file and no `--idle`, it does not exit when that
  file ends (mpv.exe does). The app always passes `--idle=yes`, so only
  command-line use is affected. Checked:
  `Lunoir-V.exe` closed by window close, the X button, right after start, and with
  `flet.exe` killed leaves no process behind.
- `native_video.py` supplies a disabled child HWND inside the Flet window for
  `--wid`; no Python mpv package or Flet video decoder is used. Flet cannot paint
  over a native window, so controls that float over the picture are shown through
  **region holes**: the child's `SetWindowRgn` excludes their rounded rectangles and
  Flet's drawing shows there. mpv's D3D11 (gpu-next) output is clipped by the region
  (checked). Because the child is disabled, Windows routes mouse input over the
  video to Flutter's `FLUTTERVIEW`, so a Flet `GestureDetector` under the video gets
  clicks: click = pause, double-click = fullscreen, right-click = menu panel.
- Module map: `app.py` window shell, layout/holes, auto-hide, queue and playback
  logic (Lunoir's `openMedia`/`playCurrent`/track restore), keys (`useShortcuts`);
  `panels.py` side panels (tracks + Adjust strip, playlist/channels with search,
  chapters, library, four-tab settings, the right-click menu as a panel, file info
  from mpv properties); `playlist.py` folder scan, local M3U queue, IPTV list parsing
  (`.m3u`/`.txt`; `.m3u8` is a stream); `options.py` settings to mpv properties
  (`applyMpvSettings`); `formatting.py` OSC readouts/badges and screenshot names;
  `i18n.py` parses Lunoir's own `lunoir/src/shared/i18n/*.ts` at run time (9
  locales, 305 keys), so do not copy strings into Python; `profile.py` Lunoir's
  `settings.ts` files and shapes (settings, positions, recents, favourites,
  audio/subtitle selections, playlist progress) under `%APPDATA%/Lunoir V`;
  `instance.py` Lunoir's `requestSingleInstanceLock`/`second-instance`; `drop.py`
  file and link drops; `thumbs.py` the seek-bar preview (`main/thumb.ts`); `ytdl.py`
  yt-dlp on demand.
  Logs: `%LOCALAPPDATA%/Lunoir V` (`ui.log`, `backend.log`). It reuses the original
  logo/wordmark from `lunoir/`; preserve Lunoir's MIT license and credits.
- `oscStyle`: `floating` (default) keeps the video full size with the OSC pill and
  panels in holes; the OSC auto-hides after `oscHideDelay` (cursor polled with
  `GetCursorPos`, so it works wherever Flutter's hover events go). `docked` reserves
  the video area above the bar and never hides it, like the first port.
- Grey holes: a newly cut hole can show the compositor's grey (RGB 105,105,105)
  until Flutter repaints that area, and Flutter re-presents only what changed in a
  frame (the clock, a hovered item), so it lingered for seconds. Seen by the user in
  fullscreen after a right-click: the bar moved left and only the newly uncovered
  strip plus the new panel were grey. Neither Flet window has a class background
  brush, so it is not GDI erasing. Mitigation: `schedule_repaint()` flips a
  full-window backdrop between two indistinguishable shades at 30/120/300 ms after
  any region or video-window change, forcing a full repaint. Flipping `page.bgcolor`
  instead rebuilt Flet's whole app and hung the session. Not reproduced with posted
  input (windowed or fullscreen, with or without the fix), so it is unconfirmed
  whether the mitigation fully removes it on real input.
- Single instance: a named mutex plus a message pipe, both keyed on a hash of the
  profile folder (as Electron keys its lock on userData), so a scratch-`APPDATA` run
  is separate from the real profile, but a plain `python -m flet_lunoir` with the
  real profile hands its arguments to an already open player and exits. The second
  launch resolves its arguments (`targetFromArgv`: flags skipped, missing paths
  dropped), waits up to 15 s for the first to start serving, then raises its window
  itself, because it is the process the user just launched and may take focus. A
  player that never answers gets a second, unlinked instance.
- Drops: the Flet window belongs to `flet.exe`, so no drop target can be registered
  on it. `drop.py` owns a layered popup (owned by the Flet window, on its own thread
  and message loop, alpha 1 so it is hit-testable yet invisible) that it shows over
  the client area while a mouse button pressed *outside* the player is held over
  it; OLE `RegisterDragDrop` on that popup takes the drop and it paints Lunoir's
  dashed `.drop-hint` once `DragEnter` sees files or a link. Files win, else the
  first http(s) line of dropped text (Lunoir's `onDrop`). Deviation: Lunoir opens
  only the first dropped file; several media files become the queue, as from the
  open dialog (`open_paths`, also used for launch arguments).
- Seek preview: a second, silent `vmpv-host` (Lunoir's `THUMB_ARGS`, no observed
  properties) embeds with `--wid` into a second `NativeVideo` child with rounded
  corners, raised above the main video; a native child needs no hole. Same rules as
  Lunoir: local files only (`syncThumb`), 320 physical px wide, height from the
  aspect (90-240), mpv's OSD writes the time, seeks throttled to 70 ms, a warm-up
  play for the first frame. Deviation: the file counts as ready only after its own
  load `playback-restart`; taking that one for the warm-up's ended the warm-up
  mid-seek (thumb.ts has the race, rarely hit there). Hover comes from the polled
  cursor (`update_preview`) against `seek_rect()`, which is computed from
  `build_ui`'s geometry; the slider has `padding=0` so its track spans the whole
  control. Checked against snapshots: thumb centres at value 0 and 1 within 0.5 px
  of `seek_rect()`. Any change to the pill's padding, border or rows must update
  `seek_rect()`.
- yt-dlp (`ytdl.py`, Lunoir's `ensureYtdl`/`refreshYtdl`/`loadPlaylistUrl`): a site
  URL (http(s) without a media extension, never IPTV) waits for
  `<profile>/yt-dlp/yt-dlp.exe`, downloaded from yt-dlp's latest GitHub release on
  first use and checked in the background once 14 days old, then sets
  `script-opts=ytdl_hook-ytdl_path=...` before `loadfile`; mpv's built-in `ytdl_hook`
  does the rest. `/playlist?` URLs expand with `--flat-playlist` into the queue (key
  `list:<id>`, last item resumed, never in recents). The host forwards `log-message`
  events at `error` level (`request_log_messages`), so a failed load toasts yt-dlp's own
  reason and an "outdated" reason triggers a refresh. Settings: quality cap and
  browser cookies (Playback tab), "Update now" (General tab, which also names the
  installed version). Deviations from Lunoir:
  `--encoding utf-8` for the playlist listing, since a pipe otherwise gets the ANSI code
  page. The "best" quality sends `bestvideo+bestaudio/best`, not `""`: with no format and
  no ffmpeg to merge, yt-dlp picks the best single file, 360p on YouTube.
  The version comes from where `releases/latest` redirects; a copy already on it is not
  downloaded again and its 14 days restart. A new copy must match the release's
  `SHA2-256SUMS` before it replaces the old one. `read(n)` ends quietly on a dropped
  connection, so before the checksum a truncated exe would have been installed.
  Checked 2026-11-07 in the GUI on scratch profiles: first-use download, then a YouTube
  URL playing; "Update now" replacing a stand-in old copy (2.4 s, no `.part` left, button
  disabled meanwhile, version shown) and a second click finding it current without a
  download. Headless: 2160p AV1 with `PATH` cut to `C:\Windows` (no Deno or Node), so no
  JS runtime is needed for this video. `test_ytdl_update` covers a dropped connection, a
  checksum mismatch and an unreachable server against loopback. Not checked: cookies,
  the outdated auto-refresh, a members-only error toast.
- Volume slider: read a slider's value from `event.data`, never `event.control.value`:
  `update_transport` writes mpv's volume to the control about 20 times a second during
  playback, so the handler used to set the old volume straight back and the slider stuck.
  `volume_dragging` keeps it off a held thumb (as `dragging` does for the seek bar). It
  now applies live, like Lunoir's `onChange`, and has 8 px side padding instead of the
  default 24, which left 56 of its 104 px usable. Deviation: moving it unmutes, because a
  muted slider sits at 0 (Lunoir's) and would snap back there. Checked 2026-11-07 with real
  mouse input: 11 drags in both directions ended on the expected value with no jumps, and
  posted clicks, mute and unmute behaved.
- Wheel over the video (Lunoir's `onWheel`): volume ±5, with Lunoir's volume OSD
  (icon, bar, number) only while the OSC is hidden; Ctrl+wheel zooms (`video-zoom`,
  log2 steps of 0.1, clamped -2..3, re-centred at 1x) with a zoom OSD; Ctrl+double-click
  resets; dragging while zoomed pans (`video-pan-x/y`, Lunoir's formula) and pauses for
  the drag. Each file starts at 1x. Ctrl comes from `GetAsyncKeyState`, because Flet's
  scroll and tap events carry no modifiers. Both OSDs are one hole, 88 px off the
  bottom, or above the pill when it shows (Lunoir's sit at 88 px either way, which
  would cover the pill here). Flet runs handlers concurrently, so `pan_start` records
  the drag before awaiting the pause; otherwise a quick release ran in between and left
  the video paused (seen in testing).
- Popups over the video are invisible (airspace), so the right-click menu is a
  side panel, speed/aspect are chips in it, and dropdowns live only inside panels.
  Dialogs still hide the video while open.
- Library (Lunoir's `Library.tsx`): Recent, Saved (`file`/`url`), Playlists
  (`playlist`) and Live (`list`) tabs over one `favourites.json`. A recents row has
  Save (`favouriteTarget`) and remove. The playlist panel's star is `saveCollection`:
  an IPTV source, or a snapshot of the queue under Lunoir's `queueKey` (`pl:` + its
  JS string hash; `profile.queue_key` hashes UTF-16 code units, so the keys match
  Lunoir's, tested). A saved playlist reopens from its snapshot and resumes its last
  item. The menu's Save is add-only and toasts `toast.alreadyFav` (it used to toggle).
  A playlist URL saved from the menu is kept as `url` (it expands again on open);
  Lunoir keeps it as `list`, whose reopen tries to fetch it as a channel list.
  Checked 2026-10-29 only on a stub app with a temporary profile (real methods and
  panel builders, no window).
- Deliberate deviation: a stream's `media-title` replaces a playlist entry's
  `#EXTINF` title only when it differs from the file name (mpv's fallback).
- Dev hooks: `LUNOIR_V_SNAPSHOTS=<dir>` makes F9 save Flutter's own rendering
  (`page.take_screenshot`), which works when other windows cover the app.
  `PrintWindow` captures often show the holes as flat grey (RGB 105,105,105); real
  screen captures of the same moments were clean, so don't judge holes by them.
  To keep a test window out of the way, give the scratch profile `rememberWindow: true`
  and `windowBounds` at `x: -3000`: posted input and F9 snapshots still work off-screen.
  `VMPV_HOST_LOG` traces every IPC request. To test without touching the real
  profile, point `APPDATA` at a scratch folder (write its `settings.json` without a
  BOM: PowerShell 5.1's `Set-Content -Encoding utf8` adds one and the profile then
  silently falls back to defaults). A running host also accepts extra clients on
  its `--input-ipc-server` pipe (read it from the process command line), which is
  a way to seek or pause the app without input. lavfi sources (`av://lavfi:...`)
  cannot seek backwards; for a real seekable file, encode one through the host
  (`--o=clip.mkv --of=matroska --ovc=mjpeg`, under 1 s for a minute; see
  `test_thumbs.py`). Drive the app with messages posted to
  the deepest enabled child (`ChildWindowFromPointEx`), not global `SendInput`:
  arrows need the extended-key bit, and clicks inside Flutter's dropdown overlay
  did not register (keyboard selection does). Two things posting cannot drive:
  a posted `WM_MOUSEWHEEL` scrolls at the *real* cursor (Flutter reads
  `GetCursorPos`), and a posted drag is cancelled at once (`TrackMouseEvent` sees the
  real cursor outside and Flutter gets `WM_MOUSELEAVE`). For those, call the handlers
  (`video_wheel`, `pan_*`) with synthetic events from inside the process.
- Verified 2026-10-25 (synthetic lavfi sources, a local M3U, a loopback HTTP channel
  list): floating pill over live video, auto-hide after 5 s, right-click menu, click
  to pause, `k`, frame-step/back-step while paused, ±5 s seek, volume, next item,
  missing-file skip, info panel, settings tabs, Chinese home/URL mode, runtime switch
  to German, docked layout, playlist progress key, IPTV channel mode (grouped list,
  search, LIVE readout, `force-media-title`, no resume or recents), and restoring a
  saved external audio track, external subtitle and resume position in Lunoir's
  order. 2026-10-28, scratch profile: a second launch with another lavfi source
  exited in about 1 s and the running player loaded it; the drop popup exists,
  owned by the Flet window and hidden; closing the window left no process behind.
  A local file starts the preview host next to the main one, and both exit with the
  window. 2026-10-29, scratch profile, mpv state read over the host pipe: wheel volume
  100 → 90 → 95 with the OSD, five Ctrl+wheel notches to zoom 0.5 (141 %), a 100x50 px
  synthetic drag to pan (0.128, 0.099) paused then resumed, Ctrl+double-click (posted)
  reset zoom and pan without going fullscreen. 52 Python tests pass (`test_backend`, `test_profile`, `test_port`, `test_ytdl`,
  `test_ytdl_update`, `test_volume`, `test_shell`, `test_thumbs`; `test_shell` calls the drop target through real
  pywin32 COM gateways, `test_thumbs` runs the preview service against an encoded
  clip in an off-screen window).
- Not verified: real files with several embedded audio/subtitle tracks, chapters,
  screenshots on disk, A-B loop, aspect crop on a real file, HiDPI, real cursor
  movement revealing the OSC (posted messages don't move the cursor), fullscreen,
  a real drag from Explorer or a browser (the popup's press-outside detection and
  OLE's `DragEnter` on it need real mouse input), focus being granted to the
  raised window through `Lunoir-V.exe`'s extra process hop, the seek preview
  under a real hovering cursor (the service and the geometry are checked apart), and
  a real mouse wheel or drag reaching the video's `GestureDetector` (only the
  handlers were driven; see the posting limits above).
- Remaining parity work (audit 2026-10-28: every UI string key and IPC handler of
  Lunoir against the port), most useful first:
  - File associations / installer for the packaged build (Lunoir's Electron build
    gets them from its installer).
  - Picture enhancement (`enhance`, `deblock`, `nr`, `sharpen`, `artcnn`, `cfl`;
    `applyEnhance`; shaders are in Lunoir's `resources/shaders/`).
  - Menu actions: stream recording (`recordingDir`), timecode overlay, hide title
    bar, mini player.
  - Update check (notify only), MediaInfo fields (HDR flavour, commercial audio
    names, the unsupported-audio badge), "watch as one" timeline/trim/clips tab,
    discs, Emby, acrylic (`frostStrength`; may not combine with holes).
  - Small: image-subtitle brightness in the Adjust strip; preferred-language lists
    come from the file's tracks instead of Lunoir's fixed list; playlist remove
    current, multi-select reorder; loading toast; settings "restore default";
    home tagline; "Media"/"All files" dialog filters.
- CI: `.github/workflows/portable.yml` builds on `windows-2025`, with V 0.5.2 and GCC
  15.2 pinned by checksum (the runner has no MinGW) and Python 3.11. It only runs
  `build-flet.ps1` and `package-flet.ps1`, as a local build does, on the user's decision:
  no tests or other checks may stand between a push and the zip. The zip is kept as an
  artifact for 14 days. Every build of `main` (push or manual run) deletes and recreates
  the `nightly` release (marked Latest, so not a pre-release: GitHub can't make a
  pre-release Latest) and its tag at that commit; a `v*` tag publishes it as a full
  release. Builds of one ref run one at a time, so two pushes can't race over `nightly`:
  a running build always finishes and a newer one waits (GitHub keeps only the newest
  waiting run and cancels older waiting ones with "a higher priority waiting request
  exists"). Run the tests locally. The
  runner's base Python has no pywin32, while the dev machine's has it globally, which is
  what failed `test_host_dies_with_a_killed_front_end` there (fixed with `python -S`).
- Packaging: `package-flet.ps1` builds, then assembles `dist/Lunoir-V/` (ignored):
  a copy of the Python the `.venv` was made from (`sys.base_prefix`, same version,
  so pywin32's compiled modules match; stdlib minus tests, IDLE, Tk, ensurepip), the
  venv's packages minus pip/setuptools, `flet_lunoir/` minus tests and launcher, the
  runtime, Lunoir's assets, i18n, `LICENSE` and `CREDITS.md`, and `Lunoir-V.exe`. A
  `python311._pth` fixes `sys.path` to that folder (`..` holds `flet_lunoir`; no
  PYTHONPATH or user site-packages); `import site` still runs pywin32's `.pth`.
  `Lunoir-V.exe` prefers `python/pythonw.exe` next to it, else `.venv`. It runs the
  player in its own folder, so it makes existing path arguments absolute first.
  Checked 2026-10-28: a copy outside the repo, with PATH cut to System32 and a
  scratch profile, played a lavfi source with every process running from the copy,
  took a relative `list.m3u` from a second launch in another folder, and closed
  cleanly. No installer, Start-menu entry or file associations yet.

## Setup (Windows)

| Tool | Version tested | Notes |
|---|---|---|
| V | 0.5.2 (Scoop) | `scoop install v` |
| GCC | 15.2.0 (Scoop) | `scoop install gcc`; TCC also works (below) |
| mpv | our build, v0.41.0-340 (client API 2.5) | `libmpv-2.dll` in this folder |

The repo ships its own mpv: `libmpv-2.dll` here. The `mpv/` module carries everything
needed to build against it (headers in `mpv/include/`, import libraries `libmpv.dll.a`
and `mpv.def`), so nothing else needs installing. At run time
`libmpv-2.dll` must be next to the exe, in the current directory, or on `PATH`;
running from this folder works as is. In Git Bash:

```bash
export V_C_ERROR_BUG_REPORT_DISABLED=1   # stop V uploading C errors to bugs.vlang.io
```

To swap in another libmpv build, replace `libmpv-2.dll` and `mpv/include/mpv/*.h`
together and regenerate the import libraries (below).

On other systems the module uses `pkg-config mpv` instead (not tested yet).

### Compilers

| Compiler | Result with V 0.5.2 |
|---|---|
| GCC 15.2 | Works through `mpv/libmpv.dll.a`. Use for release builds. |
| TCC (bundled) | Works through `mpv/mpv.def` (TCC can't link a DLL directly) |
| Clang 22 (MSVC) | Needs `-Wno-incompatible-pointer-types`; exes crash at start (`0xC0000409`) |
| Zig 0.16 (`zig cc`) | Link fails: V passes `-Wl,-stack=...`, which zig's linker rejects |

Both import libraries are generated from the DLL; regenerate them when it changes:

```bash
~/scoop/apps/v/current/thirdparty/tcc/tcc.exe -impdef libmpv-2.dll -o mpv/mpv.def
dlltool -d mpv/mpv.def -D libmpv-2.dll -l mpv/libmpv.dll.a
v -cc tcc -no-retry-compilation test mpv/
```

`-no-retry-compilation` stops V silently retrying a failed TCC build with Clang,
which hides TCC's real error behind the Clang bug above.

## Using the module in another project

Copy the `mpv/` folder into the project (or into `~/.vmodules/`), `import mpv`, and put
`libmpv-2.dll` next to the built exe. Nothing else from this repo is needed; this was
checked by building a separate project against a copied `mpv/` with GCC and TCC.

## Running the tests

From this folder:

```bash
v -cc gcc test mpv/                     # 3 test files, 150 assertions
```

The tests play synthetic `av://lavfi:testsrc` sources, so they need no media files and
open no windows.

## Folder contents

| Path | What it is |
|---|---|
| `libmpv-2.dll` | Our mpv build (v0.41.0-340), which everything here links |
| `flet_lunoir/` | Lunoir V, the player |
| `host/` | `vmpv-host`: an `mpv.exe` stand-in built on the binding, serving mpv's JSON IPC |
| `mpv/` | The binding module |
| `mpv/include/`, `mpv/libmpv.dll.a`, `mpv/mpv.def` | mpv's headers for that build, and its import libraries for GCC and TCC |
| `mpv/helper.h` | C helpers: `mpv_node` union access, C-heap node trees, render params |
| `mpv/*_test.v` | Tests: header-drift checks, node round trips, client and render API |
| `lunoir/` | What the player reads from [Lunoir](https://github.com/zhbj420/Lunoir) 0.9.4 (MIT, by Yao666): assets, translations, `LICENSE`, `CREDITS.md` |
| `.github/` | The portable build workflow and its check script |

## vmpv-host

`host/` builds **vmpv-host**, the player's playback backend. It stands in for `mpv.exe`
as Lunoir drives it, over mpv's JSON IPC named pipe with its video embedded by `--wid`:

- It accepts mpv's `--option=value`, `--flag` and `--no-flag` arguments and sets them
  with `set_option_string`.
- It serves `--input-ipc-server` itself, written in V (`host/ipc.v`) like mpv's
  `ipc.c`: one mpv client handle per connection, `observe_property`, `get_property`,
  `set_property` and the other client commands on that handle, everything else through
  `command_node`, and events forwarded with `Event.to_node()`. So every request the player
  sends and every property update it receives passes through the binding.
  `--vmpv-native-ipc` hands the pipe to libmpv's own server instead, for comparison.
- It is built with `-subsystem windows`, like mpv.exe, so no console window opens.
- Windows only for now (the pipe server uses Win32 named pipes).

`VMPV_HOST_LOG=<path>` makes the host trace every IPC request.

## API

Mostly go-mpv's API in V naming. The differences:

- **Errors** are V results: every failing call returns an `MpvError`, whose `kind()`
  is an `ErrorCode` (`if err is mpv.MpvError && err.kind() == .property_not_found`).
- **Node values** are the sum type `mpv.Node`
  (`NodeNone | string | bool | i64 | f64 | []u8 | []Node | map[string]Node`), replacing
  go-mpv's `interface{}`. Integers must be `i64`: `m.set_property('volume', i64(50))`.
- **`set_property` / `set_option` take a `Node`** and pick the mpv format from its variant,
  so there is no separate format argument. Arrays and maps go through `MPV_FORMAT_NODE`.
- **Typed getters**: `get_property_string`, `_osd_string`, `_flag`, `_int`, `_double`,
  `_node`. `get_property(name, format)` returns a `Node`. The string getters return
  errors, where go-mpv returns `""`.
- **Callbacks** are plain V functions plus a `voidptr` (`set_wakeup_callback`,
  `RenderContext.set_update_callback`, the GL `GetProcAddressFn`). go-mpv needs a
  token registry because Go can't hand Go pointers to C; V can.
- **Events**: `Event.property()`, `.log_message()`, `.start_file()`, `.end_file()`,
  `.client_message()`, `.hook()` and `.command_reply()` copy the payload into V values.
  Call them before the next `wait_event`, which frees the payload. `Event.check()`
  returns the error of an async reply.
- **Additions**: `create_client`, `create_weak_client`, `set_wakeup_callback`, `Event.to_node()`, and the
  deprecated `idle`/`tick` event ids (mpv still sends `idle`; go-mpv drops it, so it
  would show up as an unknown id).
- **Not ported**: `SetLocale` (only matters after a GUI toolkit changes `LC_NUMERIC`),
  and the stream callback API (`stream_cb.h`), which go-mpv doesn't bind either.
  Of the render API, only the SW and GL create/render paths are bound:
  `mpv_render_context_get_info`, `_set_parameter` and the parameters behind them
  (advanced control, next-frame info, block-for-target-time, skip rendering, ICC
  profile, ambient light, depth) are not. The client API is complete (all 45
  `client.h` functions, checked 2026-10-29). The Flet port needs none of the gaps: it
  embeds with `--wid`, and the remaining parity features are plain properties
  (`vf`, `glsl-shaders`, `scale`, `stream-record`, `script-opts`) that `command_node`
  already carries; our DLL includes Lua and `ytdl_hook`.

Enum values are hard-coded in V. `enums_test.v` compares each one with the C header
constant, so a libmpv upgrade that changes a value fails the tests instead of drifting.

### Not covered by tests

- **OpenGL rendering** (`new_render_context_gl`, `render_gl`, `report_swap`) compiles
  but is untested; it needs a GL context, i.e. a GUI library. go-mpv's GL example
  uses IUP, which has no V binding.
- Linux and macOS (`#pkgconfig mpv` path).

## Findings

### From the binding work (2026-10-10)

- **`MPV_EVENT_IDLE` is still sent** by default although deprecated, so the binding keeps
  it in `EventId`.
- **`mpv_get_wakeup_pipe` works on Windows**: it returned a C runtime fd, although
  `client.h` says Windows always gets -1.
- **`abort_async_command` is ignored if it arrives before the command starts.** The test
  repeats the abort until the reply comes; real code that aborts right away may need
  to do the same.
- **The `start` option rejects `MPV_FORMAT_DOUBLE`** (mpv reports "option not found");
  set it as a string. `speed`, `volume` and other plain doubles accept a double.
- V string slices are copies with a NUL terminator, so passing `s.str` to C is safe.
  Node strings are copied by length anyway.
- V reads `$env(...)` in `#flag` lines, and resolves undeclared `C.MPV_*` constants
  in tests, which the drift checks rely on.

### From running Lunoir on the binding (2026-10-10)

- **mpv sanitizes client names**: `create_client('ipc-1')` becomes `ipc_1`.
- **`-subsystem windows` discards the parent's stderr pipe.** V's generated `main`
  reopens stderr to `NUL` when there is no console, closing the inherited handle, so
  `eprintln` output never reaches the parent. The host duplicates the handle in a C
  constructor before `main` runs and writes to that copy (`host/pipe_win.h`).
- **Overlapped pipes are required**: with a synchronous handle, the reader thread's
  blocked `ReadFile` would also block the event thread's `WriteFile`.

### Groundwork (2026-10-05)

- All 54 libmpv functions go-mpv calls are exported by `libmpv-2.dll`, and all 82
  constants it hard-codes match the 2.5 headers.
- `MPV_RENDER_PARAM_DRM_DISPLAY` is unsupported on Windows (Linux-only) and
  `MPV_RENDER_PARAM_AMBIENT_LIGHT` is accepted but harmless; the binding uses neither.
- V cannot model the anonymous union inside `mpv_node`, and renames a C field called
  `string` to `__v_string` in generated C. `mpv/helper.h` handles this with small
  `static inline` accessors, as go-mpv does with `client_helper.c`.
- go2v was planned for a first draft but skipped: go-mpv is almost all cgo, which go2v
  can't translate, and the rest maps onto V sum types rather than line by line.

## License details

GPL-3.0-or-later (see `LICENSE`), including the mpv build we ship. What is kept of Lunoir
in `lunoir/` has its own MIT `LICENSE`, and `mpv/include/` keeps mpv's ISC header notice; both are
GPL-compatible.

## Developer's thoughts: why V over Rust for this binding

Rust has the more mature toolchain, which this folder's own compiler table makes plain.
For a libmpv binding specifically, V may still be the better long-term choice, because
most of Rust's advantages don't reach this kind of code.

### Rust's safety guarantees stop at the FFI boundary

A libmpv binding is almost entirely calls into C. In Rust, every one of them is `unsafe`,
and the hard rules are ones the borrow checker can't see on its own:

- event payloads are only valid until the next `mpv_wait_event` on that handle;
- render contexts must be freed before the handle is destroyed;
- node trees returned by libmpv must be freed by libmpv, while nodes the binding
  builds must be freed by the binding (see go-mpv's README).

Rust *can* encode these with lifetimes, `PhantomData` and guard types, but that is a lot
of careful type machinery for a thin wrapper, and mistakes in it are still memory bugs.
In V the same rules are a handful of documented invariants in a small API. The safety
gap between the two is smaller here than in a typical application.

### V compiles against the real headers, so there is nothing to drift

V `#include`s `mpv/client.h` and `mpv/render.h` directly, and the C compiler resolves
every struct layout and constant at build time. Rust needs either `bindgen` (which
needs libclang at build time) or hand-maintained `-sys` declarations, which is the
same layout-drift risk go-mpv's purego backend documents as its main danger.
Struct layouts and function signatures can't drift at all: upgrade libmpv, recompile,
done. Only the enum values are mirrored in V (V enums need literal values), and
`mpv/enums_test.v` compares them with the header constants on every test run, and the
expected values come straight from the headers.

### Less build plumbing to maintain

A Rust binding is usually two crates (`mpv-sys` plus a safe wrapper), a `build.rs`, and
per-platform linking logic (pkg-config, vcpkg, environment variables). The V
equivalent is a few `#flag` lines. Less plumbing means fewer things to break on the
next libmpv, OS or compiler update.

### Performance is a wash; iteration speed isn't

Decoding and rendering happen inside libmpv, so Rust's zero-cost abstractions buy
nothing measurable at this layer. Development speed does differ: V with TCC rebuilds
these tests in about a second, versus much longer Rust builds.

### Easier to contribute to

V reads much like Go, so go-mpv's maintainers and users could review and contribute
to a V port with little ramp-up. A Rust binding narrows contributors to people
comfortable with `unsafe` FFI and lifetime-heavy APIs.

### The main risk, V's immaturity, is limited for a thin binding

V is pre-1.0 and its toolchain has rough edges (see the compiler table above). But a
thin binding holds little logic, so if V changes or stalls, the cost of updating or
porting it stays small. V can also emit plain C (`v -o out.c`), which gives an
escape route.

### When Rust is still the right call

- The application using mpv is already written in Rust (existing Rust mpv crates
  cover that case).
- The surrounding code is large, long-lived or heavily concurrent, where the borrow
  checker pays for itself well beyond the FFI layer.
- The project must ship on many platforms now, with a stable language and ecosystem
  behind it.

For a lean, header-driven mpv binding meant for V programs, V is a reasonable bet.
For mpv inside a big production application, Rust's maturity still counts for more.
