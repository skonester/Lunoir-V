# Lunoir's V application

App version **0.2.0** comes from root `VERSION`, embedded by `version.v` and shown
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
| `backend.v` | Direct libmpv commands, properties and events through `mpv/` |
| `native_video.v`, `thumbs.v` | Native video child and seek previews |
| `platform_windows.c.v`, `platform_win.h` | Windows dialogs, process jobs, HTTP and video integration |
| `instance.v`, `drop_windows.c.v`, `drop_win.h` | Single instance and OLE file/link drops |
| `profile.v`, `playlist.v`, `options.v`, `formatting.v` | Persistence, lists, settings mapping and display formatting |
| `i18n.v`, `lunoir/i18n/*.json` | Nine languages, 305 strings each, English fallback |
| `ytdl.v` | yt-dlp installation, integrity checks, updates, playlists and stream recovery |

Embedded `shell.json`, `ui_templates.json` and `icons.json` contain control data,
translation-key markers and declarative event bindings resolved by V. The locale
JSON files preserve the keys and values from Lunoir's original translations; their
TypeScript wrappers and parser have been removed. Never localize schema fields
such as `_c`, `_i` or `_internals`. Preserve Lunoir's MIT license and credits.

The app includes floating/docked OSC, auto-hide, keyboard/mouse actions, zoom/pan,
file/URL dialogs, tracks and subtitle adjustments, queues/IPTV, chapters, library,
four settings tabs, runtime language switching, resume/track memory, screenshots,
previews, single instance, OS drops and yt-dlp. Profile JSON formats remain compatible.
Original Lunoir features still missing are listed in the main README's roadmap.

## Verification and restrictions

The user prohibited further local test-video runs. Do not run the complete app
test suite or `tools/test-native.ps1` while that restriction applies: those tests
create/play local media. Focused checks that do not start playback are available:

```powershell
$env:V_C_ERROR_BUG_REPORT_DISABLED = '1'
v -subsystem console -cc gcc -no-retry-compilation v_lunoir/port_test.v
v -subsystem console -cc gcc -no-retry-compilation v_lunoir/ytdl_retry_test.v
```

These cover formatting, profile persistence, JSON translations, control schema,
MessagePack and the bounded YouTube recovery policy. The one-time locale migration
compared every converted key/value with the previous loader before removing the
TypeScript files.

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
