module py_flet_lunoir

import log
import os
import rand
import time
import arrays
import math

// TODO(py2v): no V equivalent for import asyncio, flet, win32api, win32con, win32process
// Provide one in python_to_v_import (types.v) or port the module.

// TODO(py2v): no V mapping for asyncio.get_running_loop, asyncio.sleep, win32api.GetAsyncKeyState
// Each site below is stubbed with a zero value.

// TODO(py2v): 2 except handler(s) need a V Result equivalent:
//   except OSError as error (1 stmt)
//   except RuntimeError (1 stmt)

const text = '#EEEEF0'
const dim = '#92929C'
const panel = '#242429'
const line = '#393940'
const header = 40
const transport_height = 118
const panel_width = 320
const osd_height = 36
const osd_widths = {
	'volume': 218,
	'zoom': 94,
}
const frame_step_seconds = 0.025
const aspect_targets = {
	'16:9': 16 / 9,
	'4:3': 4 / 3,
	'2.35': 2.35,
}
const log = log :=
const snapshots = os.environ.get('LUNOIR_V_SNAPSHOTS', '')

pub struct Lunoir {
pub mut:
	backend Any
	profile Any
	ytdl Any
	ytdl_error Any
	ytdl_state Any
	ytdl_version_task ?asyncio.Task
	volume_dragging Any
	settings Any
	t Any
	surface ?NativeVideo
	drop ?DropTarget
	thumbs ?Thumbnails
	preview_cursor Any
	queue []Entry
	index Any
	source_type Any
	playlist_key Any
	source_ua Any
	open_target_kind Any
	recent_pending Any
	shuffle_history []int
	pending_resume Any
	subtitle_revision Any
	aspect Any
	applied_aspect Any
	panel_mode Any
	channel_query Any
	url_mode Any
	info_data map[string]Any
	revealed Any
	last_activity Any
	last_cursor Any
	stepping_until Any
	toast_task ?asyncio.Task
	osd_task ?asyncio.Task
	zoom Any
	pan Any
	pan_origin ?[]Any
	pan_was_playing Any
	repaint_task ?asyncio.Task
	last_saved Any
	properties Any
	caption Any
	title Any
	header Any
	home Any
	home_entries Any
	video_area Any
	time_text Any
	duration_text Any
	badges Any
	seek Any
	play_button Any
	mute_button Any
	volume Any
	repeat_button Any
	shuffle_button Any
	transport Any
	panel_header Any
	panel_body Any
	panel Any
	toast_text Any
	toast Any
	osd_icon Any
	osd_fill Any
	osd_bar Any
	osd_text Any
	osd_number Any
	osd_row Any
	osd Any
	backdrop Any
	root Any
	url_field Any
	ua_field Any
	ready Any
	has_media Any
	dialog_open Any
	repeat Any
	shuffle Any
	dragging Any
	last_arrow Any
	arrow_mode Any
	last_step Any
}

