module main

import os
import time
import math
import x.json2

fn (a &App) input_value(data json2.Any) json2.Any {
	if data is string || data is bool || data is int || data is i64 || data is f64 { return data }
	return get(a.ui.controls[a.event_target] or {
		map[string]json2.Any{}
	}, 'value')
}

fn (mut a App) dispatch(name string, args []json2.Any, data json2.Any) {
	first := if args.len > 0 { args[0] } else { json2.Any(json2.Null{}) }
	match name {
		'snapshot_state' {}
		'snapshot' {
			a.capture_snapshot()
		}
		'shutdown', 'disconnect' {
			a.closed = true
		}
		'window_event' {
			event := text_value(get(object(data), 'type'))
			if event == '' && data is string {
				if data == 'close' { a.closed = true }
			}
			if event == 'close' { a.closed = true }
		}
		'minimize' {
			a.ui.set('window', 'minimized', true)
		}
		'maximize' {
			a.ui.set('window', 'maximized', !truth(a.ui.prop('window', 'maximized')))
		}
		'fullscreen' {
			a.fullscreen()
		}
		'resize' {
			properties := object(data)
			width, height := number(get(properties, 'width')), number(get(properties, 'height'))
			if width > 0 { a.width = width }
			if height > 0 { a.height = height }
			a.layout()
		}
		'keyboard' {
			a.keyboard(object(data))
		}
		'command' {
			a.command(args)
		}
		'set_property' {
			if args.len >= 2 { a.try_set(text_value(args[0]), args[1]) }
		}
		'advance' {
			a.advance(first.int(), false)
		}
		'play_index' {
			a.play_index(first.int())
		}
		'remove_item' {
			a.remove_item(first.int())
		}
		'open_target' {
			a.open_target_path(text_value(first), '')
		}
		'open_files', 'open_folder', 'add_files', 'add_audio', 'add_subtitle',
		'browse_screenshot_dir' {
			a.pick_files(name)
		}
		'open_url' {
			a.url_dialog()
		}
		'toggle_url_mode' {
			a.toggle_url_mode()
		}
		'advanced' {
			a.ui.set('ua_field', 'visible', !truth(a.ui.prop('ua_field', 'visible')))
		}
		'submit_url' {
			url := text_value(a.ui.prop('url_field', 'value')).trim_space()
			agent := text_value(a.ui.prop('ua_field', 'value')).trim_space()
			if url != '' {
				if a.dialog_open { a.dismiss_dialog() }
				a.open_target_path(url, agent)
			}
		}
		'toggle_panel' {
			a.toggle_panel(text_value(first))
		}
		'show_panel' {
			a.panel_mode = text_value(first)
			a.fill_panel()
			a.layout()
		}
		'settings_tab' {
			a.settings_tab = text_value(first)
			a.fill_panel()
		}
		'library_tab' {
			a.library_tab = text_value(first)
			a.fill_panel()
		}
		'setting_bool' {
			a.change_setting(text_value(first), truth(a.input_value(data)))
		}
		'setting_select' {
			a.change_setting(text_value(first), text_value(a.input_value(data)))
		}
		'setting_number' {
			digits := if args.len > 1 { args[1].int() } else { 0 }
			value := number(a.input_value(data))
			a.change_setting(text_value(first), if digits == 0 {
				json2.Any(int(math.round_to_even(value)))
			} else {
				json2.Any(math.round_to_even(value * 10) / 10)
			})
		}
		'setting_moving' {
			if args.len > 1 {
				value := number(a.input_value(data))
				a.ui.set_id(args[1].int(), 'value', if first.int() == 0 {
					'${value:.0f}'
				} else {
					'${value:.1f}'
				})
			}
		}
		'channel_search' {
			a.channel_query = text_value(a.input_value(data))
			a.fill_panel()
		}
		'cycle_time_format' {
			order := ['time', 'timecode', 'frame']
			index := order.index(text_value(get(a.profile.settings, 'timeFormat')))
			a.profile.set_setting('timeFormat', order[(index + 1) % 3]) or {}
			a.update_transport()
		}
		'cycle_repeat' {
			a.repeat_mode = {
				'off': 'all'
				'all': 'one'
				'one': 'off'
			}[a.repeat_mode] or { 'off' }
			a.style_modes()
			a.fill_panel()
		}
		'toggle_shuffle' {
			a.shuffle = !a.shuffle
			a.shuffle_history.clear()
			a.style_modes()
			a.fill_panel()
		}
		'seek_start' {
			a.dragging = true
		}
		'seek_end' {
			a.command([json2.Any('seek'),
				number(a.input_value(data)) * number(get(a.properties, 'duration')), 'absolute'])
			a.dragging = false
			a.activity()
		}
		'volume_start' {
			a.volume_dragging = true
		}
		'volume_change', 'volume_end' {
			volume := clamp(number(a.input_value(data)), 0, 150)
			a.properties['volume'] = volume
			a.properties['mute'] = false
			a.try_set('mute', false)
			a.try_set('volume', volume)
			if name == 'volume_end' { a.volume_dragging = false }
		}
		'pointer_moved' {
			a.activity()
		}
		'video_tap' {
			a.command([json2.Any('cycle'), 'pause'])
		}
		'video_secondary' {
			a.toggle_panel('menu')
		}
		'video_double_tap' {
			if C.lv_key(0x11) != 0 {
				a.set_zoom(0)
			} else {
				a.fullscreen()
			}
		}
		'video_wheel' {
			a.video_wheel(object(data))
		}
		'pan_start' {
			if a.zoom > 0 {
				point := pointer_position(object(data))
				a.pan_origin = [number(get(point, 'x')), number(get(point, 'y')), a.pan_x, a.pan_y]
				a.pan_was_playing = !truth(get(a.properties, 'pause'))
				if a.pan_was_playing { a.try_set('pause', true) }
			}
		}
		'pan_update' {
			if a.pan_origin.len == 4 {
				point := pointer_position(object(data))
				scale := math.pow(2, a.zoom)
				a.pan_x = a.pan_origin[2] + (number(get(point, 'x')) -
					a.pan_origin[0]) / (math.max(1.0, number(a.ui.prop('video_area', 'width')) / 2) * scale)
				a.pan_y = a.pan_origin[3] + (number(get(point, 'y')) -
					a.pan_origin[1]) / (math.max(1.0, number(a.ui.prop('video_area', 'height')) / 2) * scale)
				a.try_set('video-pan-x', a.pan_x)
				a.try_set('video-pan-y', a.pan_y)
			}
		}
		'pan_end' {
			resume := a.pan_origin.len > 0 && a.pan_was_playing
			a.pan_origin.clear()
			a.pan_was_playing = false
			if resume { a.try_set('pause', false) }
		}
		'go_home' {
			a.go_home()
		}
		'screenshot' {
			a.screenshot()
		}
		'set_speed' {
			a.try_set('speed', first)
			a.notify(a.t.format(if number(first) == 1 { 'toast.speedNormal' } else { 'toast.speed' }, {
				'v': text_value(first)
			}))
		}
		'set_aspect' {
			a.aspect = text_value(first)
			a.apply_aspect()
			a.fill_panel()
		}
		'select_audio', 'select_subtitle' {
			a.select_track(name == 'select_audio', first)
		}
		'adjust_reset' {
			a.try_set('sub-delay', 0.0)
			a.try_set('sub-pos', 100)
			a.try_set('sub-scale', 1.0)
		}
		'open_saved' {
			a.open_saved(object(first))
		}
		'favourite_current' {
			a.favourite_target(a.open_target, true)
		}
		'favourite_recent' {
			a.favourite_target(text_value(first), false)
		}
		'save_collection' {
			a.save_collection()
		}
		'remove_recent' {
			a.profile.remove_recent(text_value(first)) or {}
			a.fill_panel()
		}
		'clear_recents' {
			a.confirm_clear()
		}
		'remove_favourite' {
			item := object(first)
			a.profile.toggle_favourite(text_value(get(item, 'target')), '', '',
				map[string]json2.Any{}) or {}
			a.fill_panel()
		}
		'rename_favourite' {
			a.rename_dialog(object(first))
		}
		'dialog_close' {
			a.dismiss_dialog()
		}
		'dialog_dismissed' {
			a.dialog_dismissed(first.int())
		}
		'dialog_confirm_clear' {
			a.profile.recents.clear()
			a.profile.write('recents.json', a.profile.recents) or {}
			a.dismiss_dialog()
			a.fill_panel()
		}
		'dialog_rename_save' {
			a.profile.rename_favourite(text_value(first), text_value(a.ui.prop('rename_field',
				'value'))) or {}
			a.dismiss_dialog()
			a.fill_panel()
		}
		'refresh_ytdl' {
			a.start_ytdl(true)
		}
		else {
			log_native('Unhandled UI action ${name}')
		}
	}
}

