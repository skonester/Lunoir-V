module main

import os
import time
import math
import x.json2

struct App {
mut:
	root                 string
	caption              string
	profile              Profile
	t                    Translator
	ui                   FletUi
	backend              MpvController
	surface              NativeVideo
	ready                bool
	closed               bool
	has_media            bool
	width                f64 = 1120
	height               f64 = 760
	properties           map[string]json2.Any
	queue                []Entry
	index                int    = -1
	source_type          string = 'queue'
	playlist_key         string
	source_ua            string
	open_target          string
	open_kind            string
	recent_pending       bool
	current              string
	resume_target        string
	pending_resume       string
	panel_mode           string
	settings_tab         string = 'playback'
	library_tab          string = 'recent'
	channel_query        string
	url_mode             bool
	repeat_mode          string = 'off'
	shuffle              bool
	shuffle_history      []int
	revealed             bool = true
	dragging             bool
	volume_dragging      bool
	dialog_open          bool
	last_activity        i64
	last_cursor          []f64
	last_saved           i64
	toast_until          i64
	osd_until            i64
	repaint_at           []i64
	repaint_flip         bool
	zoom                 f64
	pan_x                f64
	pan_y                f64
	pan_origin           []f64
	pan_was_playing      bool
	stepping_until       i64
	last_arrow           string
	last_arrow_at        i64
	arrow_mode           string
	last_step            i64
	aspect               string = 'default'
	applied_aspect       string
	applied_keepaspect   bool = true
	aspect_initialized   bool
	ytdl_error           string
	ytdl_http_error      string
	ytdl_hls_retry       bool
	load_failed_at       i64
	info_data            map[string]json2.Any
	work                 chan WorkResult = chan WorkResult{cap: 32}
	revision             i64
	ytdl_working         bool
	ytdl_version         string
	ytdl_version_known   bool
	ytdl_version_reading bool
	ytdl_state           string = 'idle'
	pending_load         bool
	pending_playlist     string
	event_target         int
	test_started         i64
	test_steps           []json2.Any
	test_index           int
	next_snapshot        i64
	snapshot_number      int
	instance             &C.LunoirInstance = unsafe { nil }
	thumbs               Thumbnails
	drop                 &C.LunoirDrop = unsafe { nil }
	flet_pid             int
}

fn (mut a App) message(message json2.Any) {
	items := list_value(message)
	if items.len < 2 { return }
	action, body := items[0].int(), object(items[1])
	if os.getenv('LUNOIR_V_TRACE') != '' { log_native('flet ${json_encode(message)}') }
	match action {
		0 {
			a.closed = true
		}
		1 {
			page := object(get(body, 'page'))
			if 'media' in page { a.ui.set('page', 'media', get(page, 'media')) }
			a.ui.send(1, {
				'session_id': json2.Any('lunoir-v-${os.getpid()}')
				'page_patch': a.ui.tree(1)
				'error':      ''
			}) or { a.closed = true }
			a.ui.registered = true
			a.ui.pending.clear()
			mut operations := []json2.Any{}
			for key in ['width', 'height', 'min_width', 'min_height', 'title_bar_hidden',
				'prevent_close', 'left', 'top'] {
				value := a.ui.prop('window', key)
				if value !is json2.Null { operations << json2.Any([json2.Any(1), 0, key, value]) }
			}
			a.ui.pending[2] = operations
		}
		3 {
			target := get(body, 'target').int()
			a.event_target = target
			name := text_value(get(body, 'name'))
			data := get(body, 'data')
			if handler := a.ui.events['${target}:${name}'] {
				a.dispatch(handler.name, handler.args, data)
			}
		}
		4 {
			a.ui.receive_props(get(body, 'id').int(), object(get(body, 'props')))
		}
		5 {
			call := text_value(get(body, 'call_id'))
			if call.starts_with('snapshot:') {
				result := get(body, 'result')
				if result is string && result.len > 8 {
					directory := os.getenv('LUNOIR_V_SNAPSHOTS')
					os.mkdir_all(directory) or {}
					os.write_file(os.join_path(directory, '${call[9..]}.png'), result) or {
						log_native(err.msg())
					}
				} else {
					log_native('Snapshot failed: ' + json_encode(get(body, 'error')))
				}
			}
		}
		else {}
	}
}

fn (a &App) floating() bool {
	return text_value(get(a.profile.settings, 'oscStyle')) != 'docked'
}

fn (a &App) controls_shown() bool {
	return a.has_media && (!a.floating() || a.revealed || a.panel_mode != '' || a.dragging)
}

fn (a &App) full_screen() bool {
	return truth(a.ui.prop('window', 'full_screen'))
}

