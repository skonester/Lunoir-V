module main

import math

struct Rect {
	x f64
	y f64
	w f64
	h f64
	r f64
}

struct NativeVideo {
mut:
	parent  voidptr
	hwnd    voidptr
	scale   f64 = 1
	radius  f64
	logical Rect
	bounds  []int
	holes   []Rect
	visible bool
}

fn new_video(parent voidptr, radius f64) !NativeVideo {
	if isnil(parent) { return error('Flet desktop window is not ready') }
	hwnd := C.lv_video_create(parent)
	if isnil(hwnd) { return error('Could not create the video surface') }
	return NativeVideo{
		parent: parent
		hwnd:   hwnd
		radius: radius
	}
}

fn client_rect(parent voidptr) []int {
	mut bounds := []int{len: 4}
	C.lv_client(parent, bounds.data)
	return bounds
}

fn (mut s NativeVideo) layout(rect Rect, page_width f64) bool {
	client := client_rect(s.parent)
	s.scale = f64(client[2] - client[0]) / math.max(1.0, page_width)
	s.logical = rect
	bounds := [int(math.round_to_even(rect.x * s.scale)), int(math.round_to_even(rect.y * s.scale)),
		int(math.round_to_even(rect.w * s.scale)), int(math.round_to_even(rect.h * s.scale))]
	if bounds == s.bounds { return false }
	C.lv_position(s.hwnd, bounds[0], bounds[1], if bounds[2] < 1 { 1 } else { bounds[2] }, if bounds[3] < 1 {
		1
	} else {
		bounds[3]
	})
	s.bounds = bounds
	s.apply_region()
	return true
}

fn (mut s NativeVideo) set_holes(holes []Rect) bool {
	if holes == s.holes { return false }
	s.holes = holes.clone()
	s.apply_region()
	return true
}

fn (s &NativeVideo) apply_region() {
	if s.bounds.len != 4 { return }
	mut holes := []int{}
	for h in s.holes {
		holes << [int(math.round_to_even((h.x - s.logical.x) * s.scale)),
			int(math.round_to_even((h.y - s.logical.y) * s.scale)),
			int(math.round_to_even(h.w * s.scale)), int(math.round_to_even(h.h * s.scale)),
			int(math.round_to_even(h.r * s.scale))]
	}
	C.lv_region(s.hwnd, s.bounds[2], s.bounds[3], int(math.round_to_even(s.radius * s.scale)),
		holes.data, s.holes.len)
}

fn (mut s NativeVideo) show(visible bool) {
	if visible != s.visible {
		C.lv_show(s.hwnd, int(visible))
		s.visible = visible
	}
}

fn (s &NativeVideo) cursor() ?[]f64 {
	mut point := []int{len: 2}
	if C.lv_cursor(s.parent, s.hwnd, point.data) == 0 { return none }
	return [f64(point[0]) / s.scale, f64(point[1]) / s.scale]
}

fn (s &NativeVideo) focused() bool {
	return C.lv_focused(s.parent) != 0
}

fn (s &NativeVideo) raise() {
	C.lv_raise(s.hwnd)
}

fn (s &NativeVideo) close() {
	C.lv_destroy(s.hwnd)
}