fn (mut a App) fullscreen() {
	a.ui.set('window', 'full_screen', !a.full_screen())
	a.layout()
}

fn (mut a App) toggle_panel(mode string) {
	a.panel_mode = if a.panel_mode == mode { '' } else { mode }
	if a.panel_mode == 'info' {
		a.info_data.clear()
		for name in ['file-format', 'duration', 'file-size', 'video-codec', 'video-format',
			'video-params/w', 'video-params/h', 'container-fps', 'video-bitrate',
			'video-params/pixelformat', 'video-params/colormatrix', 'video-params/primaries',
			'video-params/gamma', 'track-list'] {
			a.info_data[name] = a.backend.get_property(name)
		}
	}
	a.fill_panel()
	a.activity()
	a.layout()
}

fn (mut a App) change_setting(key string, value json2.Any) {
	a.profile.set_setting(key, value) or {
		a.notify(err.msg())
		return
	}
	for property in properties_for(key, a.profile.settings) {
		a.try_set(property.name, property.value)
	}
	if key == 'seekPreview' { a.sync_thumb() }
	if key == 'uiLanguage' {
		a.t.set_language(text_value(value))
		mut replacement := new_flet(&a.t)
		replacement.conn = a.ui.conn
		replacement.registered = a.ui.registered
		replacement.controls[2] = (a.ui.controls[2] or {
			map[string]json2.Any{}
		}).clone()
		a.ui = replacement
		if a.url_mode {
			a.url_mode = false
			a.toggle_url_mode()
		}
		a.ui.set('page', 'title', a.caption)
		views := get(a.ui.controls[1] or {
			map[string]json2.Any{}
		}, 'views')
		a.ui.pending[1] = [json2.Any([json2.Any(0), 0, 'views', views])]
	}
	a.style_modes()
	a.fill_panel()
	a.update_transport()
	a.layout()
}

