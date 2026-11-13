module py_flet_lunoir

import log
import math
import regex
import encoding.binary
import arrays

// TODO(py2v): no V equivalent for import ctypes, pythoncom, pywintypes, threading, win32api, win32clipboard, win32com.server.util, win32con, win32gui
// Provide one in python_to_v_import (types.v) or port the module.

// TODO(py2v): no V mapping for ctypes.GetLastError, ctypes.POINTER, ctypes.byref, ctypes.c_void_p, ctypes.memmove, pythoncom.CoUninitialize, pythoncom.OleInitialize, pythoncom.RegisterDragDrop, pythoncom.RevokeDragDrop, threading.Event, threading.Thread, win32api.GetAsyncKeyState, win32api.GetModuleHandle, win32clipboard.RegisterClipboardFormat, win32gui.ClientToScreen, win32gui.CreateWindowEx, win32gui.DefWindowProc, win32gui.DestroyWindow, win32gui.GetAncestor, win32gui.GetClientRect, win32gui.GetCursorPos, win32gui.IsIconic, win32gui.IsWindow, win32gui.IsWindowVisible, win32gui.LoadCursor, win32gui.PostMessage, win32gui.PostQuitMessage, win32gui.PumpMessages, win32gui.RegisterClass, win32gui.ShowWindow, win32gui.WNDCLASS, win32gui.WindowFromPoint
// Each site below is stubbed with a zero value.

// TODO(py2v): 6 except handler(s) need a V Result equivalent:
//   except AttributeError | OSError (1 stmt)
//   except Exception (1 stmt)
//   except Exception (3 stmt)
//   except pythoncom.com_error (1 stmt)
//   except pywintypes.error (1 stmt)
//   except pywintypes.error as error (1 stmt)

const log = log :=
const user_ = ctypes.windll.user32
const gdi_ = ctypes.windll.gdi32
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
const tick_ms = 30
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
const clear_ = bytes([0, 0, 0, 1])
const tint_ = bytes([23, 10, 9, 23])
const border_ = bytes([191, 106, 92, 191])
const url_format_ = Any(0)
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.

pub struct Target {
pub mut:
	com_interfaces__ list = [pythoncom.IID_IDropTarget]
	public_methods__ list = ['DragEnter', 'DragOver', 'DragLeave', 'Drop']
	owner Any
	effect Any
}

pub fn (mut self Target) init(owner DropTarget) {
	self.owner = owner
	self.effect = DROPEFFECT_NONE_
}

pub fn (self Target) pick_(allowed int) int {
	return if allowed & DROPEFFECT_COPY_ { DROPEFFECT_COPY_ } else { allowed & DROPEFFECT_LINK_ }
}

pub fn (mut self Target) DragEnter(data Any, key_state Any, point Any, allowed Any) Any {
	self.effect = if dropped_items(data) { self._pick(allowed) } else { DROPEFFECT_NONE_ }
	self.owner.set_hint((self.effect != 0))
	return self.effect
}

pub fn (self Target) DragOver(key_state Any, point Any, allowed Any) Any {
	return self.effect
}

pub fn (self Target) DragLeave() {
	self.owner.set_hint(false)
}

pub fn (self Target) Drop(data Any, key_state Any, point Any, allowed Any) Any {
	self.owner.set_hint(false)
	items := dropped_items(data)
	if items {
		self.owner.on_drop(items)
		// except handlers are not translated: see the TODO(py2v) note above
		//   except Exception: 1 statement(s) need an `or { ... }` equivalent
	}
	return if items { self._pick(allowed) } else { DROPEFFECT_NONE_ }
}

pub struct DropTarget {
pub mut:
	hwnd Any
	painted ?[]int
	ready Any
	thread Any
	was_down Any
	press_outside Any
	shown Any
	hint Any
}

pub fn (mut self DropTarget) init(parent int, on_drop fn ([]string)) {
	self.parent, self.on_drop = parent, on_drop
	self.hwnd = 0
	self.hint = false
	self.shown = false
	self.was_down = false
	self.press_outside = false
	self.painted = none
	self.ready = Any(0)
	self.thread = Any(0)
	self.thread.start()
	self.ready.wait(5)
}

