module main

import math
import time
import x.json2

const thumb_options = ['ao=null', 'volume=0', 'pause=yes', 'keepaspect=yes',
	'video-margin-ratio-bottom=0.108910891', 'background=color', 'background-color=#FF3A3A3A',
	'sid=no', 'aid=no', 'sub-auto=no', 'osd-bar=no', 'osd-level=1', 'osd-scale-by-window=no',
	'osd-font=Segoe UI Semibold', 'osd-font-size=18.5', 'osd-spacing=0.6', 'osd-bold=no',
	'osd-color=#FFCDCDD3', 'osd-outline-size=0', 'osd-shadow-offset=0', 'osd-back-color=#00000000',
	'osd-align-x=center', 'osd-align-y=bottom', 'osd-margin-y=4', 'cursor-autohide=always']

struct Thumbnails {
mut:
	parent     voidptr
	backend    MpvController
	surface    NativeVideo
	loaded     string
	enabled    bool
	visible    bool
	file_ready bool
	loading    bool
	warming    bool
	has_frame  bool
	video_h    f64 = 180
	queued     f64 = -1
	requested  f64 = -1
	last_seek  i64
	place_args []f64
}

fn (mut p Thumbnails) sync_file(path string) ! {
	if path == '' {
		p.enabled = false
		p.loaded = ''
		p.file_ready = false
		p.hide()
		if !isnil(p.backend.handle) { p.backend.command([json2.Any('stop')]) or {} }
		return
	}
	p.enabled = true
	if isnil(p.backend.handle) {
		p.surface = new_video(p.parent, 8)!
		p.backend.start(p.surface.hwnd, thumb_options, false) or {
			p.surface.close()
			return err
		}
	}
	if path == p.loaded { return }
	p.hide()
	p.loaded = path
	p.file_ready = false
	p.loading = false
	p.warming = false
	p.has_frame = false
	p.backend.command([json2.Any('loadfile'), path, 'replace'])!
}

fn (mut p Thumbnails) tick() {
	if isnil(p.backend.handle) { return }
	for event in p.backend.events() {
		match text_value(get(event, 'event')) {
			'file-loaded' {
				p.loading = true
				p.has_frame = false
				p.fit_aspect()
			}
			'video-reconfig' {
				p.fit_aspect()
			}
			'playback-restart' {
				if p.loading {
					p.loading = false
					p.file_ready = true
				} else if p.warming {
					p.warming = false
					p.has_frame = true
					p.backend.set_property('pause', true) or {}
				}
			}
			else {}
		}
	}
	if p.visible && p.file_ready && p.queued >= 0 && time.now().unix_milli() - p.last_seek >= 70 {
		p.flush()
	}
}

fn (mut p Thumbnails) fit_aspect() {
	mut aspect := number(p.backend.get_property('video-params/aspect'))
	if aspect <= 0.2 || aspect >= 6 { aspect = 16.0 / 9 }
	height := clamp(math.round_to_even(320 / aspect), 90, 240)
	if height == p.video_h { return }
	p.video_h = height
	p.backend.set_property('video-margin-ratio-bottom', 22 / (height + 22)) or {}
	if p.visible && p.place_args.len == 4 {
		p.place(p.place_args[0], p.place_args[1], p.place_args[2], p.place_args[3] > 0)
	}
}

fn (mut p Thumbnails) preview(position f64, x f64, top f64, width f64, docked bool) {
	if !p.enabled || isnil(p.backend.handle) { return }
	if !p.visible {
		p.visible = true
		p.surface.show(true)
		p.surface.raise()
		p.requested = -1
	}
	p.place(x, top, width, docked)
	if position != p.requested {
		p.queued = position
		p.requested = position
	}
}

fn (mut p Thumbnails) flush() {
	if p.warming { return }
	position := p.queued
	p.last_seek = time.now().unix_milli()
	if !p.has_frame {
		p.warming = true
		p.backend.command([json2.Any('seek'), position, 'absolute+exact']) or {}
		p.backend.set_property('pause', false) or {}
		return
	}
	p.queued = -1
	p.backend.set_property('pause', true) or {}
	p.backend.command([json2.Any('seek'), position, 'absolute+exact']) or {}
	p.backend.command([json2.Any('show-text'), duration_text(position), 100000]) or {}
}

fn (mut p Thumbnails) place(x f64, top f64, width f64, docked bool) {
	p.place_args = [x, top, width, f64(int(docked))]
	client := client_rect(p.parent)
	scale := f64(client[2] - client[0]) / math.max(1.0, width)
	if scale <= 0 { return }
	w, h := 320 / scale, (p.video_h + 22) / scale
	left := clamp(x - w / 2, 0, math.max(0.0, width - w))
	p.surface.layout(Rect{left, math.max(0.0, top - h - if docked { 12 } else { 8 }), w, h, 0},
		width)
	p.surface.raise()
}

fn (mut p Thumbnails) hide() {
	p.queued = -1
	p.requested = -1
	if p.visible { p.surface.show(false) }
	p.visible = false
}

fn (mut p Thumbnails) close() {
	p.hide()
	p.backend.close()
	if !isnil(p.surface.hwnd) { p.surface.close() }
	p.enabled = false
}

fn (mut a App) sync_thumb() {
	path := text_value(get(a.properties, 'path'))
	ok := truth(get(a.profile.settings, 'seekPreview')) && path != '' && !is_url(path)
		&& !path.to_lower().ends_with('.edl') && a.source_type != 'iptv'
	a.thumbs.sync_file(if ok { path } else { '' }) or { log_native('Seek preview: ${err.msg()}') }
}

fn (a &App) seek_rect() Rect {
	return Rect{number(a.ui.prop('transport', 'left')) + 23, a.height - 138 + 34, number(a.ui.prop('transport',
		'width')) - 46, 22, 0}
}

fn (mut a App) update_preview(cursor []f64) {
	duration := number(get(a.properties, 'duration'))
	if cursor.len < 2 || !a.controls_shown() || a.dragging || a.dialog_open || duration <= 0 {
		a.thumbs.hide()
		return
	}
	rect := a.seek_rect()
	if cursor[0] >= rect.x && cursor[0] <= rect.x + rect.w && cursor[1] >= rect.y
		&& cursor[1] <= rect.y + rect.h {
		a.thumbs.preview(clamp((cursor[0] - rect.x) / rect.w, 0, 1) * duration, cursor[0],
			a.height - 138, a.width, !a.floating())
	} else {
		a.thumbs.hide()
	}
}