fn (mut a App) style_modes() {
	a.ui.set('repeat_button', 'icon', get(a.ui.icons, if a.repeat_mode == 'one' {
		'REPEAT_ONE_ROUNDED'
	} else {
		'REPEAT_ROUNDED'
	}))
	a.ui.set('repeat_button', 'icon_color', if a.repeat_mode != 'off' {
		'#EEEEF0'
	} else {
		'#92929C'
	})
	a.ui.set('repeat_button', 'tooltip', a.t.tr('panel.repeat.' + a.repeat_mode))
	a.ui.set('shuffle_button', 'icon_color', if a.shuffle { '#EEEEF0' } else { '#92929C' })
	a.ui.set('shuffle_button', 'tooltip', a.t.tr(if a.shuffle {
		'panel.shuffle.on'
	} else {
		'panel.shuffle.off'
	}))
}

fn (mut a App) keyboard(event map[string]json2.Any) {
	if a.dialog_open { return }
	key := text_value(get(event, 'key')).to_upper()
	if key == 'F9' {
		a.capture_snapshot()
		return
	}
	if truth(get(event, 'ctrl')) && key == 'O' {
		a.pick_files('open_files')
		return
	}
	if key in ['F', 'F11'] {
		a.fullscreen()
		return
	}
	if key == 'ESCAPE' {
		if a.full_screen() { a.fullscreen() }
		return
	}
	if !a.has_media { return }
	match key {
		' ', 'SPACE', 'K' {
			a.command([json2.Any('cycle'), 'pause'])
			return
		}
		'I' {
			a.toggle_panel('info')
			return
		}
		'ARROW LEFT', 'ARROW RIGHT' {
			forward := key.ends_with('RIGHT')
			now := time.now().unix_milli()
			held := now - a.last_arrow_at < 200
			a.last_arrow_at = now
			if !held || a.arrow_mode == '' { a.arrow_mode = if truth(get(a.properties, 'pause')) {
					'step'
				} else {
					'seek'
				}
			 }
			if a.arrow_mode == 'step' {
				if !held || now - a.last_step >= 25 {
					a.last_step = now
					a.stepping_until = now + 200
					a.properties['pause'] = true
					a.command([
						json2.Any(if forward { 'frame-step' } else { 'frame-back-step' }),
					])
				}
			} else {
				a.command([json2.Any('seek'), if forward { 5 } else { -5 }, 'relative'])
			}
		}
		'ARROW UP', 'ARROW DOWN' {
			a.try_set('volume', clamp(number(get(a.properties, 'volume')) +
				if key.ends_with('UP') { 5 } else { -5 }, 0, 150))
		}
		'M' {
			a.command([json2.Any('cycle'), 'mute'])
		}
		'.', '>' {
			a.advance(1, false)
		}
		',', '<' {
			a.advance(-1, false)
		}
		else {
			return
		}
	}

	a.activity()
}