pub fn (mut self Lunoir) init(mut page Page, startup []string, instance ?Instance) {
	self.page, self.startup, self.instance = page, startup, instance
	self.backend = MpvController{}
	self.profile = Profile{}
	self.ytdl = Ytdl(self.profile.directory)
	self.ytdl_error = ''
	self.ytdl_state = 'idle'
	self.ytdl_version_task = none
	self.volume_dragging = false
	self.settings = self.profile.settings
	if !self.settings.get('screenshotDir') {
		self.profile.set('screenshotDir', screenshot_dir(self.settings))
	}
	self.t = Translator{
		system_tag: self.settings['uiLanguage']
	}
	self.surface = none
	self.drop = none
	self.thumbs = none
	self.preview_cursor = none
	self.ready = false
	self.closed = false
	self.has_media = false
	self.dragging = false
	self.dialog_open = false
	self.queue = []Entry{}
	self.index = -1
	self.source_type = 'queue'
	self.playlist_key = ''
	self.source_ua = ''
	self.open_target_kind = ['', '']
	self.recent_pending = false
	self.repeat, self.shuffle = 'off', false
	self.shuffle_history = []int{}
	self.current = ''
	self.resume_target = ''
	self.pending_resume = ''
	self.subtitle_revision = 0
	self.aspect = 'default'
	self.applied_aspect = [true, '']
	self.panel_mode = ''
	self.settings_tab, self.library_tab = 'playback', 'recent'
	self.channel_query = ''
	self.url_mode = false
	self.info_data = map[string]Any{}
	self.revealed = true
	self.last_activity = time.monotonic()
	self.last_cursor = none
	self.arrow_mode, self.last_arrow, self.last_step = '', 0, 0
	self.stepping_until = 0
	self.toast_task = none
	self.osd_task = none
	self.zoom = 0
	self.pan = [0, 0]
	self.pan_origin = none
	self.pan_was_playing = false
	self.repaint_task = none
	self.last_saved = 0
	self.properties = {
		'pause': false,
		'volume': self.settings['volume'],
		'duration': 0,
		'time-pos': 0,
		'mute': false,
		'seekable': true,
		'speed': 1,
	}
	self.caption = 'Lunoir · V · ${os.getpid()}'
	page.title = self.caption
	page.theme_mode = ft.ThemeMode.DARK
	page.theme = ft.Theme('Segoe UI', '#A8A8AE')
	page.bgcolor = '#17171C'
	page.padding = 0
	page.spacing = 0
	page.enable_screenshots = (snapshots != 0)
	page.window.width, page.window.height = 1120, 760
	bounds := self.settings.get('windowBounds')
	if self.settings.get('rememberWindow') && bounds is dict {
		page.window.left, page.window.top = bounds.get('x'), bounds.get('y')
		page.window.width = arrays.max([900, bounds.get('width') || 1120]) or { panic('!') }
		page.window.height = arrays.max([560, bounds.get('height') || 760]) or { panic('!') }
	}
	page.window.min_width, page.window.min_height = 900, 560
	page.window.title_bar_hidden = true
	page.window.prevent_close = true
	page.window.on_event = self.window_event
	page.on_keyboard_event = self.keyboard
	page.on_resize = self.resize
	page.on_disconnect = self.disconnect
	self.build_ui()
}

pub fn (self Lunoir) icon(icon Any, hint Any, callback Any, kwargs map[string]Any) Any {
	return ft.IconButton(icon, hint, 21, dim, callback, kwargs)
}

pub fn handler(_ Any) {
	coroutine(...args)
}
pub fn (self Lunoir) callback(coroutine Any, args ...Any) Any {
	return handler
}

