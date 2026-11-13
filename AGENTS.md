# AGENTS.md - Lunoir V and v-mpv working notes

## Current application (2026-11-13)

Repository: https://github.com/skonester/Lunoir-V. The app is Windows-only and uses
V 0.5.2/GCC 15.2, the shipped libmpv DLL, and Flet 1.0.5's Flutter desktop client.
The app version is 0.2.0, sourced from root `VERSION`, embedded by
`v_lunoir/version.v`, displayed in General/About and startup logs, and included in
the portable package. Root `v.mod` and `mpv/v.mod` version the binding separately
at 0.1.0. App release tags use `v0.2.0` for this version.

The user requested removing unnecessary Python/TypeScript code after the manual V
migration. The old Python application, virtual environment, Python test runner,
py2v tools/generated output/reports and TypeScript sources have been removed.
Nine translation dictionaries (305 strings each) were converted without changing
their keys or values to `lunoir/i18n/*.json`. No Python or Node/TypeScript toolchain
is required to build or run the app. Do not reintroduce those dependencies.

The user rejected a separate Win32 player. Preserve Lunoir's existing Flet interface,
assets, MIT license and credits. The behavior/design reference is Lunoir 0.9.4 at
https://github.com/zhbj420/Lunoir. The V application imports `mpv` directly; it does
not start Python or `vmpv-host`. `host/` remains an independent V IPC example/tool.

## Build and package

```powershell
./build-native.ps1                     # V/GCC; downloads pinned Flet if missing
./build-native.ps1 -SkipDependencies
./Lunoir-V.exe
./package-native.ps1 [-Zip] [-SkipBuild] # dist/Lunoir-V, no Python or TypeScript
```

`build-flet.ps1` and `package-flet.ps1` remain compatibility wrappers for the native
scripts. The ignored `runtime/flet/` holds the official Flet client, downloaded with
SHA256 verification. The application locates `runtime/flet/flet/flet.exe` relative to
its executable. Packages contain that runtime, libmpv, the V exe, assets, JSON
translations, VERSION and licenses. The asset path remains
`lunoir/src/renderer/src/assets/` for compatibility with existing UI layout data.

CI uses the native scripts on windows-2025 with pinned V/GCC and no Python setup.
Preserve the user's rule: CI builds/packages/releases; no test/check gates between
a push and the zip. Builds of main replace the rolling nightly release and v* tags
publish versioned releases. The shipped DLL is about 94 MiB, under GitHub's 100 MB
file limit; retain it and its matching headers/import libraries.

## Testing restriction

The user explicitly prohibited further local test-video runs (2026-11-13) and
requested focusing on yt-dlp. Do not run `tools/test-native.ps1` or the complete
V app test suite while this restriction applies: they create/play local media.
Use targeted non-media checks and the supplied online URL instead.

Permitted focused checks with no media playback:

```powershell
$env:V_C_ERROR_BUG_REPORT_DISABLED = '1'
v -subsystem console -cc gcc -no-retry-compilation v_lunoir/port_test.v
v -subsystem console -cc gcc -no-retry-compilation v_lunoir/ytdl_retry_test.v
```

The first checks formatting, profiles, JSON translations, control schema and wire
encoding. The second checks the bounded YouTube retry policy without starting mpv.
Explicit `-subsystem console` keeps test diagnostics visible. Other V tests remain
available but must not be run contrary to the user's media restriction.

Earlier validation covered real libmpv playback, resume, external audio/subtitles,
previews, screenshots, COM drop objects, singleton forwarding, download integrity,
and process cleanup. The Python integration runner used then has been removed.
Real Explorer/browser dragging, physical hover/wheel/pan, fullscreen and HiDPI
still need hands-on checking. The desktop input helper was unavailable during the
migration. COM/in-process checks do not establish physical input paths.

## Implementation notes

- `main.v`, `app.v`, `media.v`, `input.v`, `panels.v`, `library.v` own startup, UI
  state, playback, settings, queues and library behavior. Mutable state and mpv
  events stay on the main loop; socket/download workers communicate through channels.
