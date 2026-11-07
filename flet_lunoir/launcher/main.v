// Double-clickable entry point for the Flet port. Playback lives in host/.
module main

import os

#include <windows.h>
#flag -luser32

fn C.MessageBoxW(voidptr, &u16, &u16, u32) int

fn main() {
	root := os.dir(os.executable())
	// a packaged build carries its own Python (package-flet.ps1); a checkout uses .venv
	mut python := os.join_path(root, 'python', 'pythonw.exe')
	if !os.exists(python) {
		python = os.join_path(root, '.venv', 'Scripts', 'pythonw.exe')
	}
	if !os.exists(python) {
		C.MessageBoxW(unsafe { nil }, 'Run build-flet.ps1 once to set up Lunoir.'.to_wide(),
			'Lunoir'.to_wide(), 0x10)
		return
	}
	mut process := os.new_process(python)
	process.set_work_folder(root)
	mut args := ['-m', 'flet_lunoir']
	for arg in os.args[1..] {
		// the player runs in root, so a path relative to the caller's folder must be resolved here
		args << if !arg.starts_with('-') && os.exists(arg) { os.abs_path(arg) } else { arg }
	}
	process.set_args(args)
	process.run()
	// Wait to keep the V process's child handle valid for the session.
	process.wait()
	process.close()
}