pub fn (mut self Lunoir) build_ui()  {
	t := self.t
	self.page.controls.clear()
	self.title = ft.Text(self.window_title(), 12, dim, 1, ft.TextOverflow.ELLIPSIS)
	self.header = ft.Container(header, 0, 0, 0, '#1E1E23', ft.Row([
		ft.WindowDragArea(ft.Container(ft.Row([ft.Image('logo.png', 22, 22), self.title].map(Any(it)), 10), ft.Padding.only(16)), true),
		self.icon(ft.Icons.REMOVE, t('win.minimize'), self.minimize),
		self.icon(ft.Icons.CROP_SQUARE, t('win.maximize'), self.maximize),
		self.icon(ft.Icons.CLOSE, t('win.close'), self.shutdown),
	].map(Any(it)), 0))
	self.home = ft.GestureDetector(0, header, 0, 0, self.toggle_url_mode, ft.Container(ft.RadialGradient(ft.Alignment(0, -0.25), 1.15, ['#33333B', '#17171D']), ft.Alignment.CENTER, self.home_content()))
	self.home_entries = ft.Container(24, 20, ft.Row([
		self.icon(ft.Icons.STAR_BORDER_ROUNDED, t('osc.library'), self.callback(self.toggle_panel, 'library')),
		self.icon(ft.Icons.SETTINGS_OUTLINED, t('common.settings'), self.callback(self.toggle_panel, 'settings')),
	].map(Any(it)), 8))
	self.video_area = ft.GestureDetector(false, ft.Container('#000000'), self.video_tap, self.video_double_tap, self.video_secondary, self.pointer_moved, 100, self.video_wheel, self.pan_start, self.pan_update, self.pan_end, 16)
	self.time_text = ft.Text('00:00', 11, dim)
	self.duration_text = ft.Text('00:00', 11, dim)
	self.badges = ft.Text('', 11, dim, 1, ft.TextOverflow.ELLIPSIS)
	self.seek = ft.Slider(0, 1, 0, 22, true, ft.Padding.all(0), '#BDBDC4', '#48484F', text, self.seek_start, self.seek_end)
	self.play_button = ft.IconButton(ft.Icons.PLAY_ARROW_ROUNDED, 34, '#222227', '#DEDEE3', 48, 48, t('osc.play'), self.callback(self.command, 'cycle', 'pause'))
	self.mute_button = self.icon(ft.Icons.VOLUME_UP_ROUNDED, t('osc.mute'), self.callback(self.command, 'cycle', 'mute'))
	self.volume = ft.Slider(0, 150, f64(self.properties.get('volume') || 0), 104, 28, ft.Padding.symmetric(8), '#BDBDC4', '#48484F', self.volume_start, self.volume_change, self.volume_end)
	self.repeat_button = self.icon(ft.Icons.REPEAT_ROUNDED, t('panel.repeat.${self.repeat}'), self.cycle_repeat)
	self.shuffle_button = self.icon(ft.Icons.SHUFFLE_ROUNDED, t(if self.shuffle { 'panel.shuffle.on' } else { 'panel.shuffle.off' }), self.toggle_shuffle)
	self.style_repeat_shuffle()
	self.transport = ft.Container(20, transport_height, 24, panel, ft.Border.all(1, line), ft.Padding.symmetric(22, 12), false, self.pointer_moved, ft.Column([
		ft.Row([
		ft.GestureDetector(self.time_text, self.cycle_time_format, ft.MouseCursor.CLICK, t('osc.timeFormat')),
		ft.Container(true),
		self.badges,
		ft.Container(8),
		self.duration_text,
	].map(Any(it)), 18),
		self.seek,
		ft.Row([
		self.shuffle_button,
		self.icon(ft.Icons.SKIP_PREVIOUS_ROUNDED, t('menu.previous'), self.callback(self.advance, -1)),
		self.icon(ft.Icons.REPLAY_10_ROUNDED, t('osc.back', 10), self.callback(self.command, 'seek', -10, 'relative')),
		self.play_button,
		self.icon(ft.Icons.FORWARD_10_ROUNDED, t('osc.forward', 10), self.callback(self.command, 'seek', 10, 'relative')),
		self.icon(ft.Icons.SKIP_NEXT_ROUNDED, t('menu.next'), self.callback(self.advance, 1)),
		self.repeat_button,
		ft.Container(true),
		self.mute_button,
		self.volume,
		self.icon(ft.Icons.QUEUE_MUSIC_ROUNDED, t('osc.panel'), self.callback(self.toggle_panel, 'tracks')),
		self.icon(ft.Icons.STAR_BORDER_ROUNDED, t('osc.library'), self.callback(self.toggle_panel, 'library')),
		self.icon(ft.Icons.SETTINGS_OUTLINED, t('common.settings'), self.callback(self.toggle_panel, 'settings')),
		self.icon(ft.Icons.MORE_HORIZ_ROUNDED, none, self.callback(self.toggle_panel, 'menu')),
		self.icon(ft.Icons.FULLSCREEN_ROUNDED, t('menu.fullscreen'), self.fullscreen),
	].map(Any(it)), 0, 48),
	].map(Any(it)), 3))
	self.panel_header = ft.Row([], 4)
	self.panel_body = ft.Column(ft.ScrollMode.AUTO, true, 6)
	self.panel = ft.Container(16, panel_width, false, self.pointer_moved, panel, ft.Border.all(1, line), 18, ft.Padding.only(18, 10, 12, 14), ft.Column([self.panel_header, ft.Divider(line, 12), self.panel_body].map(Any(it)), 0))
	self.toast_text = ft.Text('', 13, text, ft.TextAlign.CENTER)
	self.toast = ft.Container(false, 44, '#2E2E35', 12, ft.Border.all(1, line), ft.Alignment.CENTER, ft.Padding.symmetric(16), self.toast_text)
	self.osd_icon = ft.Icon(ft.Icons.VOLUME_UP_ROUNDED, 20, text)
	self.osd_fill = ft.Container(0, 4, '#D9D9DA', 2)
	self.osd_bar = ft.Container(120, 4, '#434346', 2, ft.Alignment.CENTER_LEFT, self.osd_fill)
	self.osd_text = ft.Text('', 13, ft.FontWeight.W_500, text)
	self.osd_number = ft.Container(30, ft.Alignment.CENTER_RIGHT, self.osd_text)
	self.osd_row = ft.Row([self.osd_icon, self.osd_bar, self.osd_number].map(Any(it)), 10, true)
	self.osd = ft.Container(false, osd_widths['volume'], osd_height, '#1A1A1E', 8, ft.Padding.symmetric(14), self.osd_row)
	self.backdrop = ft.Container(0, 0, 0, 0, '#17171C')
	self.root = ft.Stack([
		self.backdrop,
		self.home,
		self.video_area,
		self.header,
		self.home_entries,
		self.transport,
		self.panel,
		self.toast,
		self.osd,
	].map(Any(it)), true)
	self.page.add(self.root)
	self.fill_panel()
	self.update_transport()
	self.layout()
}