- `flet.v`/`msgpack.v` implement the pinned Flet 1.0.5 desktop socket protocol.
  Embedded `shell.json`, `ui_templates.json`, `icons.json` hold control data and
  event bindings. Localized text resolves from JSON dictionaries through `i18n.v`.
  Never translate schema fields such as `_c`, `_i` or `_internals`.
- `backend.v` calls the existing `mpv/` binding directly. Both playback and preview
  handles live inside the V process. `thumbs.v` preserves local-file-only previews,
  warm-up playback, throttled seeking and the original 320px preview geometry.
- `platform_win.h`, `drop_win.h` and V wrappers provide native video, process jobs,
  file dialogs, OLE drops, HTTP and single-instance handling. Flet joins a
  kill-on-close job so killing the V controller closes its client. Profile formats
  and mutex/pipe names remain compatible with earlier versions.
- Floating controls and panels use holes in a disabled video child HWND; Flet
  receives mouse input through it. A full-window backdrop shade flip forces repaints
  after region/layout changes to mitigate grey compositor holes. Do not replace
  this with changing `page.bgcolor`, which rebuilds the app.
- Volume/seek handlers use event data and dragging flags so property polling does
  not overwrite an actively dragged thumb. Gesture event position/scroll fields
  include compact wire aliases `g` and `sd`. Cursor polling drives auto-hide/previews.
  If OSC geometry changes, update `seek_rect()` alongside the layout.
- `profile.v` stores settings, resume positions, histories, favorites, playlist
  progress and track selections under `%APPDATA%/Lunoir V`. Logs are under
  `%LOCALAPPDATA%/Lunoir V`. Use scratch APPDATA/LOCALAPPDATA for app diagnostics.
- YouTube extraction can succeed while mpv's direct audio request returns HTTP 403.
  `ytdl.v` retries once with HLS audio/video, retaining the selected quality cap and
  restoring normal selection on the next queue item. mpv logs can arrive after
  end-file, so failure handling waits briefly to collect the real HTTP cause.
  Verified with https://www.youtube.com/watch?v=A7kKxad9tWM at 1920x1080 with AAC.
  Warnings/errors go to `native.log`; `LUNOIR_V_MPV_LOG=<path>` enables detailed logs.
  yt-dlp is downloaded on demand and verified against its published SHA256 checksum.
- Use `json_decode`/`json_encode` in `json.v`. The pinned generic JSON2 decoder
  expects tagged sum types absent from ordinary profile/mpv JSON. `object` and
  `list_value` must reject scalars; coercing `.as_map()`/`.as_array()` are unsuitable.
- Avoid implicitly converting unary `!x` to `json2.Any`: this compiler generates
  invalid C. Assign the bool to a local first. Keep
  `V_C_ERROR_BUG_REPORT_DISABLED=1` when invoking V.
- Diagnostic hooks: `LUNOIR_V_TEST_SCRIPT` supplies timed actions;
  `LUNOIR_V_EXIT_AFTER` bounds a run. F9 captures Flutter rendering when
  `LUNOIR_V_SNAPSHOTS` is set; timed captures additionally need
  `LUNOIR_V_SNAPSHOT_INTERVAL` (ms). Flutter captures omit native video.

See the main README for original Lunoir features still outside the implemented app.

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
| `v_lunoir/` | Lunoir V, the native V player |
| `host/` | `vmpv-host`: an `mpv.exe` stand-in built on the binding, serving mpv's JSON IPC |
| `mpv/` | The binding module |
| `mpv/include/`, `mpv/libmpv.dll.a`, `mpv/mpv.def` | mpv's headers for that build, and its import libraries for GCC and TCC |
| `mpv/helper.h` | C helpers: `mpv_node` union access, C-heap node trees, render params |
| `mpv/*_test.v` | Tests: header-drift checks, node round trips, client and render API |
| `lunoir/` | What the player reads from [Lunoir](https://github.com/zhbj420/Lunoir) 0.9.4 (MIT, by Yao666): assets, translations, `LICENSE`, `CREDITS.md` |
| `.github/` | The portable build workflow and its check script |

## vmpv-host

`host/` builds **vmpv-host**, an optional IPC host for binding consumers. It stands in for `mpv.exe`
over mpv's JSON IPC named pipe, with video embedded by `--wid`. The current app imports mpv directly:

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