pub fn (mut self DropTarget) run_()  {
	_ = Any(0)
	defer {
		self.ready.set()
	}
	instance := Any(0)
	mut wc := Any(0)
	wc.lpszClassName = 'LunoirVDrop'
	wc.hInstance = instance
	wc.lpfnWndProc = proc_
	wc.hCursor = Any(0)
	_ = Any(0)
	// except handlers are not translated: see the TODO(py2v) note above
	//   except pywintypes.error as error: 1 statement(s) need an `or { ... }` equivalent
	self.hwnd = Any(0)
	targets_[self.hwnd] = self
	_ = Any(0)
	user_.SetTimer(self.hwnd, 1, tick_ms, none)
	// except handlers are not translated: see the TODO(py2v) note above
	//   except Exception: 3 statement(s) need an `or { ... }` equivalent
	defer {
		_ = Any(0)
	}
	_ = Any(0)
}

pub fn (self DropTarget) message_(hwnd Any, message Any, wparam Any, lparam Any) Any {
	if message == win32con.WM_TIMER {
		self._tick()
		return 0
	}
	if message == win32con.WM_MOUSEACTIVATE {
		return win32con.MA_NOACTIVATE
	}
	if message == win32con.WM_CLOSE {
		user_.KillTimer(hwnd, 1)
		_ = Any(0)
		// except handlers are not translated: see the TODO(py2v) note above
		//   except pythoncom.com_error: 1 statement(s) need an `or { ... }` equivalent
		_ = Any(0)
		return 0
	}
	if message == win32con.WM_DESTROY {
		(targets_[hwnd] or { 0 })
		_ = Any(0)
		return 0
	}
	return Any(0)
}

pub fn (self DropTarget) over_player_(point Any) bool {
	under := Any(0)
	root := if under { Any(0) } else { 0 }
	// except handlers are not translated: see the TODO(py2v) note above
	//   except pywintypes.error: 1 statement(s) need an `or { ... }` equivalent
	return (root in [self.parent, self.hwnd])
}

pub fn (mut self DropTarget) tick_()  {
	if !Any(0) {
		_ = Any(0)
		return
	}
	down := [win32con.VK_LBUTTON, win32con.VK_RBUTTON].map(Any(0) & 32768).any(it)
	point := Any(0)
	// except handlers are not translated: see the TODO(py2v) note above
	//   except pywintypes.error: 1 statement(s) need an `or { ... }` equivalent
	over := self._over_player(point)
	if down && !self.was_down {
		self.press_outside = !over
	}
	self.was_down = down
	usable := Any(0) && !Any(0)
	self._show(usable && (self.hint || (down && self.press_outside && over)))
}

pub fn (mut self DropTarget) show_(visible bool)  {
	if visible {
		self._paint()
		if !self.shown {
			_ = Any(0)
		}
	} else if self.shown {
		_ = Any(0)
	}
	self.shown = visible
}

pub fn (mut self DropTarget) set_hint(hint bool)  {
	self.hint = hint
	if self.shown {
		self._paint()
	}
}

pub fn (mut self DropTarget) paint_()  {
	py2v_unpack2 := Any(0)
	mut left := py2v_unpack2[0]
	mut top := py2v_unpack2[1]
	mut right := py2v_unpack2[2]
	mut bottom := py2v_unpack2[3]
	py2v_unpack3 := Any(0)
	mut x := py2v_unpack3[0]
	mut y := py2v_unpack3[1]
	width, height := right - left, bottom - top
	if width <= 0 || height <= 0 {
		return
	}
	state := [x, y, width, height, self.hint]
	if state == self.painted {
		return
	}
	mut scale := user_.GetDpiForWindow(self.parent) / 96 || 1
	// except handlers are not translated: see the TODO(py2v) note above
	//   except AttributeError | OSError: 1 statement(s) need an `or { ... }` equivalent
	pixels := hint_pixels(width, height, scale, self.hint)
	header := @struct.pack('<IiiHHIIiiII', 40, width, -height, 1, 32, 0, 0, 0, 0, 0, 0)
	screen := user_.GetDC(none)
	memory := gdi_.CreateCompatibleDC(screen)
	bits := Any(0)
	bitmap := gdi_.CreateDIBSection(memory, header, 0, Any(0), none, 0)
	defer {
		if bitmap {
			gdi_.DeleteObject(bitmap)
		}
		gdi_.DeleteDC(memory)
		user_.ReleaseDC(none, screen)
	}
	if !bitmap {
		return
	}
	_ = Any(0)
	previous := gdi_.SelectObject(memory, bitmap)
	position, size, origin := wintypes.POINT(x, y), wintypes.SIZE(width, height), wintypes.POINT(0, 0)
	blend := @struct.pack('<BBBB', 0, 0, 255, 1)
	if user_.UpdateLayeredWindow(self.hwnd, screen, Any(0), Any(0), memory, Any(0), 0, blend, 2) {
		self.painted = state
	} else {
		log.warning('drop overlay paint failed: %s', Any(0))
	}
	gdi_.SelectObject(memory, previous)
}

