# Lunoir's V application

App version **0.3.0** comes from root `VERSION`, embedded by `version.v` and shown
in General/About and startup logs. The `v_mpv` binding manifests remain at `0.1.0`.

The application logic runs in V and uses `import mpv` directly. Flet 1.0.5's Flutter
desktop client draws Lunoir's interface. The old Python implementation, virtual
environment, Python test runner, py2v tooling and generated migration output have
been removed. No Python or TypeScript toolchain is required to build the app.

## Build and package

With Windows x64, V 0.5.2 and GCC on PATH:

```powershell
./build-native.ps1
./Lunoir-V.exe
./package-native.ps1 -SkipBuild -Zip
```

The first build downloads the official, checksum-pinned Flet desktop client into
the ignored `runtime/flet/` directory. Later builds accept `-SkipDependencies`.
`build-flet.ps1` and `package-flet.ps1` remain aliases for the native scripts.

The portable package includes the V exe, libmpv, Flet/Flutter, assets, JSON locale
data, VERSION and licenses. Runtime paths are relative to the executable.

## Source map

| Files | Responsibility |
|---|---|
| `main.v`, `app.v`, `media.v`, `input.v` | Startup, state loop, layout, playback and input |
| `panels.v`, `library.v` | Settings, tracks, queues, chapters, menus and library |
| `flet.v`, `msgpack.v` | Flet desktop transport, control tree and event bindings |
| `backend.v`, `playback_requests.v` | Ordered async libmpv requests, completion handling and events through `mpv/` |
| `diagnostics.v`, `picture.v` | Live Info statistics, picture controls and named playback/picture presets |
| `audio_outputs.v` | Worker-based output discovery, device selection and restoration |
| `native_video.v`, `thumbs.v` | Native video child and seek previews |
| `platform_windows.c.v`, `platform_win.h` | Windows dialogs, process jobs, HTTP and video integration |
| `instance.v`, `drop_windows.c.v`, `drop_win.h` | Single instance and OLE file/link drops |
| `profile.v`, `playlist.v`, `options.v`, `formatting.v` | Persistence, lists, settings mapping and display formatting |
| `i18n.v`, `lunoir/i18n/*.json` | Nine languages, 356 strings each, English fallback |
| `ytdl.v` | yt-dlp installation, integrity checks, updates, playlists and stream recovery |

Embedded `shell.json`, `ui_templates.json` and `icons.json` contain control data,
translation-key markers and declarative event bindings resolved by V. The locale
JSON files preserve the keys and values from Lunoir's original translations; their
TypeScript wrappers and parser have been removed. Never localize schema fields
such as `_c`, `_i` or `_internals`. Preserve Lunoir's MIT license and credits.

The app includes floating/docked OSC, auto-hide, keyboard/mouse actions, zoom/pan,
file/URL dialogs, tracks and subtitle adjustments, queues/IPTV, chapters, library,
five settings tabs, runtime language switching, resume/track memory, screenshots,
previews, single instance, OS drops and yt-dlp. Profile JSON formats remain compatible.
Original Lunoir features still missing are listed in the main README's roadmap.

Press **I** during playback to open Info. Its live section updates once per second
with the decoder actually in use, frame drops, A/V sync, buffered time, buffer fill,
FPS and bitrates. Missing values appear as a dash; zero drops appear as zero.

**Settings > Picture** contains color adjustments, debanding, motion interpolation
and upscaling filters. Scroll to **Named presets** to save, apply or delete a preset.
Presets also capture hardware decoding, deinterlacing, pitch correction and stream
quality. Saving an existing name replaces it. Applying a preset replaces all managed
options, including defaults for missing keys, and saves only after mpv accepts them.
On failure, the app requests the previous values and leaves the saved settings intact.
Presets are stored in `%APPDATA%/Lunoir V/presets.json`.

