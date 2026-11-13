module py_flet_lunoir

import os

// TODO(py2v): no V equivalent for import flet, flet.utils, urllib.request, zipfile
// Provide one in python_to_v_import (types.v) or port the module.

// TODO(py2v): no V mapping for zipfile.ZipFile
// Each site below is stubbed with a zero value.

pub fn main_func() {
	runtime := ROOT / 'flet_lunoir/runtime/flet'
	if (runtime / 'flet/flet.exe').is_file() {
		return
	}
	archive := runtime.parent / 'flet-windows.zip'
	url := 'https://github.com/flet-dev/flet/releases/download/v${flet.version____}/flet-windows.zip'
	println("Downloading Flet ${flet.version____}'s Windows desktop client...")
	if !archive.is_file() {
		urllib.request.urlretrieve(url, archive)
	}
	runtime.mkdir()
	if true {
		package := Any(0)
		safe_zip_extractall(package, runtime)
	}
	if !(runtime / 'flet/flet.exe').is_file() {
		panic('RuntimeError: ' + 'The Flet desktop archive did not contain flet.exe.')
	}
	archive.unlink()
}

pub fn provision_main() {
	main_func()
}