pub fn advanced(_ Any) {
	self.ua_field.visible = !self.ua_field.visible
	self.page.update()
}
pub fn (mut self Lunoir) home_content() Column {
	t := self.t
	if self.url_mode {
		self.url_field = ft.TextField(t('empty.urlPlaceholder'), 420, true, 12, self.submit_url, true)
		self.ua_field = ft.TextField(t('url.userAgent'), 420, true, false)
		// pass
		mut cta := [
			ft.Row([self.url_field, ft.IconButton(ft.Icons.PLAY_ARROW_ROUNDED, t('empty.urlPlay'), self.submit_url)].map(Any(it)), ft.MainAxisAlignment.CENTER, true),
			ft.TextButton(t('url.advanced'), advanced),
			self.ua_field,
			ft.Text(t('empty.urlBack'), 11, '#6E6E79'),
		]
	} else {
		button := ft.Container(180, 44, 12, '#38383E', ft.Alignment.CENTER, ft.Row([ft.Icon(ft.Icons.FILE_UPLOAD_OUTLINED, 17, text), ft.Text(t('empty.openFile'), text, 14)].map(Any(it)), true, 8))
		cta = [
			ft.GestureDetector(button, ft.MouseCursor.CLICK, self.open_files, self.open_folder),
			ft.Text(t('empty.hint'), 11, '#6E6E79'),
		]
	}
	return ft.Column(([ft.Image('logo.png', 104, 104), ft.Image('Lunoir.png', 232, 68, text), ft.Container(18)]).concat(cta), ft.CrossAxisAlignment.CENTER, ft.MainAxisAlignment.CENTER, 12, true)
}

pub fn (self Lunoir) floating() bool {
	return self.settings.get('oscStyle') != 'docked'
}

pub fn (self Lunoir) controls_shown() bool {
	return self.has_media && (!self.floating() || self.revealed || (self.panel_mode != 0) || self.dragging)
}