fn (mut a App) layout() {
	width, height := a.width, a.height
	top := if a.full_screen() { 0.0 } else { 40.0 }
	panel_open := a.panel_mode != ''
	available := width - if panel_open { 352 } else { 0 }
	video := if a.floating() {
		Rect{0, top, width, height - top, 0}
	} else {
		Rect{16, top + 16, math.max(1.0, available - 32), math.max(1.0,
			height - top - 16 - 118 - 36), 0}
	}
	a.ui.set('header', 'visible', !a.full_screen())
	home_visible := !a.has_media
	a.ui.set('home', 'visible', home_visible)
	a.ui.set('home_entries', 'visible', home_visible)
	a.ui.set('home', 'top', top)
	a.ui.set('video_area', 'visible', a.has_media)
	for name, value in {
		'left':   video.x
		'top':    video.y
		'width':  video.w
		'height': video.h
	} {
		a.ui.set('video_area', name, value)
	}
	transport_width := clamp(available - 40, 300, 840)
	a.ui.set('transport', 'visible', a.controls_shown())
	a.ui.set('transport', 'width', transport_width)
	a.ui.set('transport', 'left', (available - transport_width) / 2)
	a.ui.set('panel', 'visible', panel_open)
	a.ui.set('panel', 'top', top + 16)
	a.ui.set('panel', 'bottom', 16)
	toast_width := math.min(460.0, width - 40)
	a.ui.set('toast', 'width', toast_width)
	a.ui.set('toast', 'left', (width - toast_width) / 2)
	a.ui.set('toast', 'top', top + 16)
	osd_width := number(a.ui.prop('osd', 'width'))
	osd_top := (if a.controls_shown() { height - 20 - 118 - 12 } else { height - 88 }) - 36
	a.ui.set('osd', 'left', (available - osd_width) / 2)
	a.ui.set('osd', 'top', osd_top)
	mut holes := []Rect{}
	if a.controls_shown() {
		holes << Rect{(available - transport_width) / 2, height - 20 - 118, transport_width, 118, 24}
	}
	if panel_open { holes << Rect{width - 336, top + 16, 320, height - top - 32, 18} }
	if truth(a.ui.prop('toast', 'visible')) {
		holes << Rect{(width - toast_width) / 2, top + 16, toast_width, 44, 12}
	}
	if truth(a.ui.prop('osd', 'visible')) {
		holes << Rect{(available - osd_width) / 2, osd_top, osd_width, 36, 8}
	}
	if a.ready {
		moved := a.surface.layout(video, width)
		cut := a.surface.set_holes(holes)
		a.surface.show(a.has_media && !a.dialog_open)
		if moved || cut {
			now := time.now().unix_milli()
			a.repaint_at = [now + 30, now + 120, now + 300]
		}
	}
}

fn (mut a App) tick() {
	now := time.now().unix_milli()
	// Log messages can arrive after end-file; collect the HTTP cause before retrying.
	if a.load_failed_at > 0 && now >= a.load_failed_at {
		a.load_failed_at = 0
		a.finish_failed_load()
	}
	if !isnil(a.instance) {
		for paths in instance_requests(a.instance) {
			a.open_paths(paths)
		}
	}
	if !isnil(a.drop) {
		paths := drop_requests(a.drop)
		if paths.len > 0 { a.open_paths(paths) }
	}
	if a.test_started == 0 { a.test_started = now }
	if a.test_index < a.test_steps.len {
		step := object(a.test_steps[a.test_index])
		if now - a.test_started >= get(step, 'at').i64() {
			a.test_index++
			a.dispatch(text_value(get(step, 'action')), list_value(get(step, 'args')), get(step,
				'data'))
			output := get(step, 'state')
			if output is string && output != '' {
				os.write_file(output, json_encode(a.test_state())) or {}
			}
		}
	}
	interval := os.getenv('LUNOIR_V_SNAPSHOT_INTERVAL').int()
	if os.getenv('LUNOIR_V_SNAPSHOTS') != '' && interval > 0 && now >= a.next_snapshot {
		a.next_snapshot = now + interval
		a.capture_snapshot()
	}
	for _ in 0 .. 32 {
		select {
			result := <-a.work {
				a.work_result(result)
			}
			else {
				break
			}
		}
	}
	if a.toast_until > 0 && now >= a.toast_until {
		a.toast_until = 0
		a.ui.set('toast', 'visible', false)
		a.layout()
	}
	if a.osd_until > 0 && now >= a.osd_until {
		a.osd_until = 0
		a.ui.set('osd', 'visible', false)
		a.layout()
	}
	if a.repaint_at.len > 0 && now >= a.repaint_at[0] {
		a.repaint_at.delete(0)
		a.repaint_flip = !a.repaint_flip
		a.ui.set('backdrop', 'bgcolor', if a.repaint_flip { '#17171D' } else { '#17171C' })
	}
	if cursor := a.surface.cursor() {
		if a.last_cursor.len == 2 && cursor != a.last_cursor { a.activity() }
		a.last_cursor = cursor.clone()
	} else {
		a.last_cursor.clear()
	}
	a.update_preview(a.last_cursor)
	a.thumbs.tick()
	delay := math.max(0.0, number(get(a.profile.settings, 'oscHideDelay')))
	if a.revealed && a.has_media && a.floating() && a.panel_mode == '' && !a.dragging
		&& !a.volume_dragging && now - a.last_activity >= i64(delay * 1000)
		&& !a.over_transport(a.last_cursor) {
		a.revealed = false
		a.layout()
	}
	if a.current != '' && now - a.last_saved > 5000 { a.persist() }
}

