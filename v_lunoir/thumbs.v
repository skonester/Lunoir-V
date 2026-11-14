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

const thumb_timeout_ms = i64(4000)
const thumb_retry_delay_ms = i64(250)

enum PreviewStage {
	idle
	loading
	warming
	pausing
	seeking
}

struct Thumbnails {
mut:
	parent         voidptr
	backend        MpvController
	surface        NativeVideo
	loaded         string
	enabled        bool
	visible        bool
	file_ready     bool
	stage          PreviewStage
	deadline       i64
	retry_at       i64
	retries        int
	load_id        u64
	pause_id       u64
	awaiting_start bool
	has_frame      bool
	video_h        f64 = 180
	queued         f64 = -1
	requested      f64 = -1
	last_seek      i64
	place_args     []f64
}

fn (mut p Thumbnails) sync_file(path string) ! {
	if path == '' {
		p.enabled = false
		p.loaded = ''
		p.file_ready = false
		p.has_frame = false
		p.reset_request()
		p.retry_at = 0
		p.hide()
		p.backend.cancel_pending()
		if !isnil(p.backend.handle) { p.backend.command([json2.Any('stop')]) or {} }
		return
	}
	if path == p.loaded { return }
	p.enabled = true
	if isnil(p.backend.handle) {
		p.surface = new_video(p.parent, 8)!
		p.backend.start(p.surface.hwnd, thumb_options, false) or {
			p.surface.close()
			return err
		}
		p.backend.handle.observe_property(1, 'video-params/aspect', .node)!
	}
	p.hide()
	p.loaded = path
	p.backend.cancel_pending()
	p.retries = 0
	p.retry_at = 0
	p.load(time.now().unix_milli()) or {
		p.recover(err.msg(), time.now().unix_milli())
		return err
	}
}

fn (mut p Thumbnails) load(now i64) ! {
	p.reset_request()
	p.file_ready = false
	p.has_frame = false
	p.awaiting_start = true
	p.stage = .loading
	p.deadline = now + thumb_timeout_ms
	// All earlier replies belong to the stopped/timed-out attempt.
	p.load_id = p.backend.command([json2.Any('loadfile'), p.loaded, 'replace'])!
}

fn (mut p Thumbnails) reset_request() {
	p.stage = .idle
	p.deadline = 0
	p.pause_id = 0
	p.awaiting_start = false
}

fn (mut p Thumbnails) recover(reason string, now i64) {
	log_native('Seek preview: ${reason}')
	p.hide()
	p.reset_request()
	p.file_ready = false
	p.has_frame = false
	p.retry_at = 0
	// Drop unsent seeks and cancel an in-flight command before recovery. The
	// main player's controller and media never participate in this reset.
	p.backend.cancel_pending()
	if !isnil(p.backend.handle) {
		p.backend.set_property('pause', true) or {}
		p.backend.command([json2.Any('stop')]) or {}
	}
	if p.enabled && p.loaded != '' && p.retries < 1 {
		p.retries++
		p.retry_at = now + thumb_retry_delay_ms
	} else {
		p.enabled = false
	}
}

fn (mut p Thumbnails) watchdog(now i64) {
	if p.deadline > 0 && now >= p.deadline {
		p.recover('${p.stage} timed out', now)
	}
}

fn (mut p Thumbnails) handle_event(event map[string]json2.Any, now i64) {
	if !p.enabled || p.retry_at > 0 { return }
	match text_value(get(event, 'event')) {
		'backend-reply' {
			id := u64(get(event, 'request_id').i64())
			if id < p.load_id { return }
			failure := text_value(get(event, 'error'))
			if failure != '' {
				p.recover(failure, now)
				return
			}
			if p.stage == .pausing && id == p.pause_id {
				p.has_frame = true
				p.reset_request()
			}
		}
		'start-file' {
			p.awaiting_start = false
		}
		'file-loaded' {
			if p.awaiting_start || p.stage != .loading { return }
			p.deadline = now + thumb_timeout_ms
		}
		'property-change' {
			if text_value(get(event, 'name')) == 'video-params/aspect' {
				p.fit_aspect(number(get(event, 'data')))
			}
		}
		'playback-restart' {
			if p.awaiting_start { return }
			match p.stage {
				.loading {
					p.file_ready = true
					p.reset_request()
				}
				.warming {
					p.stage = .pausing
					p.deadline = now + thumb_timeout_ms
					p.pause_id = p.backend.set_property('pause', true) or {
						p.recover(err.msg(), now)
						return
					}
				}
				.seeking {
					p.reset_request()
				}
				else {}
			}
		}
		'end-file' {
			if !p.awaiting_start && text_value(get(event, 'reason')) == 'error' {
				p.recover('could not load preview media', now)
			}
		}
		else {}
	}
}

fn (mut p Thumbnails) tick() {
	if isnil(p.backend.handle) { return }
	now := time.now().unix_milli()
	for event in p.backend.events() {
		p.handle_event(event, now)
	}
	p.watchdog(now)
	if p.retry_at > 0 && now >= p.retry_at {
		p.retry_at = 0
		p.load(now) or { p.recover(err.msg(), now) }
	}
	if p.visible && p.file_ready && p.queued >= 0 && now - p.last_seek >= 70 {
		p.flush()
	}
}

fn (mut p Thumbnails) fit_aspect(value f64) {
	mut aspect := value
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
	if !p.enabled || p.retry_at > 0 || isnil(p.backend.handle) { return }
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
	if p.stage != .idle { return }
	position := p.queued
	p.last_seek = time.now().unix_milli()
	if !p.has_frame {
		p.stage = .warming
		p.deadline = p.last_seek + thumb_timeout_ms
		p.backend.command([json2.Any('seek'), position, 'absolute+exact']) or {
			p.recover(err.msg(), p.last_seek)
			return
		}
		p.backend.set_property('pause', false) or { p.recover(err.msg(), p.last_seek) }
		return
	}
	p.queued = -1
	p.stage = .seeking
	p.deadline = p.last_seek + thumb_timeout_ms
	p.backend.command([json2.Any('seek'), position, 'absolute+exact']) or {
		p.recover(err.msg(), p.last_seek)
		return
	}
	p.backend.command([json2.Any('show-text'), duration_text(position), 100000]) or {
		p.recover(err.msg(), p.last_seek)
	}
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
	p.loaded = ''
	p.retry_at = 0
	p.file_ready = false
	p.has_frame = false
	p.reset_request()
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
