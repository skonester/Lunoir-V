# Lunoir V

A desktop media player for Windows: the interface of
[Lunoir](https://github.com/zhbj420/Lunoir) rebuilt in Flet/Python, with every playback
command going through **v-mpv**, this repo's [mpv](https://mpv.io/) bindings for the
[V language](https://vlang.io/). No Electron or Node is involved.

## Run it

You need Windows, Python 3.10+, [V](https://vlang.io/) and GCC (`scoop install v gcc`).

```powershell
git clone https://github.com/skonester/Lunoir-V.git
cd Lunoir-V
./build-flet.ps1
```

Then double-click **`Lunoir-V.exe`**. The first build sets up a Python environment and
downloads Flet's desktop runtime.

`./package-flet.ps1 -Zip` makes a self-contained copy in `dist/` (about 250 MB) that runs
on a PC with none of the above installed. GitHub Actions builds the same thing for
64-bit Windows, and tagged versions are on the
[Releases](https://github.com/skonester/Lunoir-V/releases) page: unzip and run
`Lunoir-V.exe`. Settings stay in `%APPDATA%/Lunoir V`, outside the folder.

## What it does

- Lunoir's home screen and controls, which float over the video and hide when idle, or
  sit docked below it
- Lunoir's nine interface languages, its settings and keyboard shortcuts
- per-file resume, and remembered audio and subtitle choices
- folders, M3U playlists and IPTV channel lists
- online video through [yt-dlp](https://github.com/yt-dlp/yt-dlp), which it downloads on
  first use and keeps current; **Settings > General > Update now** gets the latest
  release on demand
- seek-bar previews, opening files and links by drag and drop, one window per profile
- the right-click menu (speed, aspect, A-B loop, screenshots), a file info panel, and a
  library of recent and saved items

Not ported yet: picture enhancement, discs, recording, timeline editing, Lunoir's
translucent panels, and an installer with file associations.

It is an experiment, tested on Windows only.

## The V bindings

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

The bindings are a port of the Go library
[go-mpv](https://github.com/gen2brain/go-mpv) and ship with their own mpv build
(`libmpv-2.dll`). They let V programs open files or streams, control playback (pause,
seek, volume, tracks, subtitles), read player state, and react to player events.

## What's in here

- **`flet_lunoir/`**: Lunoir V, the player.
- **`mpv/`**: the bindings, a V module. Copy it into a project, `import mpv`, and put
  `libmpv-2.dll` next to the program.
- **`host/`**: `vmpv-host`, a stand-in for `mpv.exe` built on the bindings. The player
  runs it as its playback backend.
- **`lunoir/`**: the files Lunoir V reads from [Lunoir](https://github.com/zhbj420/Lunoir)
  0.9.4: its assets and translations, unmodified, with its license and credits.

Building, testing and project notes are in [AGENTS.md](AGENTS.md).

## License

GPL-3.0-or-later. Lunoir, by Yao666, keeps its MIT license and credits in `lunoir/`.