fn (mut a App) capture_snapshot() {
	if os.getenv('LUNOIR_V_SNAPSHOTS') == '' { return }
	a.snapshot_number++
	a.ui.invoke(1, 'take_screenshot', map[string]json2.Any{}, 'snapshot:${a.snapshot_number:03}') or {
		log_native(err.msg())
	}
}

fn (a &App) test_state() map[string]json2.Any {
	mut result := a.properties.clone()
	result['_controller_pid'] = os.getpid()
	result['_flet_pid'] = a.flet_pid
	result['_queue'] = a.queue.map(json2.Any(it.path))
	result['_index'] = a.index
	result['_panel'] = a.panel_mode
	result['_language'] = a.t.locale
	result['_controls'] = a.ui.controls.len
	result['_ready'] = a.ready
	result['_dialog_open'] = a.dialog_open
	result['_dialog_controls'] = list_value(get(a.ui.controls[5] or {
		map[string]json2.Any{}
	}, 'controls')).len
	result['_thumb_ready'] = a.thumbs.file_ready
	result['_thumb_height'] = a.thumbs.video_h
	result['_thumb_visible'] = a.thumbs.visible
	result['_thumb_position'] = a.thumbs.backend.get_property('time-pos')
	result['_thumb_frame'] = a.thumbs.has_frame
	return result
}

fn (a &App) over_transport(cursor []f64) bool {
	if cursor.len < 2 { return false }
	left, width := number(a.ui.prop('transport', 'left')), number(a.ui.prop('transport', 'width'))
	return cursor[0] >= left && cursor[0] <= left + width && cursor[1] >= a.height - 138
		&& cursor[1] <= a.height - 20
}

fn (mut a App) activity() {
	a.last_activity = time.now().unix_milli()
	if !a.revealed {
		a.revealed = true
		a.layout()
	}
}

fn (mut a App) notify(message string) {
	a.ui.set('toast_text', 'value', message)
	a.ui.set('toast', 'visible', true)
	a.toast_until = time.now().unix_milli() + 3000
	a.layout()
}

fn (mut a App) command(args []json2.Any) json2.Any {
	return a.backend.command(args) or {
		a.notify(err.msg())
		return json2.Null{}
	}
}

fn (mut a App) try_set(name string, value json2.Any) {
	a.backend.set_property(name, value) or { log_native('mpv property ${name}: ${err.msg()}') }
}

fn (a &App) live() bool {
	return a.source_type == 'iptv'
		|| (is_http(a.current) && get(a.properties, 'seekable') == json2.Any(false))
}

fn (a &App) can_resume() bool {
	return a.source_type != 'iptv' && get(a.properties, 'seekable') != json2.Any(false)
}

fn (a &App) window_title() string {
	if a.index < 0 || a.index >= a.queue.len { return 'Lunoir' }
	entry := a.queue[a.index]
	if a.source_type == 'iptv' { return if entry.title == '' { 'Lunoir' } else { entry.title }
	 }
	if is_http(entry.path) {
		mut name := text_value(get(a.properties, 'media-title'))
		if name == '' { name = if entry.title == '' { 'Lunoir' } else { entry.title }
		 }
		author := text_value(get(a.properties, 'metadata/by-key/uploader'))
		return name + if author == '' {
			''
		} else {
			' · ' + author
		}
	}
	for key in ['filename', 'media-title'] {
		name := text_value(get(a.properties, key))
		if name != '' { return name }
	}
	return media_name(entry.path)
}

