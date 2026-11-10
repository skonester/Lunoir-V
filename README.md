<div align="center">

<img src="lunoir/src/renderer/src/assets/logo.png" alt="Lunoir V logo" width="128">

# Lunoir V

**A lightweight, mpv-powered media player for Windows: Lunoir's interface, without Electron.**

[![Portable build](https://github.com/skonester/Lunoir-V/actions/workflows/portable.yml/badge.svg)](https://github.com/skonester/Lunoir-V/actions/workflows/portable.yml)
[![Download nightly](https://img.shields.io/badge/download-nightly-7c4dff?logo=github)](https://github.com/skonester/Lunoir-V/releases/tag/nightly)
![Platform: Windows x64](https://img.shields.io/badge/platform-Windows%20x64-0078D4?logo=windows)
![Engine: mpv 0.41](https://img.shields.io/badge/engine-mpv%200.41-691F69)
![Built with V and Python](https://img.shields.io/badge/built%20with-V%20%2B%20Python-5D87BF)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](LICENSE)

[Download](#-download) · [Features](#-features) · [Shortcuts](#-keyboard-and-mouse) · [Build from source](#-build-from-source) · [The V bindings](#-v-mpv-the-bindings)

</div>

---

Lunoir V brings the polished interface of [Lunoir](https://github.com/zhbj420/Lunoir) to a
native-feeling desktop app built with [Flet](https://flet.dev/) and Python. Every frame
it plays is decoded and rendered by [mpv](https://mpv.io/), driven through
**v-mpv**, this repo's own libmpv bindings for the [V language](https://vlang.io/). No
Electron, no Node.js, no bundled browser: just mpv's playback engine behind a modern,
minimal UI.

> [!NOTE]
> Lunoir V is in active development and tested on Windows only. Some of Lunoir's
> features are still being ported (see the [roadmap](#-roadmap)).

## 📥 Download

Grab the portable build from [**Releases**](https://github.com/skonester/Lunoir-V/releases):

- **`nightly`**, the Latest release, is rebuilt automatically from every commit to `main`.
- **`v*` releases** are tagged versions.

Unzip anywhere and run **`Lunoir-V.exe`**. No installer, no admin rights, and nothing
else to install: Python, the Flet runtime and mpv are all inside the folder. Each zip
ships with a `.sha256` file so you can verify the download. Settings live in
`%APPDATA%\Lunoir V`, so updating means replacing the folder.

## ✨ Features

### 🎬 Playback engine

- **mpv inside**: the codec and container support of FFmpeg-based mpv, from H.264,
  HEVC and AV1 to MKV, MP4 and WebM
- **GPU rendering** through mpv's libplacebo-based `gpu-next` renderer on Direct3D 11
- **Hardware-accelerated decoding** (`hwdec=auto` out of the box, configurable)
- **Frame-accurate stepping** forwards and backwards, and up to **150 % volume boost**
- **Audio passthrough** (S/PDIF) for your choice of codecs, and pitch correction at
  any playback speed
- **A-B loop**, playback speed and aspect ratio presets, deinterlacing
- **Screenshots** in your choice of format, saved straight to disk

### 💎 Interface

- **Floating, auto-hiding on-screen controller** over full-size video, or a classic
  docked control bar
- **Seek-bar thumbnail previews** while hovering over the timeline
- **Mouse-wheel volume and Ctrl+wheel zoom** with on-screen indicators; drag to pan a
  zoomed picture
- **Drag and drop** for files, folders and links
- **Nine interface languages**, switchable live
- **Single-instance**: opening another file hands it to the window that's already open

### 💬 Subtitles and audio tracks

- Switch audio and subtitle tracks on the fly, and load external ones
- Automatic loading of matching subtitle files
- Full subtitle styling: font, size, spacing, bold, outline, position and code page
- Brightness control for subtitles over **HDR** video, for text and bitmap (PGS/VobSub)
  subtitles alike
- Preferred audio and subtitle languages

### 📺 Streaming and IPTV

- **Stream online video** from the sites [yt-dlp](https://github.com/yt-dlp/yt-dlp)
  supports, with a selectable quality cap and optional browser cookies
- **Self-updating yt-dlp**: downloaded on first use, checksum-verified, kept current in
  the background, or updated on demand
- **Online playlists** expand into the play queue
- **IPTV and live TV**: load M3U channel lists, with grouped channels, search and a
  live indicator

### 📚 Library and memory

- **Resume playback** where you left off, per file
- **Remembers your audio and subtitle choices** for each file
- **Recents, favourites and saved playlists** in a built-in library
- Folder playback and local **M3U playlists** with per-playlist progress
- **File info panel** with codec, resolution, bitrate and other stream details

## ⚡ Keyboard and mouse

| Input | Action |
|---|---|
| <kbd>Space</kbd> / <kbd>K</kbd> / click | Play / pause |
| <kbd>←</kbd> <kbd>→</kbd> | Seek 5 s (frame step while paused) |
| <kbd>↑</kbd> <kbd>↓</kbd> / mouse wheel | Volume ±5 |
| <kbd>M</kbd> | Mute |
| <kbd>.</kbd> / <kbd>,</kbd> | Next / previous item |
| <kbd>F</kbd> / <kbd>F11</kbd> / double-click | Fullscreen |
| <kbd>Esc</kbd> | Leave fullscreen |
| <kbd>I</kbd> | File info |
| <kbd>Ctrl</kbd>+<kbd>O</kbd> | Open files |
| <kbd>Ctrl</kbd>+wheel | Zoom (<kbd>Ctrl</kbd>+double-click resets) |
| Right-click | Quick menu: speed, aspect, A-B loop, screenshot and more |

## 🔧 Build from source

**Requirements:** Windows, Python 3.10+, [V](https://vlang.io/) and GCC.

```powershell
scoop install v gcc
git clone https://github.com/skonester/Lunoir-V.git
cd Lunoir-V
./build-flet.ps1
```

Then double-click **`Lunoir-V.exe`**. The first build creates a Python virtual
environment and downloads Flet's desktop runtime; later builds can skip that with
`./build-flet.ps1 -SkipDependencies`.

To make your own portable package (about 250 MB, in `dist/`):

```powershell
./package-flet.ps1 -Zip
```

Developer notes, tests and design decisions are in [AGENTS.md](AGENTS.md).

## 🧱 Architecture

```
┌──────────────────────────────┐   JSON IPC over a    ┌───────────────────────────┐
│  Lunoir V (Flet / Python)    │   named pipe         │  vmpv-host (V)            │
│  UI, library, playlists,     │ ───────────────────▶ │  mpv's IPC protocol,      │
│  settings, yt-dlp, IPTV      │ ◀─────────────────── │  served through v-mpv     │
└──────────────┬───────────────┘   events, properties └─────────────┬─────────────┘
               │ native child window (--wid)                        │ libmpv client API
               └───────────────────── video ◀───────────────────────┤
                                                                    ▼
                                                            libmpv-2.dll (mpv 0.41)
```

| Folder | What it is |
|---|---|
| [`flet_lunoir/`](flet_lunoir/) | Lunoir V, the player |
| [`host/`](host/) | `vmpv-host`, a drop-in stand-in for `mpv.exe` built on the bindings, serving mpv's JSON IPC |
| [`mpv/`](mpv/) | **v-mpv**, the V module, with mpv's headers and import libraries |
| [`lunoir/`](lunoir/) | Lunoir 0.9.4's assets and translations, unmodified, with its license and credits |

## 🧩 v-mpv: the bindings

v-mpv is a complete binding of libmpv's client API for V, ported from
[go-mpv](https://github.com/gen2brain/go-mpv). Open files and streams, control playback,
read and observe properties, and react to player events, with V results for errors and a
sum type for mpv's node values.

```v
import mpv

fn main() {
	m := mpv.new()!
	defer {
		m.terminate_destroy()
	}
	m.initialize()!
	m.command(['loadfile', 'video.mkv'])!
	for {
		e := m.wait_event(-1)
		match e.id {
			.file_loaded { println('length: ${m.get_property_double('duration')!} s') }
			.end_file, .shutdown { break }
			else {}
		}
	}
}
```

- **All 45 functions** of mpv's `client.h`, plus the software and OpenGL render API
- **Self-contained**: copy `mpv/` into your project, `import mpv`, and put
  `libmpv-2.dll` (included) next to your program
- **Builds with GCC and TCC**, compiling against mpv's real headers so struct layouts
  can't drift; tests check every enum value against the C constants

## 🧭 Roadmap

Lunoir features not ported yet:

- [ ] Installer with file associations
- [ ] Picture enhancement (sharpening, denoising, deblocking, upscaling shaders)
- [ ] Stream recording, timecode overlay, mini player
- [ ] Update notifications
- [ ] Timeline trimming and clips
- [ ] Disc playback and Emby
- [ ] Translucent (acrylic) panels

## 🙏 Credits

- [**Lunoir**](https://github.com/zhbj420/Lunoir) by Yao666, whose design, assets and
  translations this player is built on (MIT, see [`lunoir/`](lunoir/))
- [**mpv**](https://mpv.io/), the playback engine
- [**go-mpv**](https://github.com/gen2brain/go-mpv), which the V bindings are ported from
- [**Flet**](https://flet.dev/) and [**yt-dlp**](https://github.com/yt-dlp/yt-dlp)

## 📄 License

Lunoir V is licensed under **GPL-3.0-or-later** (see [LICENSE](LICENSE)), including the
mpv build it ships. The files from Lunoir keep their
[MIT license and credits](lunoir/CREDITS.md).
