module main

import math
import x.json2

fn padding(horizontal f64, vertical f64) json2.Any {
	return {
		'left':   json2.Any(horizontal)
		'right':  horizontal
		'top':    vertical
		'bottom': vertical
	}
}

fn (mut a App) text(label string, size f64, color string) json2.Any {
	return a.ui.create('Text', {
		'value':     json2.Any(label)
		'size':      size
		'color':     color
		'max_lines': 2
		'overflow':  'ellipsis'
	})
}

fn (mut a App) row(controls []json2.Any) json2.Any {
	return a.ui.create('Row', {
		'controls': json2.Any(controls)
		'spacing':  4
	})
}

fn (mut a App) wrap_row(controls []json2.Any) json2.Any {
	return a.ui.create('Row', {
		'controls':    json2.Any(controls)
		'spacing':     4
		'run_spacing': 6
		'wrap':        true
	})
}

fn (mut a App) column(controls []json2.Any) json2.Any {
	return a.ui.create('Column', {
		'controls': json2.Any(controls)
		'spacing':  4
		'tight':    true
	})
}

fn (mut a App) section(label string) json2.Any {
	return a.ui.create('Container', {
		'content': a.text(label, 11, '#92929C')
		'padding': padding(0, 9)
	})
}

fn (mut a App) button(label string, action string, args []json2.Any) json2.Any {
	control := a.ui.create('TextButton', {
		'content': json2.Any(label)
	})
	a.ui.bind(control, 'click', action, args)
	return control
}

fn (mut a App) icon_button(icon string, label string, action string, args []json2.Any) json2.Any {
	control := a.ui.create('IconButton', {
		'icon':       get(a.ui.icons, icon)
		'tooltip':    label
		'icon_size':  17
		'icon_color': '#92929C'
	})
	a.ui.bind(control, 'click', action, args)
	return control
}

fn (mut a App) item(label string, subtitle string, action string, args []json2.Any, active bool, trailing json2.Any) json2.Any {
	return a.item_leading(label, subtitle, action, args, active, json2.Any(json2.Null{}), trailing)
}

fn (mut a App) item_leading(label string, subtitle string, action string, args []json2.Any, active bool, leading json2.Any, trailing json2.Any) json2.Any {
	mut labels := [a.text(label, 13, '#EEEEF0')]
	if subtitle != '' { labels << a.text(subtitle, 11, '#92929C') }
	text := a.ui.create('Column', {
		'controls': json2.Any(labels)
		'spacing':  1
		'expand':   true
	})
	mut row := []json2.Any{}
	if leading !is json2.Null { row << leading }
	row << text
	if trailing !is json2.Null { row << trailing }
	control := a.ui.create('Container', {
		'content':       a.row(row)
		'bgcolor':       if active { '#3A3A42' } else { '#242429' }
		'border_radius': 10
		'padding':       padding(8, 7)
		'ink':           true
	})
	a.ui.bind(control, 'click', action, args)
	return control
}

fn (mut a App) icon(name string, size f64, color string) json2.Any {
	return a.ui.create('Icon', {
		'icon':  get(a.ui.icons, name)
		'size':  size
		'color': color
	})
}

fn (mut a App) menu_action(label string, action string, args []json2.Any, icon string, disabled bool, checked bool) json2.Any {
	mut parts := [a.icon(icon, 18, if disabled { '#6E6E79' } else { '#92929C' }),
		a.ui.create('Text', {
			'value':  json2.Any(label)
			'size':   13
			'color':  if disabled { '#6E6E79' } else { '#EEEEF0' }
			'expand': true
		})]
	if checked { parts << a.icon('CHECK_ROUNDED', 16, '#EEEEF0') }
	ink := !disabled
	control := a.ui.create('Container', {
		'content':       a.ui.create('Row', {
			'controls': json2.Any(parts)
			'spacing':  12
		})
		'padding':       padding(8, 8)
		'border_radius': 10
		'ink':           ink
	})
	if !disabled { a.ui.bind(control, 'click', action, args) }
	return control
}

