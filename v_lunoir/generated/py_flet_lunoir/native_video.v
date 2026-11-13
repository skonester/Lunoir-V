module py_flet_lunoir

import arrays
import math

// TODO(py2v): no V equivalent for import ctypes, win32con, win32gui
// Provide one in python_to_v_import (types.v) or port the module.

// TODO(py2v): no V mapping for win32gui.CreateWindowEx, win32gui.DestroyWindow, win32gui.FindWindow, win32gui.GetClientRect, win32gui.GetCursorPos, win32gui.GetForegroundWindow, win32gui.IsChild, win32gui.IsWindow, win32gui.PumpWaitingMessages, win32gui.ScreenToClient, win32gui.SetWindowPos, win32gui.ShowWindow, win32gui.WindowFromPoint
// Each site below is stubbed with a zero value.

// TODO(py2v): 1 except handler(s) need a V Result equivalent:
//   except win32gui.error (1 stmt)

const gdi_ = ctypes.windll.gdi32
const user_ = ctypes.windll.user32
const rgn_diff_ = 4
const handle_ = ctypes.c_void_p
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.

pub struct NativeVideo {
pub mut:
	parent  Any
	radius  Any
	hwnd    Any
	bounds  Any
	logical Any
	scale   Any
	holes   []int
	visible Any
}

pub fn (mut self NativeVideo) init(title string, parent int, radius f64) {
	self.parent = parent || Any(0)
	if !self.parent {
		panic('RuntimeError: ' + "Flet's desktop window is not ready yet.")
	}
	self.radius = radius
	self.hwnd = Any(0)
	self.bounds = none
	self.logical = [0, 0, 1, 1]
	self.scale = 1
	self.holes = []
	self.visible = false
}

pub fn (mut self NativeVideo) layout(x f64, y f64, width f64, height f64, page_width f64) bool {
	client := Any(0)
	self.scale = (client[2] - client[0]) / (arrays.max([1, page_width]) or { panic('!') })
	self.logical = [x, y, width, height]
	bounds := [x, y, width, height].map(math.round(it * self.scale))
	if bounds != self.bounds {
		_ = Any(0)
		self.bounds = bounds
		self._apply_region()
		return true
	}
	return false
}

pub fn (mut self NativeVideo) set_holes(holes [][5]f64) bool {
	holes = holes
	if holes == self.holes {
		return false
	}
	self.holes = holes
	self._apply_region()
	return true
}

pub fn (self NativeVideo) apply_region_() {
	if !self.bounds {
		return
	}
	s, [ox, oy] := self.scale, self.logical[..2]
	if !self.holes && !self.radius {
		user_.SetWindowRgn(self.hwnd, none, true)
		return
	}
	if self.radius {
		corner := math.round(2 * self.radius * s)
		mut region := gdi_.CreateRoundRectRgn(0, 0, self.bounds[2] + 1, self.bounds[3] + 1, corner,
			corner)
	} else {
		region = gdi_.CreateRectRgn(0, 0, self.bounds[2], self.bounds[3])
	}
	py2v_seq1 := self.holes
	for py2v_item2 in py2v_seq1 {
		x := py2v_item2[0]
		y := py2v_item2[1]
		width := py2v_item2[2]
		height := py2v_item2[3]
		radius := py2v_item2[4]
		left, top := math.round((x - ox) * s), math.round((y - oy) * s)
		hole := gdi_.CreateRoundRectRgn(left, top, left + math.round(width * s) + 1, top +
			math.round(height * s) + 1, math.round(2 * radius * s), math.round(2 * radius * s))
		gdi_.CombineRgn(region, region, hole, rgn_diff_)
		gdi_.DeleteObject(hole)
	}
	if !user_.SetWindowRgn(self.hwnd, region, true) {
		gdi_.DeleteObject(region)
	}
}

pub fn (self NativeVideo) raise_() {
	_ = Any(0)
}

pub fn (mut self NativeVideo) show(visible bool) {
	if visible != self.visible {
		_ = Any(0)
		self.visible = visible
	}
}

pub fn (self NativeVideo) cursor() ?[2]f64 {
	point := Any(0)
	under := Any(0)
	// except handlers are not translated: see the TODO(py2v) note above
	//   except win32gui.error: 1 statement(s) need an `or { ... }` equivalent
	if under != self.parent && under != self.hwnd && !Any(0) {
		return none
	}
	py2v_unpack3 := Any(0)
	mut x := py2v_unpack3[0]
	mut y := py2v_unpack3[1]
	return [x / self.scale, y / self.scale]
}

pub fn (self NativeVideo) focused() bool {
	return Any(0) == self.parent
}

pub fn (self NativeVideo) pump() {
	_ = Any(0)
}

pub fn (self NativeVideo) close() {
	if Any(0) {
		_ = Any(0)
	}
}
