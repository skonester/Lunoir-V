module py_flet_lunoir

import log
import math
import time
import arrays

// TODO(py2v): no V equivalent for import asyncio, win32gui
// Provide one in python_to_v_import (types.v) or port the module.

// TODO(py2v): no V mapping for asyncio.current_task, asyncio.sleep, win32gui.GetClientRect
// Each site below is stubbed with a zero value.

// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
// TODO(py2v): module-level statement has no place in a V module; move it into a function and call it explicitly.
const min_seek = 0.07
const radius = 8
const log = log :=
const thumb_args = [
	'--ao=null',
	'--volume=0',
	'--pause',
	'--keepaspect=yes',
	'--video-margin-ratio-bottom=${TIME_H / (THUMB_H + TIME_H)}',
	'--background=color',
	'--background-color=#FF3A3A3A',
	'--sid=no',
	'--aid=no',
	'--sub-auto=no',
	'--osd-bar=no',
	'--osd-level=1',
	'--osd-scale-by-window=no',
	'--osd-font=Segoe UI Semibold',
	'--osd-font-size=18.5',
	'--osd-spacing=0.6',
	'--osd-bold=no',
	'--osd-color=#FFCDCDD3',
	'--osd-outline-size=0',
	'--osd-shadow-offset=0',
	'--osd-back-color=#00000000',
	'--osd-align-x=center',
	'--osd-align-y=bottom',
	'--osd-margin-y=4',
	'--cursor-autohide=always',
]

pub struct Thumbnails {
pub mut:
	parent Any
	mpv ?MpvController
	surface ?NativeVideo
	events_task ?asyncio.Task
	starting ?asyncio.Task
	loaded Any
	loading Any
	video_h Any
	queued ?f64
	last_seek Any
	follow ?asyncio.Task
	place_args ?[]int
	enabled Any
	visible Any
	warming Any
}

pub fn (mut self Thumbnails) init(parent int) {
	self.parent = parent
	self.mpv = none
	self.surface = none
	self.events_task = none
	self.starting = none
	self.loaded = ''
	self.enabled = false
	self.visible = false
	self.file_ready = false
	self.warming = false
	self.has_frame = false
	self.loading = false
	self.video_h = THUMB_H
	self.queued = none
	self.last_seek = 0
	self.follow = none
	self.place_args = none
}

pub fn send() {
	if true {
		contextlib.suppress(MpvError, OSError, asyncio.TimeoutError)
		self.mpv.command(...args)
	}
}
pub fn (self Thumbnails) fire_(args ...Any)  {
	if !self.mpv {
		return
	}
	go send()
}

pub fn follow() {
	_ = Any(0)
	self._flush()
}
pub fn (mut self Thumbnails) preview(t f64, x f64, osc_top f64, page_width f64, docked bool)  {
	if !self.enabled || !self.mpv || !self.surface {
		return
	}
	if !self.visible {
		self.visible = true
		self.surface.show(true)
		self.surface.raise_()
	}
	self._place(x, osc_top, page_width, docked)
	self.queued = t
	wait := min_seek - (time.monotonic() - self.last_seek)
	if wait <= 0 {
		self._flush()
	} else if !self.follow || self.follow.done() {
		// pass
		self.follow = go follow()
	}
}

pub fn (mut self Thumbnails) flush_()  {
	if self.follow && !self.follow.done() && self.follow != Any(0) {
		self.follow.cancel()
	}
	if self.queued == none || !self.file_ready {
		return
	}
	t := self.queued
	self.last_seek = time.monotonic()
	if !self.has_frame {
		self.warming = true
		self._fire('seek', t, 'absolute+exact')
		self._fire('set_property', 'pause', false)
		return
	}
	self.queued = none
	self._fire('set_property', 'pause', true)
	self._fire('seek', t, 'absolute+exact')
	self._fire('show-text', clock(t), 100000)
}

pub fn (mut self Thumbnails) hide()  {
	if self.follow && !self.follow.done() {
		self.follow.cancel()
	}
	self.queued = none
	if self.visible && self.surface {
		self.surface.show(false)
	}
	self.visible = false
}

pub fn (mut self Thumbnails) place_(x f64, osc_top f64, page_width f64, docked bool)  {
	self.place_args = [x, osc_top, page_width, docked]
	py2v_unpack1 := Any(0)
	mut left := py2v_unpack1[0]
	_ := py2v_unpack1[1]
	mut right := py2v_unpack1[2]
	_ := py2v_unpack1[3]
	scale := (right - left) / (arrays.max([1, page_width]) or { panic('!') })
	width, height := THUMB_W / scale, (self.video_h + TIME_H) / scale
	left = arrays.max([0, arrays.min([x - width / 2, page_width - width]) or { panic('!') }]) or { panic('!') }
	top := arrays.max([0, osc_top - height - (if docked { DOCK_GAP } else { FLOAT_GAP })]) or { panic('!') }
	self.surface.layout(left, top, width, height, page_width)
}

pub fn clock(seconds f64) string {
	seconds = if math.isfinite(seconds) { arrays.max([0, int(seconds)]) or { panic('!') } } else { 0 }
	h, m, s := math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
	return if h { '${h}:${m}:${s}' } else { '${m}:${s}' }
}