fn (mut a App) set_zoom(value f64) {
	a.zoom = if math.abs(value) < 0.01 { 0.0 } else { value }
	if a.zoom == 0 {
		a.pan_x = 0
		a.pan_y = 0
		a.try_set('video-pan-x', 0.0)
		a.try_set('video-pan-y', 0.0)
	}
	a.try_set('video-zoom', a.zoom)
}

fn (mut a App) video_wheel(event map[string]json2.Any) {
	mut scroll := object(get(event, 'scroll_delta'))
	if scroll.len == 0 { scroll = object(get(event, 'sd')).clone() }
	delta := number(get(scroll, 'y'))
	if delta == 0 { return }
	up := delta < 0
	if C.lv_key(0x11) != 0 {
		a.set_zoom(clamp(a.zoom + if up { 0.1 } else { -0.1 }, -2, 3))
		a.show_osd('zoom', int(math.round_to_even(math.pow(2, a.zoom) * 100)))
	} else {
		volume := int(math.round_to_even(clamp(number(get(a.properties, 'volume')) +
			if up { 5 } else { -5 }, 0, 150)))
		a.properties['volume'] = volume
		a.try_set('volume', volume)
		if !a.controls_shown() {
			a.show_osd('volume', volume)
		} else {
			a.update_transport()
		}
	}
}

fn pointer_position(event map[string]json2.Any) map[string]json2.Any {
	point := object(get(event, 'global_position'))
	return if point.len > 0 { point } else { object(get(event, 'g')) }
}

fn (mut a App) show_osd(kind string, value int) {
	volume := kind == 'volume'
	a.ui.set('osd', 'visible', true)
	a.ui.set('osd', 'width', if volume { 218 } else { 94 })
	a.ui.set('osd_bar', 'visible', volume)
	a.ui.set('osd_icon', 'visible', volume)
	a.ui.set('osd_number', 'width', if volume { json2.Any(30) } else { json2.Any(json2.Null{}) })
	a.ui.set('osd_fill', 'width', 120.0 * math.min(100.0, f64(value)) / 100)
	a.ui.set('osd_icon', 'icon', get(a.ui.icons, if value == 0 {
		'VOLUME_OFF_ROUNDED'
	} else {
		'VOLUME_UP_ROUNDED'
	}))
	a.ui.set('osd_text', 'value', if volume { '${value}' } else { '${value}%' })
	a.osd_until = time.now().unix_milli() + 1000
	a.layout()
}

