module py_flet_lunoir

import crypto
import json
import log
import os
import time

// TODO(py2v): no V equivalent for import ctypes, pywintypes, threading, win32api, win32con, win32event, win32file, win32gui, win32pipe, winerror
// Provide one in python_to_v_import (types.v) or port the module.

// TODO(py2v): no V mapping for ctypes.windll.user32.AllowSetForegroundWindow, threading.Thread, win32api.GetLastError, win32event.CreateMutex, win32file.CloseHandle, win32file.CreateFile, win32file.FlushFileBuffers, win32file.ReadFile, win32file.WriteFile, win32gui.IsIconic, win32gui.IsWindow, win32gui.SetForegroundWindow, win32gui.ShowWindow, win32pipe.ConnectNamedPipe, win32pipe.CreateNamedPipe, win32pipe.DisconnectNamedPipe, win32pipe.SetNamedPipeHandleState
// Each site below is stubbed with a zero value.

// TODO(py2v): 5 except handler(s) need a V Result equivalent:
//   except pywintypes.error (1 stmt)
//   except pywintypes.error (2 stmt)
//   except pywintypes.error as error (1 stmt)
//   except pywintypes.error as error (3 stmt)
//   except pywintypes.error | ValueError (1 stmt)

const log = log :=
const asfw_any_ = 4.294967295e+09

pub struct Instance {
pub mut:
	mutex_name Any
	pipe_name Any
	mutex Any
	thread ?threading.Thread
}

pub fn (mut self Instance) init(profile Path) {
	key := hashlib.sha1(os.path.normcase(os.path.abspath(profile)).bytes()).hexdigest()[..16]
	self.mutex_name = 'Local\\LunoirV-${key}'
	self.pipe_name = '\\\\.\\pipe\\lunoir-v-instance-${key}'
	self.mutex = none
	self.thread = none
}

pub fn (mut self Instance) claim() bool {
	self.mutex = Any(0)
	return Any(0) != winerror.ERROR_ALREADY_EXISTS
}

pub fn (self Instance) forward(found []string, timeout f64) bool {
	_ = Any(0)
	deadline := time.monotonic() + timeout
	for time.monotonic() < deadline {
		handle := Any(0)
		// except handlers are not translated: see the TODO(py2v) note above
		//   except pywintypes.error as error: 3 statement(s) need an `or { ... }` equivalent
		defer {
			_ = Any(0)
		}
		_ = Any(0)
		_ = Any(0)
		py2v_unpack1 := Any(0)
		_ := py2v_unpack1[0]
		mut reply := py2v_unpack1[1]
		raise_window(int(reply || [byte(0x30)]))
		return true
	}
	return false
}

pub fn run() {
	for {
		pipe := Any(0)
		// except handlers are not translated: see the TODO(py2v) note above
		//   except pywintypes.error: 2 statement(s) need an `or { ... }` equivalent
		defer {
			_ = Any(0)
			// except handlers are not translated: see the TODO(py2v) note above
			//   except pywintypes.error: 1 statement(s) need an `or { ... }` equivalent
			_ = Any(0)
		}
		_ = Any(0)
		// except handlers are not translated: see the TODO(py2v) note above
		//   except pywintypes.error as error: 1 statement(s) need an `or { ... }` equivalent
		py2v_unpack2 := Any(0)
		_ := py2v_unpack2[0]
		mut data := py2v_unpack2[1]
		found := json.loads(data.decode('utf-8'))
		hwnd := handler(if found is list { found.map(it) } else { [] })
		_ = Any(0)
		_ = Any(0)
		// except handlers are not translated: see the TODO(py2v) note above
		//   except pywintypes.error | ValueError: 1 statement(s) need an `or { ... }` equivalent
	}
}
pub fn (mut self Instance) serve(handler fn ([]string) int)  {
	self.thread = Any(0)
	self.thread.start()
}

pub fn targets(argv []string, cwd ?string) []string {
	mut found := []
	for raw in argv {
		if !raw || raw.starts_with('-') {
			continue
		}
		if is_url(raw) {
			found << raw
			continue
		}
		path := os.path.abspath((cwd || os.getcwd()).join(os.path))
		if os.path.exists(path) {
			found << path
		}
	}
	return found
}

pub fn raise_window(hwnd int)  {
	if !hwnd || !Any(0) {
		return
	}
	if Any(0) {
		_ = Any(0)
	}
	_ = Any(0)
	// except handlers are not translated: see the TODO(py2v) note above
	//   except pywintypes.error: 1 statement(s) need an `or { ... }` equivalent
}