pub fn (mut self Lunoir) layout()  {
	width, height := f64(self.page.width || 1120), f64(self.page.height || 760)
	full := (self.page.window.full_screen != 0)
	top := if full { 0 } else { header }
	panel_open := (self.panel_mode != 0)
	available := width - (if panel_open { panel_width + 32 } else { 0 })
	if self.floating() {
		mut video := [0, top, width, height - top]
	} else {
		video = [16, top + 16, arrays.max([1, available - 32]) or { panic('!') }, arrays.max([1, height - top - 16 - transport_height - 36]) or { panic('!') }]
	}
	self.header.visible = !full
	self.home.visible = !self.has_media
	self.home_entries.visible = !self.has_media
	self.home.top = top
	self.video_area.visible = self.has_media
	py2v_unpack1 := video
	mut self.video_area.left := py2v_unpack1[0]
	mut self.video_area.top := py2v_unpack1[1]
	mut self.video_area.width := py2v_unpack1[2]
	mut self.video_area.height := py2v_unpack1[3]
	self.transport.visible = self.controls_shown()
	self.transport.width = arrays.max([300, arrays.min([840, available - 40]) or { panic('!') }]) or { panic('!') }
	self.transport.left = (available - self.transport.width) / 2
	self.panel.visible = panel_open
	self.panel.top, self.panel.bottom = top + 16, 16
	self.toast.width = arrays.min([460, width - 40]) or { panic('!') }
	self.toast.left, self.toast.top = (width - self.toast.width) / 2, top + 16
	self.osd.left = (available - self.osd.width) / 2
	self.osd.top = (if self.transport.visible { height - 20 - transport_height - 12 } else { height - 88 }) - osd_height
	mut holes := []
	if self.transport.visible {
		holes << [self.transport.left, height - 20 - transport_height, self.transport.width, transport_height, 24]
	}
	if self.panel.visible {
		holes << [width - 16 - panel_width, top + 16, panel_width, height - top - 32, 18]
	}
	if self.toast.visible {
		holes << [self.toast.left, self.toast.top, self.toast.width, 44, 12]
	}
	if self.osd.visible {
		holes << [self.osd.left, self.osd.top, self.osd.width, osd_height, 8]
	}
	if self.surface {
		moved := self.surface.layout(...video, width)
		if self.surface.set_holes(holes) || moved {
			self.schedule_repaint()
		}
		self.surface.show(self.has_media && !self.dialog_open)
	}
}

pub fn repaint() {
	for delay in [0.03, 0.12, 0.3] {
		_ = Any(0)
		if self.closed {
			return
		}
		mut backdrop := self.backdrop
		backdrop.bgcolor = if backdrop.bgcolor == '#17171C' { '#17171D' } else { '#17171C' }
		backdrop.update()
	}
}
pub fn (mut self Lunoir) schedule_repaint()  {
	if self.repaint_task && !self.repaint_task.done() {
		self.repaint_task.cancel()
	}
	self.repaint_task = Any(0).create_task(repaint())
	// except handlers are not translated: see the TODO(py2v) note above
	//   except RuntimeError: 1 statement(s) need an `or { ... }` equivalent
}

pub fn (self Lunoir) refresh()  {
	self.layout()
	self.page.update()
}

pub fn (self Lunoir) sync_thumb()  {
	if !self.thumbs {
		return
	}
	path := self.properties.get('path')
	ok := (self.settings.get('seekPreview') != 0) && path is str && (path != 0) && !is_url(path) && !path.to_lower().ends_with('.edl') && self.source_type != 'iptv'
	go self.thumbs.sync_file(if ok { path } else { none })
}

pub fn (mut self Lunoir) watch_pointer() bool {
	if !self.surface {
		return false
	}
	cursor := self.surface.cursor()
	mut changed := false
	if cursor != none && self.last_cursor != none && cursor != self.last_cursor {
		changed = self.activity()
	}
	self.last_cursor = cursor
	self.update_preview(cursor)
	delay := arrays.max([1, f64(self.settings.get('oscHideDelay') || 5)]) or { panic('!') }
	if self.revealed && self.has_media && self.floating() && !self.panel_mode && !self.dragging && time.monotonic() - self.last_activity > delay && !self.over_transport(cursor) {
		self.revealed = false
		changed = true
	}
	return changed
}

pub fn (self Lunoir) seek_rect() (f64, f64, f64, f64) {
	top := f64(self.page.height || 760) - 20 - transport_height + 1 + 12 + 18 + 3
	return self.transport.left + 23, top, self.transport.width - 46, 22
}