fn (mut a App) pick_files(kind string) {
	a.dialog_open = true
	a.layout()
	a.ui.flush() or {}
	mut extensions := video_extensions.clone()
	extensions << 'm3u'
	if kind == 'add_audio' { extensions = audio_extensions.clone() }
	if kind == 'add_subtitle' { extensions = subtitle_extensions.clone() }
	paths := open_dialog(a.surface.parent, kind in ['open_folder', 'browse_screenshot_dir'], kind in [
		'open_files',
		'add_files',
	], extensions)
	a.dialog_open = false
	a.layout()
	if paths.len == 0 { return }
	match kind {
		'add_audio', 'add_subtitle' {
			audio := kind == 'add_audio'
			a.command([json2.Any(if audio { 'audio-add' } else { 'sub-add' }), paths[0], 'select'])
			if audio {
				a.profile.save_audio(a.resume_target, {
					'type': json2.Any('external')
					'path': paths[0]
				}) or {}
			} else {
				a.profile.save_subtitle(a.resume_target, {
					'type': json2.Any('external')
					'path': paths[0]
				}) or {}
			}
		}
		'add_files' {
			a.queue << paths.map(Entry{ path: it })
			if a.index < 0 { a.play_index(0) }
			a.fill_panel()
		}
		'browse_screenshot_dir' {
			a.change_setting('screenshotDir', paths[0])
		}
		else {
			a.open_paths(paths)
		}
	}
}

fn (mut a App) toggle_url_mode() {
	a.url_mode = !a.url_mode
	if a.url_mode {
		controls := a.ui.instantiate('url_home', &a.t, a.profile.settings)
		if controls.len > 0 {
			content := object(a.ui.prop('home', 'content'))
			a.ui.set_id(get(content, '_i').int(), 'content', controls[0])
		}
	} else {
		template := new_flet(&a.t)
		for id, props in template.controls {
			if id >= 19 && id < 29 { a.ui.controls[id] = props.clone() }
		}
		for event, handler in template.events {
			if event.all_before(':').int() >= 19 && event.all_before(':').int() <= 30 {
				a.ui.events[event] = handler
			}
		}
		a.ui.set_id(29, 'content', a.ui.tree(28))
	}
	a.ui.prune()
}

fn (mut a App) screenshot() {
	os.mkdir_all(screenshot_dir(a.profile.settings)) or {
		a.notify(err.msg())
		return
	}
	a.try_set('screenshot-template', screenshot_template(text_value(get(a.properties, 'filename')), number(get(a.properties,
		'time-pos'))))
	mut args := [json2.Any('screenshot')]
	if !truth(get(a.profile.settings, 'screenshotSubs')) { args << json2.Any('video') }
	a.backend.command(args) or {
		a.notify(err.msg())
		return
	}
	a.notify(a.t.tr('toast.screenshotSaved'))
}

fn (mut a App) select_track(audio bool, id json2.Any) {
	a.try_set(if audio { 'aid' } else { 'sid' }, id)
	mut selection := {
		'type': json2.Any('embedded')
		'id':   id
	}
	if text_value(id) == 'no' {
		selection = {
			'type': json2.Any('none')
		}
	} else {
		for item in list_value(get(a.properties, 'track-list')) {
			track := object(item)
			if get(track, 'id') == id && text_value(get(track, 'type')) == if audio {
				'audio'
			} else {
				'sub'
			} && truth(get(track, 'external')) {
				selection = {
					'type': json2.Any('external')
					'path': get(track, 'external-filename')
				}
				break
			}
		}
	}
	if audio {
		a.profile.save_audio(a.resume_target, selection) or {}
	} else {
		a.profile.save_subtitle(a.resume_target, selection) or {}
	}
}