fn (mut a App) panel_header(title string) {
	a.ui.set('panel_header', 'controls', [
		a.ui.create('Text', {
			'value':  json2.Any(title)
			'size':   17
			'color':  '#EEEEF0'
			'expand': true
		}),
		a.icon_button('KEYBOARD_DOUBLE_ARROW_RIGHT_ROUNDED', a.t.tr('common.collapse'),
			'toggle_panel', [json2.Any('')]),
	])
}

fn (mut a App) tabs(choices map[string]string, current string, action string) json2.Any {
	mut buttons := []json2.Any{}
	for value, label in choices {
		control := a.ui.create('Container', {
			'content':       a.text(label, 13, if current == value { '#EEEEF0' } else { '#92929C' })
			'bgcolor':       if current == value { '#3A3A42' } else { '#242429' }
			'padding':       padding(9, 6)
			'border_radius': 8
		})
		a.ui.bind(control, 'click', action, [json2.Any(value)])
		buttons << control
	}
	return a.ui.create('Row', {
		'controls':    json2.Any(buttons)
		'spacing':     2
		'run_spacing': 2
		'wrap':        true
		'expand':      true
	})
}

fn (mut a App) player_tabs() {
	mut choices := {
		'tracks':   a.t.tr('panel.tab.audioSub')
		'playlist': a.t.tr(if a.source_type == 'iptv' {
			'panel.tab.channels'
		} else {
			'panel.tab.playlist'
		})
	}
	if list_value(get(a.properties, 'chapter-list')).len > 0 {
		choices['chapters'] = a.t.tr('panel.tab.chapters')
	}
	a.ui.set('panel_header', 'controls', [a.tabs(choices, a.panel_mode, 'show_panel'),
		a.icon_button('KEYBOARD_DOUBLE_ARROW_RIGHT_ROUNDED', a.t.tr('common.collapse'),
			'toggle_panel', [json2.Any('')])])
}

fn (mut a App) fill_panel() {
	a.ui.set('panel_header', 'controls', []json2.Any{})
	mut body := []json2.Any{}
	match a.panel_mode {
		'settings' {
			name := a.settings_tab +
				if a.settings_tab == 'playback' && truth(get(a.profile.settings, 'useCookies')) { ':cookies' } else { '' }
			controls := a.ui.instantiate(name, &a.t, a.profile.settings)
			if controls.len == 2 {
				header := (a.ui.controls[get(object(controls[0]), '_i').int()] or {
					map[string]json2.Any{}
				}).clone()
				content := (a.ui.controls[get(object(controls[1]), '_i').int()] or {
					map[string]json2.Any{}
				}).clone()
				a.ui.set('panel_header', 'controls', get(header, 'controls'))
				body = list_value(get(content, 'controls'))
			}
			if a.settings_tab == 'general' {
				a.read_ytdl_version()
				for event, handler in a.ui.events {
					if handler.name == 'refresh_ytdl' {
						a.ui.set_id(event.all_before(':').int(), 'disabled', a.ytdl_working)
					}
				}
				if a.ytdl_version != '' { body << a.text('yt-dlp ' + a.ytdl_version, 11, '#92929C') }
				if a.ytdl_state != 'idle' { body << a.text(a.t.tr({
						'working': 'set.ytdl.working'
						'done':    'set.ytdl.done'
						'error':   'set.ytdl.failed'
					}[a.ytdl_state] or { 'set.ytdl.desc' }), 11, '#92929C') }
			}
		}
		'tracks' {
			a.player_tabs()
			body = a.tracks_panel()
		}
		'playlist' {
			a.player_tabs()
			body = a.queue_panel()
		}
		'chapters' {
			a.player_tabs()
			body = a.chapters_panel()
		}
		'library' {
			body = a.library_panel()
		}
		'menu' {
			a.panel_header(a.window_title())
			body = a.menu_panel()
		}
		'info' {
			a.panel_header(a.t.tr('info.title'))
			body = a.info_panel()
		}
		else {}
	}

	a.ui.set('panel_body', 'controls', body)
	a.ui.prune()
}