fn (mut a App) update_transport() {
	paused, muted := truth(get(a.properties, 'pause')), truth(get(a.properties, 'mute'))
	a.ui.set('play_button', 'icon', get(a.ui.icons, if paused {
		'PLAY_ARROW_ROUNDED'
	} else {
		'PAUSE_ROUNDED'
	}))
	a.ui.set('play_button', 'tooltip', a.t.tr(if paused { 'osc.play' } else { 'osc.pause' }))
	volume := clamp(number(get(a.properties, 'volume')), 0, 150)
	a.ui.set('mute_button', 'icon', get(a.ui.icons, if muted || volume == 0 {
		'VOLUME_OFF_ROUNDED'
	} else {
		'VOLUME_UP_ROUNDED'
	}))
	a.ui.set('mute_button', 'tooltip', a.t.tr(if muted { 'osc.unmute' } else { 'osc.mute' }))
	duration, position := math.max(0.0, number(get(a.properties, 'duration'))), math.max(0.0, number(get(a.properties,
		'time-pos')))
	a.ui.set('seek', 'disabled', a.live() || duration <= 0)
	a.ui.set('seek', 'opacity', if a.live() { 0 } else { 1 })
	if !a.dragging { a.ui.set('seek', 'value', if duration > 0 {
			math.min(1.0, position / duration)
		} else {
			0.0
		})
	 }
	fps := number(get(a.properties, 'container-fps'))
	frame := current_frame(number(get(a.properties, 'estimated-frame-number')), position, fps)
	mut current, mut total := clock(position), clock(duration)
	if a.live() {
		current, total = '● LIVE', ''
	} else {
		match text_value(get(a.profile.settings, 'timeFormat')) {
			'timecode' {
				current = timecode(frame, fps)
				total = timecode(get(a.properties, 'estimated-frame-count').i64(), fps)
			}
			'frame' {
				current = frame.str()
				total = get(a.properties, 'estimated-frame-count').i64().str()
			}
			else {}
		}
	}
	a.ui.set('time_text', 'value', current)
	a.ui.set('duration_text', 'value', total)
	if !a.volume_dragging { a.ui.set('volume', 'value', if muted { 0.0 } else { volume })
	 }
	mut badges := []string{}
	if is_http(a.current) && truth(get(a.properties, 'video-params/h')) {
		tier := resolution_tier(number(get(a.properties, 'video-params/w')), number(get(a.properties,
			'video-params/h')))
		badges << '${tier}' + if a.source_type == 'iptv' { '' } else { 'p' }
	}
	badges << hdr_label(text_value(get(a.properties, 'video-params/gamma')))
	badges << audio_badge(text_value(get(a.properties, 'audio-codec-name')), number(get(a.properties,
		'audio-params/channel-count')))
	loop_a, loop_b := get(a.properties, 'ab-loop-a'), get(a.properties, 'ab-loop-b')
	if loop_a !is string && loop_a !is json2.Null { badges << 'A ' + clock(number(loop_a)) +
			if loop_b !is string && loop_b !is json2.Null { ' – B ' +
			clock(number(loop_b)) } else { '' }
	 }
	speed := number(get(a.properties, 'speed'))
	if math.abs(speed - 1) > 0.01 { badges << '${speed:g}×' }
	a.ui.set('badges', 'value', badges.filter(it != '').join('  ·  '))
	a.ui.set('title', 'value', a.window_title())
}

fn (mut a App) persist() {
	if !a.ready { return }
	a.last_saved = time.now().unix_milli()
	a.profile.save_position(a.resume_target, number(get(a.properties, 'time-pos')), number(get(a.properties,
		'duration')), a.can_resume()) or { log_native(err.msg()) }
	if truth(get(a.profile.settings, 'rememberVolume')) {
		a.profile.set_setting('volume', get(a.properties, 'volume')) or {}
	}
}

fn (mut a App) close() {
	if a.ready {
		a.persist()
		if truth(get(a.profile.settings, 'rememberWindow')) && !a.full_screen() {
			mut bounds := []int{len: 4}
			C.lv_bounds(a.surface.parent, bounds.data)
			a.profile.set_setting('windowBounds', {
				'x':      json2.Any(bounds[0])
				'y':      bounds[1]
				'width':  number(a.ui.prop('window', 'width'))
				'height': number(a.ui.prop('window', 'height'))
			}) or {}
		}
		if !isnil(a.drop) {
			C.lv_drop_close(a.drop)
			a.drop = unsafe { nil }
		}
		a.thumbs.close()
		a.backend.close()
		a.surface.close()
		a.ready = false
	}
	a.ui.invoke(2, 'destroy', map[string]json2.Any{}, 'close') or {}
}