**Settings > Playback > Audio output** selects a device or System default. Device
discovery runs on a worker using a separate mpv client. Refresh after connecting
or removing hardware. The app remembers an accepted selection and restores it
before opening media; an unavailable saved device falls back to System default.
The picker selects mpv's output option; playback routing on physical devices still
needs hands-on validation.

Transport controls and property-driven panels update once per event batch. Pending
Flet patches keep only the final value per property. Runtime settings save one second
after the last actual change, skip identical/reverted values and flush on close.
Failed saves remain pending and retry after one second.

Interpolation also enables display sync, as required by [mpv's interpolation option](https://mpv.io/manual/stable/#options-interpolation).
It is disabled by default. These controls use `gpu-next` options; custom upscaling
shaders and the remaining sharpening/denoising/deblocking tools are still on the roadmap.

## Verification and restrictions

The user prohibited further local test-video runs. Do not run the complete app
test suite or `tools/test-native.ps1` while that restriction applies: those tests
create/play local media. Focused checks that do not start playback are available:

```powershell
$env:V_C_ERROR_BUG_REPORT_DISABLED = '1'
v -subsystem console -cc gcc -no-retry-compilation v_lunoir/port_test.v
v -subsystem console -cc gcc -no-retry-compilation v_lunoir/ytdl_retry_test.v
v -subsystem console -cc gcc -no-retry-compilation v_lunoir/playback_async_test.v
v -subsystem console -cc gcc -no-retry-compilation v_lunoir/picture_diagnostics_test.v
v -subsystem console -cc gcc -no-retry-compilation v_lunoir/audio_updates_test.v
```

These cover formatting, profile persistence, JSON translations, control schema,
MessagePack and the bounded YouTube recovery policy. The one-time locale migration
compared every converted key/value with the previous loader before removing the
TypeScript files.

The async checks use an idle mpv instance with null outputs and synthetic state;
they never load media or create a window. They cover request dependencies,
coalesced writes, immediate/reply errors, completion-dependent profile/UI updates,
stale replies and the one-retry preview watchdog. Runtime mpv calls queue work
without waiting for the core; screenshot success and saved track selections follow
successful replies. Previews reset after a 4-second timeout, retry once after
250 ms and disable themselves for the file if recovery also fails.

The picture/diagnostics checks verify missing versus zero statistics, updates to
existing text controls, all nine locales, preset persistence/replacement, rejection
handling and supported option values on an idle null-output mpv instance. They do
not render or play media. Idle Flet captures have also been inspected for the new
Picture tab, preset dialog and live Info layout using a scratch profile.

The audio/update checks cover discovery on an idle null-output mpv core without
stealing playback replies, worker cleanup, output failures/fallback, deferred opens,
all locales, save debounce/retry/shutdown, flat control trees and coalesced updates
with slider drag guards. Idle Flet captures verify the picker alongside the existing
Playback settings; a scratch-profile shutdown verifies the final settings flush.

The supplied online video `https://www.youtube.com/watch?v=A7kKxad9tWM` was verified:
a direct audio request returned HTTP 403, then the automatic HLS retry played
1920x1080 video with AAC audio. Failure processing collects log messages that arrive
after `end-file`. Recovery is limited to one retry per load, respects the chosen
height cap, and restores normal format selection on the next item.

Earlier validation covered libmpv playback, external track restoration, previews,
screenshots, COM drop objects, singleton forwarding, download integrity and process
cleanup. The development-only Python runner used for those checks was removed.
Real Explorer/browser dragging, physical hover/wheel/pan, fullscreen and HiDPI still
need hands-on checking; the desktop input helper was unavailable during migration.

Warnings/errors are recorded in `%LOCALAPPDATA%/Lunoir V/native.log`.
`LUNOIR_V_MPV_LOG=<path>` enables detailed diagnostics. Use scratch APPDATA and
LOCALAPPDATA for diagnostic launches. The app's F9/optional timed Flutter captures
omit native video; see AGENTS.md for the diagnostic environment variables.