pub fn (self DropTarget) close()  {
	if self.hwnd && Any(0) {
		_ = Any(0)
	}
}

pub fn proc_(hwnd Any, message Any, wparam Any, lparam Any) Any {
	target := targets_.get(hwnd)
	if target {
		return target._message(hwnd, message, wparam, lparam)
	}
	return Any(0)
}

pub fn hdrop_paths(raw ?[]u8) []string {
	if !raw || raw.len < 20 {
		return []
	}
	py2v_unpack1 := @struct.unpack_from('<IiiII', raw)
	mut offset := py2v_unpack1[0]
	mut x_ := py2v_unpack1[1]
	mut y_ := py2v_unpack1[2]
	mut nc_ := py2v_unpack1[3]
	mut wide := py2v_unpack1[4]
	body := raw[offset..]
	text := if wide { body.decode('utf-16-le', 'replace') } else { body.decode('mbcs', 'replace') }
	return text.split('\x00\x00')[0].split('\x00').filter(it).map(it)
}

pub fn first_url(text string) string {
	return next(text.split_into_lines().filter((regex.regex_opt('^https?://') or { panic(err) }).match_string(it.trim_space())).map(it.trim_space()), '')
}

pub fn read(fmt Any) Any {
	return data.GetData([fmt, none, pythoncom.DVASPECT_CONTENT, -1, pythoncom.TYMED_HGLOBAL]).data
	// except handlers are not translated: see the TODO(py2v) note above
	//   except pythoncom.com_error: 1 statement(s) need an `or { ... }` equivalent
}
pub fn dropped_items(data Any) []string {
	paths := hdrop_paths(read(win32con.CF_HDROP))
	if paths {
		return paths
	}
	for fmt in [win32con.CF_UNICODETEXT, url_format_] {
		raw := read(fmt)
		url := if raw { first_url(raw.decode('utf-16-le', 'replace').split('\x00')[0]) } else { '' }
		if url {
			return [url]
		}
	}
	return []
}

pub fn put(x Any, y Any, colour Any) {
	at := (y * width + x) * 4
	pixels[at..at + 4] = colour
}
pub fn hint_pixels(width int, height int, scale f64, hint bool) bytearray {
	mut pixels := bytearray(clear_ * (width * height))
	if !hint {
		return pixels
	}
	inset, line, radius := math.round(14 * scale), arrays.max([1, math.round(2 * scale)]) or { panic('!') }, math.round(18 * scale)
	left, top, right, bottom := inset, inset, width - inset, height - inset
	if right - left < 2 * radius || bottom - top < 2 * radius {
		return pixels
	}
	dash := 3 * line
	for y in []int{len: bottom - top, init: index + top} {
		row := y * width
		dy := if y < top + radius { top + radius - y } else { if y >= bottom - radius { y - (bottom - radius - 1) } else { 0 } }
		if dy > 0 {
			for side in [0, 1] {
				cx := if side == 0 { left + radius } else { right - radius - 1 }
				for x in if side == 0 { []int{len: left + radius - left, init: index + left} } else { []int{len: right - (right - radius), init: index + (right - radius)} } {
					distance := math.hypot(x - cx, dy)
					if distance <= radius {
						put(x, y, if distance > radius - line { border_ } else { tint_ })
					}
				}
			}
			span_left, span_right := left + radius, right - radius
			on_edge := y < top + line || y >= bottom - line
			pixels[(row + span_left) * 4..(row + span_right) * 4] = tint_ * (span_right - span_left)
			if on_edge {
				for x in []int{len: span_right - span_left, init: index + span_left} {
					if math.divide_floored(x - span_left, dash).quot % 2 == 0 {
						put(x, y, border_)
					}
				}
			}
		} else {
			pixels[(row + left) * 4..(row + right) * 4] = tint_ * (right - left)
			if math.divide_floored(y - top - radius, dash).quot % 2 == 0 {
				pixels[(row + left) * 4..(row + left + line) * 4] = border_ * line
				pixels[(row + right - line) * 4..(row + right) * 4] = border_ * line
			}
		}
	}
	return pixels
}