fn (a &App) lang_label(raw string) string {
	base := raw.to_lower().replace('_', '-').replace(',', '-').all_before('-').all_before(' ')
	keys := {
		'eng': 'english'
		'en':  'english'
		'chi': 'chinese'
		'zho': 'chinese'
		'zh':  'chinese'
		'jpn': 'japanese'
		'ja':  'japanese'
		'kor': 'korean'
		'ko':  'korean'
		'fre': 'french'
		'fra': 'french'
		'fr':  'french'
		'ger': 'german'
		'deu': 'german'
		'de':  'german'
		'spa': 'spanish'
		'es':  'spanish'
		'ita': 'italian'
		'it':  'italian'
		'rus': 'russian'
		'ru':  'russian'
		'por': 'portuguese'
		'pt':  'portuguese'
	}
	return if key := keys[base] { a.t.tr('opt.lang.' + key) } else { raw }
}

fn label_words(label string) []string {
	mut words := []string{}
	mut start := -1
	for i, b in label.bytes() {
		word := b.is_letter() || b.is_digit() || b == `_` || b >= 128
		if word && start < 0 { start = i }
		if !word && start >= 0 {
			words << label[start..i]
			start = -1
		}
	}
	if start >= 0 { words << label[start..] }
	return words
}

fn looks_like_filename(label string) bool {
	words := label_words(label.to_lower().replace('web-dl', 'webdl'))
	return
		words.any(it in ['480p', '576p', '720p', '1080p', '2160p', 'bluray', 'remux', 'webdl', 'webrip', 'hdtv', 'x264', 'x265', 'hevc', 'avc'])
		|| (label.count('.') >= 3 && !label.contains(' '))
}

fn (a &App) track_label(track map[string]json2.Any, audio bool) string {
	mut label := text_value(get(track, 'title'))
	if looks_like_filename(label) { label = '' }
	language := a.lang_label(text_value(get(track, 'lang')))
	if audio {
		codec := text_value(get(track, 'codec'))
		names := {
			'truehd': 'Dolby TrueHD'
			'eac3':   'Dolby Digital Plus'
			'ac3':    'Dolby Digital'
			'opus':   'Opus'
			'vorbis': 'Vorbis'
		}
		format := names[codec.to_lower()] or {
			if codec.to_lower().starts_with('pcm') { 'PCM' } else { codec.to_upper() }
		}
		channels := number(get(track, 'demux-channel-count'))
		layout := channel_layout(channels)
		parts := [language, format, if layout == '' && channels > 0 {
			'${int(channels)}ch'
		} else {
			layout
		}]
		mut technical := parts.filter(it != '').join(' ')
		if technical != '' && truth(get(track, 'demux-bitrate')) {
			technical += '   ${math.round_to_even(number(get(track, 'demux-bitrate')) / 1000):.0f} kbps'
		}
		if label != '' && technical != '' { return label + ' · ' + technical }
		if technical != '' { return technical }
	} else if language != '' {
		mut descriptors := []string{}
		for token in ['SDH', 'Forced', 'CC'] {
			if token.to_lower() in label_words(label.to_lower()) { descriptors << token }
		}
		mut parts := [language]
		parts << descriptors
		return parts.join(' ')
	} else {
		label = label_words(label.replace_each(['.', ' ', '_', ' ', '-', ' '])).filter(it.to_lower() !in [
			'subrip',
			'srt',
			'sup',
			'pgs',
			'pgssub',
			'vobsub',
			'ass',
			'ssa',
			'webvtt',
			'dvb',
		]).join(' ')
	}
	return if label == '' { a.t.format('panel.trackN', {
			'n': text_value(get(track, 'id'))
		}) } else { label }
}