pub fn (mut self Lunoir) update_preview(cursor Any)  {
	if !self.thumbs {
		return
	}
	if cursor == self.preview_cursor && self.thumbs.visible {
		return
	}
	self.preview_cursor = cursor
	duration := f64(self.properties.get('duration') || 0)
	held := [win32con.VK_LBUTTON, win32con.VK_RBUTTON].map(Any(0) & 32768).any(it)
	py2v_unpack2 := self.seek_rect()
	mut left := py2v_unpack2[0]
	mut top := py2v_unpack2[1]
	mut width := py2v_unpack2[2]
	mut height := py2v_unpack2[3]
	if cursor == none || !self.transport.visible || self.seek.disabled || duration <= 0 || self.dragging || held || self.dialog_open || width <= 0 || !(left - 2 <= cursor[0] && top - 4 <= cursor[1]) {
		self.thumbs.hide()
		return
	}
	t := (arrays.max([0, arrays.min([1, (cursor[0] - left) / width]) or { panic('!') }]) or { panic('!') }) * duration
	self.thumbs.preview(t, cursor[0], f64(self.page.height || 760) - 20 - transport_height, f64(self.page.width || 1120), !self.floating())
}

pub fn (self Lunoir) over_transport(cursor Any) bool {
	if cursor == none || !self.transport.visible {
		return false
	}
	height := f64(self.page.height || 760)
	py2v_unpack3 := cursor
	mut x := py2v_unpack3[0]
	mut y := py2v_unpack3[1]
	return self.transport.left <= x && height - 20 - transport_height <= y
}

pub fn (mut self Lunoir) activity() bool {
	self.last_activity = time.monotonic()
	if !self.revealed {
		self.revealed = true
		return true
	}
	return false
}

pub fn (self Lunoir) window_title() string {
	props := self.properties
	entry := if 0 <= self.index { self.queue[self.index] } else { none }
	if !entry {
		return 'Lunoir'
	}
	if self.source_type == 'iptv' {
		return entry.title || 'Lunoir'
	}
	if is_http(entry.path) {
		base := props.get('media-title') || entry.title || 'Lunoir'
		author := props.get('metadata/by-key/uploader')
		return if author { '${base} · ${author}' } else { base }
	}
	return props.get('filename') || props.get('media-title') || media_name(entry.path)
}

pub fn (self Lunoir) is_live() bool {
	return self.source_type == 'iptv' || (is_http(self.current) && self.properties.get('seekable') == false)
}

pub fn (mut self Lunoir) update_transport()  {
	t, props := self.t, self.properties
	paused := (props.get('pause') != 0)
	self.play_button.icon = if paused { ft.Icons.PLAY_ARROW_ROUNDED } else { ft.Icons.PAUSE_ROUNDED }
	self.play_button.tooltip = if paused { t('osc.play') } else { t('osc.pause') }
	muted := (props.get('mute') != 0)
	volume := arrays.max([0, arrays.min([150, f64(props.get('volume') || 0)]) or { panic('!') }]) or { panic('!') }
	self.mute_button.icon = if muted || !volume { ft.Icons.VOLUME_OFF_ROUNDED } else { ft.Icons.VOLUME_UP_ROUNDED }
	self.mute_button.tooltip = if muted { t('osc.unmute') } else { t('osc.mute') }
	duration := arrays.max([0, f64(props.get('duration') || 0)]) or { panic('!') }
	position := arrays.max([0, f64(props.get('time-pos') || 0)]) or { panic('!') }
	live := self.is_live()
	self.seek.disabled = live || duration <= 0
	self.seek.opacity = if live { 0 } else { 1 }
	if !self.dragging {
		self.seek.value = if duration { arrays.min([1, position / duration]) or { panic('!') } } else { 0 }
	}
	style := self.settings.get('timeFormat', 'time')
	fps := props.get('container-fps')
	if live {
		self.time_text.value, self.duration_text.value = '● LIVE', ''
	} else if style == 'timecode' {
		frame := current_frame(props.get('estimated-frame-number'), position, fps)
		self.time_text.value = timecode(frame, fps)
		self.duration_text.value = timecode(props.get('estimated-frame-count') || 0, fps)
	} else if style == 'frame' {
		self.time_text.value = (current_frame(props.get('estimated-frame-number'), position, fps))
		self.duration_text.value = (int(props.get('estimated-frame-count') || 0))
	} else {
		self.time_text.value, self.duration_text.value = clock(position), clock(duration)
	}
	if !self.volume_dragging {
		self.volume.value = if muted { 0 } else { volume }
	}
	mut badges := []
	if is_http(self.current) && props.get('video-params/h') {
		tier := resolution_tier(props.get('video-params/w'), props.get('video-params/h'))
		badges << '${tier}${if self.source_type == 'iptv' { '' } else { 'p' }}'
	}
	badges << hdr_label(props.get('video-params/gamma'))
	badges << audio_badge(props.get('audio-codec-name') || '', props.get('audio-params/channel-count'))
	a, b := props.get('ab-loop-a'), props.get('ab-loop-b')
	if (a is int || a is float) {
		badges << 'A ${clock(a)}' + (if (b is int || b is float) { ' – B ${clock(b)}' } else { '' })
	}
	speed := props.get('speed') || 1
	if math.abs(speed - 1) > 0.01 {
		badges << '${speed}×'
	}
	self.badges.value = (badges.filter(it).map(it))
	self.title.value = self.window_title()
}