fn (mut a App) tracks_panel() []json2.Any {
	mut body := []json2.Any{}
	tracks := list_value(get(a.properties, 'track-list'))
	for audio in [true, false] {
		kind := if audio { 'audio' } else { 'sub' }
		filtered := tracks.filter(text_value(get(object(it), 'type')) == kind)
		body << a.section(a.t.tr(if audio { 'panel.sec.audio' } else { 'panel.sec.subtitles' }))
		if !audio { body << a.item(a.t.tr('panel.subNone'), '', 'select_subtitle', [
				json2.Any('no'),
			], !filtered.any(truth(get(object(it), 'selected'))), json2.Null{}) }
		if audio && filtered.len == 0 { body << a.text(a.t.tr('panel.empty.audio'), 12, '#92929C') }
		for record in filtered {
			track := object(record)
			badge := if audio {
				if truth(get(track, 'external')) { 'EXT' } else { '' }
			} else {
				text_value(get(track, 'codec')).to_upper()
			}
			body << a.item(a.track_label(track, audio), '', if audio {
				'select_audio'
			} else {
				'select_subtitle'
			}, [get(track, 'id')], truth(get(track, 'selected')), a.text(badge, 10, '#92929C'))
		}
		body << a.button(a.t.tr(if audio { 'panel.addAudio' } else { 'panel.addSub' }), if audio {
			'add_audio'
		} else {
			'add_subtitle'
		}, []json2.Any{})
	}
	body << a.section(a.t.tr('adjust.label'))
	for name in ['sub-delay', 'sub-pos', 'sub-scale'] {
		key := {
			'sub-delay': 'delay'
			'sub-pos':   'position'
			'sub-scale': 'size'
		}[name] or { '' }
		step := if name == 'sub-delay' {
			0.1
		} else if name == 'sub-pos' {
			1.0
		} else {
			0.05
		}
		body << a.row([a.text(a.t.tr('adjust.' + key), 12, '#92929C'),
			a.button('−', 'command', [json2.Any('add'), name, -step]),
			a.text(text_value(get(a.properties, name)), 12, '#EEEEF0'),
			a.button('+', 'command', [json2.Any('add'), name, step])])
	}
	body << a.button(a.t.tr('adjust.reset'), 'adjust_reset', []json2.Any{})
	return body
}

fn (mut a App) queue_panel() []json2.Any {
	mut body := [
		a.row([
			a.button(a.t.tr('panel.repeat.' + a.repeat_mode), 'cycle_repeat', []json2.Any{}),
			a.button(a.t.tr(if a.shuffle { 'panel.shuffle.on' } else { 'panel.shuffle.off' }),
				'toggle_shuffle', []json2.Any{}),
		]),
	]
	if a.source_type == 'iptv' {
		search := a.ui.create('TextField', {
			'value':         json2.Any(a.channel_query)
			'hint_text':     a.t.tr('panel.searchChannels')
			'dense':         true
			'border_radius': 10
			'autofocus':     a.channel_query != ''
		})
		a.ui.bind(search, 'change', 'channel_search', []json2.Any{})
		body << search
	}
	mut group := '\x00'
	mut shown := 0
	for index, entry in a.queue {
		query := a.channel_query.to_lower().trim_space()
		if a.source_type == 'iptv' && query != '' && !entry.title.to_lower().contains(query) && !entry.group.to_lower().contains(query) { continue
		 }
		if shown >= 1500 { break
		 }
		shown++
		if a.source_type == 'iptv' && entry.group != group {
			group = entry.group
			body << a.section(if group == '' { a.t.tr('panel.ungrouped') } else { group })
		}
		body << a.item(if entry.title == '' { media_name(entry.path) } else { entry.title }, '',
			'play_index', [json2.Any(index)], index == a.index, a.icon_button('CLOSE_ROUNDED',
			a.t.tr('lib.remove'), 'remove_item', [json2.Any(index)]))
	}
	if shown == 0 { body << a.text(a.t.tr(if a.queue.len == 0 {
			'panel.empty.queue'
		} else {
			'panel.noMatches'
		}), 12, '#92929C')
	 }
	body << a.row([a.button(a.t.tr('panel.addFiles'), 'add_files', []json2.Any{}),
		a.button(a.t.tr('menu.home'), 'go_home', []json2.Any{}),
		a.icon_button(if a.profile.is_favourite(a.collection_key()) {
			'STAR_ROUNDED'
		} else {
			'STAR_BORDER_ROUNDED'
		}, a.t.tr('panel.savePlaylist'), 'save_collection', []json2.Any{})])
	return body
}

fn (mut a App) chapters_panel() []json2.Any {
	mut body := []json2.Any{}
	for i, value in list_value(get(a.properties, 'chapter-list')) {
		chapter := object(value)
		label := text_value(get(chapter, 'title'))
		body << a.item(if label == '' { a.t.format('panel.chapterN', {
				'n': (i + 1).str()
			}) } else { label }, '', 'set_property', [json2.Any('chapter'), i], get(a.properties,
			'chapter').int() == i, a.text(clock(number(get(chapter, 'time'))), 11, '#92929C'))
	}
	if body.len == 0 { body << a.text(a.t.tr('panel.empty.chapters'), 12, '#92929C') }
	return body
}

fn (mut a App) library_panel() []json2.Any {
	a.ui.set('panel_header', 'controls', [
		a.tabs({
			'recent':    a.t.tr('lib.recent')
			'saved':     a.t.tr('lib.favourites')
			'playlists': a.t.tr('lib.playlists')
			'live':      a.t.tr('lib.live')
		}, a.library_tab, 'library_tab'),
		a.icon_button('KEYBOARD_DOUBLE_ARROW_RIGHT_ROUNDED', a.t.tr('common.collapse'),
			'toggle_panel', [json2.Any('')]),
	])
	mut body := []json2.Any{}
	if a.library_tab == 'recent' {
		if a.profile.recents.len > 0 {
			body << a.button(a.t.tr('lib.clearRecents'), 'clear_recents', []json2.Any{})
		}
		for value in a.profile.recents {
			entry := object(value)
			target := text_value(get(entry, 'target'))
			trailing := a.row([
				a.icon_button('STAR_BORDER_ROUNDED', a.t.tr('menu.favourite'), 'favourite_recent', [
					json2.Any(target),
				]),
				a.icon_button('CLOSE_ROUNDED', a.t.tr('lib.remove'), 'remove_recent', [
					json2.Any(target),
				]),
			])
			body << a.item(text_value(get(entry, 'name')), target, 'open_target', [
				json2.Any(target),
			], false, trailing)
		}
	} else {
		for value in a.profile.favourites {
			entry := object(value)
			kind := text_value(get(entry, 'kind'))
			if (a.library_tab == 'saved' && kind !in ['file', 'url']) || (a.library_tab == 'playlists' && kind != 'playlist') || (a.library_tab == 'live' && kind != 'list') { continue
			 }
			trailing := a.row([
				a.icon_button('EDIT_OUTLINED', a.t.tr('lib.rename'), 'rename_favourite', [
					value,
				]),
				a.icon_button('CLOSE_ROUNDED', a.t.tr('lib.remove'), 'remove_favourite', [
					value,
				]),
			])
			body << a.item(text_value(get(entry, 'name')), text_value(get(entry, 'target')),
				'open_saved', [value], false, trailing)
		}
	}
	if body.len == 0 { body << a.text(a.t.tr({
			'recent':    'lib.emptyRecent'
			'saved':     'lib.emptyFav'
			'playlists': 'lib.emptyPlaylists'
			'live':      'lib.emptyLive'
		}[a.library_tab] or { 'lib.emptyFav' }), 12, '#92929C') }
	return body
}