pub fn (self Lunoir) can_resume() bool {
	return self.source_type != 'iptv' && self.properties.get('seekable') != false
}

pub fn (mut self Lunoir) set_queue(entries []Entry)  {
	self.queue = entries
	self.index = -1
	self.shuffle_history = []
	self.channel_query = ''
}

pub fn (self Lunoir) resume_index() int {
	if !self.settings.get('resumePlaylistItem') {
		return 0
	}
	last := self.profile.playlist_items.get(self.playlist_key)
	return next((fn () [][]Any { mut r := [][]Any{}; for i, v in self.queue { r << [Any(i), v] }; return r }()).filter(entry.path == last).map(i), 0)
}

pub fn (self Lunoir) refill_settings()  {
	if self.panel_mode == 'settings' {
		self.fill_panel()
		self.refresh()
	}
}

pub fn read() {
	self.ytdl.read_version()
	self.ytdl_version_task = none
	self.refill_settings()
}
pub fn (mut self Lunoir) show_ytdl_version()  {
	if self.ytdl.version == none && !self.ytdl_version_task && self.ytdl.exe.is_file() {
		// pass
		self.ytdl_version_task = go read()
	}
}

pub fn (self Lunoir) next_index(step int) ?int {
	count := self.queue.len
	if self.shuffle && count > 1 {
		if step < 0 {
			return if self.shuffle_history { self.shuffle_history.pop() } else { none }
		}
		self.shuffle_history << self.index
		return random.choice([]int{len: count, init: index}.filter(it != self.itndex).map(it))
	}
	mut index := self.index + step
	if self.repeat == 'all' {
		index %= count
	}
	return if 0 <= index { index } else { none }
}

pub fn (self Lunoir) fill_panel()  {
	fill(self)
}

pub fn (self Lunoir) favourite_target(target string)  {
	if self.profile.is_favourite(target) {
		return
	}
	mut extra := map[string]Any{}
	if target == self.open_target_kind[0] {
		mut kind := self.open_target_kind[1]
		if kind == 'list' && self.source_type == 'iptv' {
			extra['channels'] = self.queue.map({
				'namit': it.titlit,
				'url': it.path,
				'group': it.group,
			})
		} else if kind == 'list' {
			kind = 'url'
		}
		if self.source_ua {
			extra['userAgent'] = self.source_ua
		}
		mut name := if kind == 'list' { media_name(target) } else { self.window_title() }
	} else {
		kind = if is_channel_list(target) { 'list' } else { if is_url(target) { 'url' } else { 'file' } }
		recent := next(self.profile.recents.filter(it.get('taitget') == taitget).map(it), none)
		name = (recent && recent.get('name')) || (if kind == 'url' { target } else { media_name(target) || target })
	}
	self.profile.toggle_favourite(target, name, kind, extra)
}