fn (mut a App) menu_panel() []json2.Any {
	mut body := []json2.Any{}
	paused := truth(get(a.properties, 'pause'))
	body << a.menu_action(a.t.tr(if paused { 'osc.play' } else { 'osc.pause' }), 'command', [
		json2.Any('cycle'),
		'pause',
	], if paused { 'PLAY_ARROW_ROUNDED' } else { 'PAUSE_ROUNDED' }, false, false)
	body << a.ui.create('Divider', {
		'color':  json2.Any('#393940')
		'height': 8
	})
	body << a.menu_action(a.t.tr('menu.previous'), 'advance', [json2.Any(-1)],
		'SKIP_PREVIOUS_ROUNDED', a.queue.len <= 1, false)
	body << a.menu_action(a.t.tr('menu.next'), 'advance', [json2.Any(1)], 'SKIP_NEXT_ROUNDED',
		a.queue.len <= 1, false)
	body << a.menu_action(a.t.tr('menu.prevChapter'), 'command', [json2.Any('add'), 'chapter',
		-1], 'FIRST_PAGE_ROUNDED', list_value(get(a.properties, 'chapter-list')).len == 0, false)
	body << a.menu_action(a.t.tr('menu.nextChapter'), 'command', [json2.Any('add'), 'chapter',
		1], 'LAST_PAGE_ROUNDED', list_value(get(a.properties, 'chapter-list')).len == 0, false)
	body << a.section(a.t.tr('menu.speed'))
	mut speed := []json2.Any{}
	for value in [0.5, 0.75, 1, 1.25, 1.5, 2] {
		chip := a.ui.create('Chip', {
			'label':    a.text(if value == 1 { a.t.tr('menu.speedNormal') } else { '${value:g}×' },
				12, '#EEEEF0')
			'selected': math.abs(number(get(a.properties, 'speed')) - value) < 0.01
		})
		a.ui.bind(chip, 'select', 'set_speed', [json2.Any(value)])
		speed << chip
	}
	body << a.wrap_row(speed)
	body << a.section(a.t.tr('menu.aspect'))
	mut aspects := []json2.Any{}
	for key, label in {
		'default': a.t.tr('common.default')
		'16:9':    '16:9'
		'4:3':     '4:3'
		'2.35':    '2.35:1'
		'stretch': a.t.tr('menu.aspectStretch')
	} {
		chip := a.ui.create('Chip', {
			'label':    a.text(label, 12, '#EEEEF0')
			'selected': a.aspect == key
		})
		a.ui.bind(chip, 'select', 'set_aspect', [json2.Any(key)])
		aspects << chip
	}
	body << a.wrap_row(aspects)
	loop_a, loop_b := get(a.properties, 'ab-loop-a'), get(a.properties, 'ab-loop-b')
	a_set := loop_a !is string && loop_a !is json2.Null
	b_set := loop_b !is string && loop_b !is json2.Null
	body << a.menu_action(a.t.tr(if !a_set {
		'menu.abStart'
	} else if !b_set {
		'menu.abEnd'
	} else {
		'menu.abClear'
	}), 'command', [json2.Any('ab-loop')], 'REPEAT_ROUNDED', false, a_set && b_set)
	body << a.menu_action(a.t.tr('menu.screenshot'), 'screenshot', []json2.Any{},
		'PHOTO_CAMERA_OUTLINED', false, false)
	body << a.menu_action(a.t.tr('menu.favourite'), 'favourite_current', []json2.Any{},
		'STAR_BORDER_ROUNDED', false, a.profile.is_favourite(a.open_target))
	body << a.menu_action(a.t.tr('info.title'), 'toggle_panel', [json2.Any('info')],
		'INFO_OUTLINE_ROUNDED', false, false)
	body << a.ui.create('Divider', {
		'color':  json2.Any('#393940')
		'height': 8
	})
	body << a.menu_action(a.t.tr('menu.home'), 'go_home', []json2.Any{}, 'HOME_OUTLINED', false,
		false)
	body << a.menu_action(a.t.tr('menu.openFile'), 'open_files', []json2.Any{},
		'FOLDER_OPEN_OUTLINED', false, false)
	body << a.menu_action(a.t.tr('appmenu.openFolder'), 'open_folder', []json2.Any{},
		'DRIVE_FOLDER_UPLOAD_OUTLINED', false, false)
	body << a.menu_action(a.t.tr('menu.openUrl'), 'open_url', []json2.Any{}, 'LINK_ROUNDED', false,
		false)
	body << a.menu_action(a.t.tr('menu.fullscreen'), 'fullscreen', []json2.Any{},
		'FULLSCREEN_ROUNDED', false, a.full_screen())
	return body
}

fn (mut a App) info_panel() []json2.Any {
	mut body := []json2.Any{}
	data := a.info_data.clone()
	if data.len == 0 { return [a.text(a.t.tr('info.noData'), 12, '#92929C')] }
	duration, size := number(get(data, 'duration')), number(get(data, 'file-size'))
	body << a.info_line('info.container', text_value(get(data, 'file-format')))
	if duration > 0 { body << a.info_line('info.duration', duration_text(duration)) }
	if size > 0 { body << a.info_line('info.fileSize', file_size(size)) }
	if duration > 0 && size > 0 {
		body << a.info_line('info.overallBitRate', bitrate(size * 8 / duration))
	}
	width, height := get(data, 'video-params/w').int(), get(data, 'video-params/h').int()
	if width > 0 || height > 0 { body << a.section(a.t.tr('info.video')) }
	codec := text_value(get(data, 'video-codec'))
	body << a.info_line('info.codec', if codec == '' {
		text_value(get(data, 'video-format'))
	} else {
		codec
	})
	if width > 0 && height > 0 { body << a.info_line('info.resolution', '${width} × ${height}') }
	fps := number(get(data, 'container-fps'))
	if fps > 0 {
		body << a.info_line('info.frameRate', '${fps:.3f}'.trim_right('0').trim_right('.') + ' fps')
	}
	if number(get(data, 'video-bitrate')) > 0 {
		body << a.info_line('info.bitRate', bitrate(number(get(data, 'video-bitrate'))))
	}
	pixel := text_value(get(data, 'video-params/pixelformat'))
	if pixel != '' {
		mut depth := '8'
		for i := 0; i + 2 < pixel.len; i++ {
			if pixel[i] == `p` && pixel[i + 1].is_digit() && pixel[i + 2].is_digit() {
				depth = pixel[i + 1..i + 3]
				break
			}
		}
		body << a.info_line('info.bitDepth', depth + '-bit')
	}
	body << a.info_line('info.colorSpace', [
		text_value(get(data, 'video-params/colormatrix')),
		text_value(get(data, 'video-params/primaries')),
	].filter(it != '').join(' / '))
	body << a.info_line('info.hdr', hdr_label(text_value(get(data, 'video-params/gamma'))))
	audio :=
		list_value(get(data, 'track-list')).filter(text_value(get(object(it), 'type')) == 'audio')
	if audio.len > 0 { body << a.section(a.t.tr('info.audio')) }
	for record in audio {
		track := object(record)
		body << a.text(a.track_label(track, true), 12, if truth(get(track, 'selected')) {
			'#EEEEF0'
		} else {
			'#92929C'
		})
	}
	return body.filter(it !is json2.Null)
}

fn (mut a App) info_line(key string, value string) json2.Any {
	if value == '' { return json2.Null{} }
	return a.row([
		a.ui.create('Text', {
			'value': json2.Any(a.t.tr(key))
			'width': 110
			'size':  12
			'color': '#92929C'
		}),
		a.ui.create('Text', {
			'value':      json2.Any(value)
			'size':       12
			'color':      '#EEEEF0'
			'expand':     true
			'selectable': true
		}),
	])
}