pub fn (self Lunoir) collection_key() string {
	if self.source_type == 'iptv' {
		return self.open_target_kind[0]
	}
	return if self.queue { queue_key(self.queue.map(it.path)) } else { '' }
}

pub fn (self Lunoir) queue_name() string {
	first := if self.queue { self.queue[0] } else { none }
	if !first {
		return 'Playlist'
	}
	base := first.title || media_name(first.path)
	folder := if is_url(first.path) { '' } else { os.path.basename(os.path.dirname(first.path)) }
	return if self.queue.len > 1 && folder { folder } else { base }
}

pub fn (mut self Lunoir) style_repeat_shuffle()  {
	self.repeat_button.icon = if self.repeat == 'one' { ft.Icons.REPEAT_ONE_ROUNDED } else { ft.Icons.REPEAT_ROUNDED }
	self.repeat_button.icon_color = if self.repeat != 'off' { text } else { dim }
	self.repeat_button.tooltip = self.t('panel.repeat.${self.repeat}')
	self.shuffle_button.icon_color = if self.shuffle { text } else { dim }
	self.shuffle_button.tooltip = self.t(if self.shuffle { 'panel.shuffle.on' } else { 'panel.shuffle.off' })
}

pub fn (mut self Lunoir) persist()  {
	self.last_saved = time.monotonic()
	self.profile.save_position(self.current, f64(self.properties.get('time-pos') || 0), f64(self.properties.get('duration') || 0), self.can_resume())
	volume := self.properties.get('volume')
	if (volume is int || volume is float) && self.settings.get('volume') != volume {
		self.profile.set('volume', volume)
	}
	// except handlers are not translated: see the TODO(py2v) note above
	//   except OSError as error: 1 statement(s) need an `or { ... }` equivalent
}

pub fn hide() {
	_ = Any(0)
	self.toast.visible = false
	self.refresh()
}
pub fn (mut self Lunoir) notify(text string)  {
	self.toast_text.value = text
	self.toast.visible = true
	if self.toast_task {
		self.toast_task.cancel()
	}
	self.toast_task = Any(0).create_task(hide())
	// except handlers are not translated: see the TODO(py2v) note above
	//   except RuntimeError: 1 statement(s) need an `or { ... }` equivalent
	self.refresh()
}

pub fn hide() {
	_ = Any(0)
	self.osd.visible = false
	self.refresh()
}
pub fn (mut self Lunoir) show_osd(kind string, value int, seconds f64)  {
	zoom := kind == 'zoom'
	if zoom {
		self.osd_icon.icon = if value > 100 { ft.Icons.ZOOM_IN_ROUNDED } else { ft.Icons.ZOOM_OUT_ROUNDED }
	} else {
		self.osd_icon.icon = if value == 0 { ft.Icons.VOLUME_OFF_ROUNDED } else { ft.Icons.VOLUME_UP_ROUNDED }
	}
	self.osd_icon.size = if zoom { 16 } else { 20 }
	self.osd_bar.visible = !zoom
	self.osd_fill.width = 1.2 * (arrays.min([100, value]) or { panic('!') })
	self.osd_number.width = if zoom { 42 } else { 30 }
	self.osd_text.value = if zoom { '${value}%' } else { value }
	self.osd_row.spacing = if zoom { 8 } else { 10 }
	self.osd.width = osd_widths[kind]
	self.osd.visible = true
	if self.osd_task {
		self.osd_task.cancel()
	}
	self.osd_task = Any(0).create_task(hide())
	self.refresh()
}

pub fn (self Lunoir) save_window()  {
	window := self.page.window
	if !self.settings.get('rememberWindow') || window.full_screen || window.maximized || window.minimized {
		return
	}
	if (none !in [window.left, window.top, window.width, window.height]) {
		self.profile.set('windowBounds', map[string]Any{
			'x': math.round(window.left),
			'y': math.round(window.top),
			'width': math.round(window.width),
			'height': math.round(window.height),
		})
	}
}

pub fn app_main(page Page, startup ?[]string, instance ?Instance)  {
	app := Lunoir{
		backend: page
		profile: startup || []
		ytdl: instance
	}
	page.run_task(app.start)
}
