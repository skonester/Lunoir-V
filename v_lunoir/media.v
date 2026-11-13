module main

import os
import time
import rand
import math
import x.json2

fn (mut a App) set_queue(entries []Entry) {
	a.queue = entries.clone()
	a.index = -1
	a.shuffle_history.clear()
	a.channel_query = ''
}

fn (mut a App) open_paths(paths []string) {
	if paths.len == 0 || !a.ready { return }
	if paths.len > 1 && paths.all(!is_url(it) && os.is_file(it)
		&& it.all_after_last('.').to_lower() in video_extensions) {
		a.persist()
		a.open_target = paths[0]
		a.open_kind = 'file'
		a.source_type = 'queue'
		a.playlist_key = ''
		a.source_ua = ''
		a.profile.recent(paths[0], media_name(paths[0]), 'file') or {}
		a.set_queue(paths.map(Entry{ path: it }))
		a.play_index(0)
	} else {
		a.open_target_path(paths[0], '')
	}
}

fn (mut a App) open_target_path(target string, agent string) {
	if !a.ready { return }
	a.persist()
	a.revision++
	a.pending_load = false
	a.pending_playlist = ''
	a.source_ua = agent
	playlist_url := is_playlist_url(target)
	a.open_target = target
	a.open_kind = if is_channel_list(target) || playlist_url { 'list' } else { target_kind(target) }
	a.recent_pending = a.open_kind == 'url'
	a.source_type = 'queue'
	a.playlist_key = ''
	if a.open_kind == 'file' { a.profile.recent(target, media_name(target), 'file') or {} }
	if playlist_url {
		a.pending_playlist = target
		a.notify(a.t.tr('main.loadingPlaylist'))
		a.start_ytdl(false)
		return
	}
	if is_local_queue(target) {
		text := os.read_file(target) or {
			a.notify(a.t.tr('main.playlistFailed'))
			return
		}
		entries := parse_local_m3u(target, text)
		if entries.len == 0 {
			a.notify(a.t.tr('main.playlistFailed'))
			return
		}
		if entries.all(is_http(it.path)) {
			a.load_channels(target)
			return
		}
		a.set_queue(entries)
		a.playlist_key = 'file:' + os.abs_path(target).to_lower()
		a.play_index(a.resume_index())
		return
	}
	if a.open_kind == 'list' {
		a.load_channels(target)
		return
	}
	if os.is_dir(target) {
		mut files := scan_folder(target)
		if files.len == 0 {
			a.notify(a.t.tr('main.noMedia'))
			return
		}
		if files.len > 500 {
			a.notify(a.t.format('main.folderTruncated', {
				'count': files.len.str()
				'max':   '500'
			}))
			files = files[..500].clone()
		}
		a.set_queue(files.map(Entry{ path: it }))
		a.play_index(0)
	} else if is_url(target) || !truth(get(a.profile.settings, 'scanFolderIntoPlaylist')) {
		a.set_queue([Entry{ path: target }])
		a.play_index(0)
	} else {
		mut files := scan_folder(os.dir(target))
		if files.len == 0 || files.len > 500 { files = [target] }
		mut start := 0
		for i, path in files {
			if os.abs_path(path).to_lower() == os.abs_path(target).to_lower() {
				start = i
				break
			}
		}
		a.set_queue(files.map(Entry{ path: it }))
		a.play_index(start)
	}
}

fn (a &App) resume_index() int {
	if truth(get(a.profile.settings, 'resumePlaylistItem')) {
		last := text_value(get(a.profile.playlist_items, a.playlist_key))
		for i, entry in a.queue {
			if entry.path == last { return i }
		}
	}
	return 0
}

fn (mut a App) load_channels(source string) {
	a.notify(a.t.tr('main.loadingPlaylist'))
	spawn channel_worker(a.work, a.revision, source, a.source_ua)
}

fn (mut a App) play_index(requested int) {
	mut index := requested
	for index >= 0 && index < a.queue.len && !is_url(a.queue[index].path)
		&& !os.exists(a.queue[index].path) {
		index++
	}
	if index < 0 || index >= a.queue.len {
		a.notify(a.t.tr('main.noPlayable'))
		return
	}
	if index != requested { a.notify(a.t.tr('main.skippedMissing')) }
	a.persist()
	a.revision++
	a.pending_load = false
	a.index = index
	a.current = a.queue[index].path
	a.resume_target = a.current
	a.ytdl_hls_retry = false
	a.ytdl_http_error = ''
	a.load_failed_at = 0
	// A fallback is scoped to this load. The next item starts at the chosen quality.
	for property in properties_for('streamQuality', a.profile.settings) {
		a.try_set(property.name, property.value)
	}
	for name in ['time-pos', 'duration', 'filename', 'media-title', 'metadata/by-key/uploader',
		'chapter-list', 'track-list', 'ab-loop-a', 'ab-loop-b', 'estimated-frame-number'] {
		a.properties.delete(name)
	}
	a.has_media = true
	a.revealed = true
	a.activity()
	a.layout()
	a.ui.flush() or {}
	a.try_set('user-agent', if a.source_type == 'iptv' { a.source_ua } else { '' })
	a.try_set('force-media-title', if a.source_type == 'iptv' { a.queue[index].title } else { '' })
	if needs_ytdl(a.current) && a.source_type != 'iptv' {
		exe := ytdl_executable(a.profile.directory)
		if !os.is_file(exe) {
			a.pending_load = true
			a.start_ytdl(false)
			return
		}
		a.try_set('script-opts', 'ytdl_hook-ytdl_path=' + exe.replace('\\', '/'))
		if ytdl_stale(exe) { a.start_ytdl(false) }
	}
	a.load_current()
}

fn (mut a App) load_current() {
	a.command([json2.Any('loadfile'), a.current, 'replace'])
	a.try_set('pause', false)
	if a.playlist_key != '' { a.profile.save_playlist_item(a.playlist_key, a.current) or {} }
	a.fill_panel()
	a.update_transport()
	a.layout()
}

fn (mut a App) advance(step int, ended bool) {
	if a.queue.len == 0 { return }
	if ended && a.repeat_mode == 'one' {
		a.command([json2.Any('seek'), 0, 'absolute'])
		a.try_set('pause', false)
		return
	}
	mut index := a.index + step
	if a.shuffle && a.queue.len > 1 {
		if step < 0 {
			if a.shuffle_history.len == 0 { return }
			index = a.shuffle_history.pop()
		} else {
			a.shuffle_history << a.index
			pick := rand.intn(a.queue.len - 1) or { 0 }
			index = if pick >= a.index { pick + 1 } else { pick }
		}
	} else if a.repeat_mode == 'all' {
		index = (index + a.queue.len) % a.queue.len
	}
	if index >= 0 && index < a.queue.len { a.play_index(index) }
}

fn (mut a App) remove_item(index int) {
	if index < 0 || index >= a.queue.len { return }
	was_current := index == a.index
	a.queue.delete(index)
	a.shuffle_history = a.shuffle_history.filter(it != index).map(if it > index {
		it - 1
	} else {
		it
	})
	if index < a.index { a.index-- }
	if a.queue.len == 0 {
		a.go_home()
		return
	}
	if was_current { a.play_index(if index < a.queue.len { index } else { a.queue.len - 1 })
	 }
	a.fill_panel()
}

fn (mut a App) handle_event(event map[string]json2.Any) {
	kind := text_value(get(event, 'event'))
	match kind {
		'property-change' {
			name := text_value(get(event, 'name'))
			data := get(event, 'data')
			if name == 'pause' && data == json2.Any(false)
				&& time.now().unix_milli() < a.stepping_until {
				return
			}
			a.properties[name] = data
			if name == 'eof-reached' && truth(data) { a.advance(1, true) }
			if name in ['track-list', 'aid', 'sid', 'chapter-list', 'chapter', 'ab-loop-a', 'ab-loop-b', 'speed']
				&& a.panel_mode in ['tracks', 'chapters', 'menu'] {
				a.fill_panel()
			}
			if name == 'media-title' && a.index >= 0 && a.index < a.queue.len && is_url(a.current)
				&& a.source_type != 'iptv' {
				title := text_value(data)
				if title != '' && title != media_name(a.current) {
					a.queue[a.index] = Entry{
						path:  a.current
						title: title
						group: a.queue[a.index].group
					}
					if a.open_kind == 'url' { a.profile.rename_recent(a.open_target, title) or {} }
					if a.panel_mode == 'playlist' { a.fill_panel() }
				}
			}
			if name == 'seekable' && truth(data) && a.recent_pending && a.open_kind == 'url' {
				entry_title := if a.index >= 0 && a.index < a.queue.len
					&& a.queue[a.index].title != '' {
					a.queue[a.index].title
				} else {
					a.open_target
				}
				a.profile.recent(a.open_target, entry_title, 'url') or {}
				a.recent_pending = false
			}
			if name in ['video-params/aspect', 'video-params/w', 'video-params/h'] {
				a.apply_aspect()
			}
			if name == 'path' { a.sync_thumb() }
			a.update_transport()
		}
		'file-loaded' {
			a.on_file_loaded()
		}
		'playback-restart' {
			if a.pending_resume != '' {
				a.notify(a.t.format('main.resumed', {
					'time': a.pending_resume
				}))
				a.pending_resume = ''
			}
		}
		'start-file' {
			a.ytdl_error = ''
			a.ytdl_http_error = ''
			a.load_failed_at = 0
		}
		'log-message' {
			prefix := text_value(get(event, 'prefix'))
			text := text_value(get(event, 'text')).trim_space()
			log_native('mpv [${prefix}] ' + text)
			if text.to_lower().contains('http') && text.contains('403') {
				a.ytdl_http_error = 'HTTP 403 Forbidden'
			}
			if prefix == 'ytdl_hook' {
				reason := ytdl_error_text(text)
				if reason != '' { a.ytdl_error = reason }
			}
		}
		'end-file' {
			log_native('mpv end-file ' + json_encode(event) + '; HTTP: ' + a.ytdl_http_error)
			if text_value(get(event, 'reason')) == 'error' {
				a.load_failed_at = time.now().unix_milli() + 150
			}
		}
		'shutdown' {
			a.closed = true
		}
		else {}
	}
}

fn (mut a App) finish_failed_load() {
	if a.retry_youtube_hls() { return }
	a.notify(if a.ytdl_error != '' {
		a.ytdl_error
	} else if a.ytdl_http_error != '' {
		a.ytdl_http_error
	} else {
		a.t.tr('main.loadFailed')
	})
	if ytdl_outdated(a.ytdl_error) { a.start_ytdl(true) }
	a.ytdl_error = ''
}

fn (mut a App) on_file_loaded() {
	a.zoom = 0
	a.pan_x = 0
	a.pan_y = 0
	a.pan_origin.clear()
	for name in ['video-zoom', 'video-pan-x', 'video-pan-y'] {
		a.try_set(name, 0.0)
	}
	audio := object(get(a.profile.audio, a.resume_target))
	match text_value(get(audio, 'type')) {
		'embedded' {
			a.try_set('aid', get(audio, 'id'))
		}
		'external' {
			path := text_value(get(audio, 'path'))
			if os.exists(path) { a.command([json2.Any('audio-add'), path, 'select']) }
		}
		else {}
	}

	for path in a.profile.subtitle_files(a.resume_target) {
		if !is_url(path) && !os.exists(path) { continue
		 }
		tracks := list_value(a.backend.get_property('track-list'))
		if !tracks.any(text_value(get(object(it), 'external-filename')) == path && text_value(get(object(it), 'type')) == 'sub') { a.command([
				json2.Any('sub-add'),
				path,
				'auto',
			]) }
	}
	saved := object(get(a.profile.subtitles, a.resume_target))
	tracks := list_value(a.backend.get_property('track-list'))
	match text_value(get(saved, 'type')) {
		'none' {
			a.try_set('sid', 'no')
		}
		'embedded' {
			if tracks.any(text_value(get(object(it), 'type')) == 'sub'
				&& !truth(get(object(it), 'external')) && get(object(it), 'id') == get(saved, 'id'))
			{
				a.try_set('sid', get(saved, 'id'))
			}
		}
		'external' {
			for tr in tracks {
				track := object(tr)
				if text_value(get(track, 'external-filename')) == text_value(get(saved, 'path'))
					&& text_value(get(track, 'type')) == 'sub' {
					a.try_set('sid', get(track, 'id'))
					break
				}
			}
		}
		else {}
	}

	if truth(get(a.profile.settings, 'resumePlayback')) && a.can_resume() {
		position := number(get(a.profile.positions, a.resume_target))
		if position > 5 {
			a.command([json2.Any('seek'), position, 'absolute'])
			a.pending_resume = clock(position)
		}
	} else if !a.can_resume() {
		a.profile.clear_position(a.resume_target) or {}
	}
}

fn (mut a App) apply_aspect() {
	target := {
		'16:9': 16.0 / 9
		'4:3':  4.0 / 3
		'2.35': 2.35
	}[a.aspect] or { 0.0 }
	source := number(get(a.properties, 'video-params/aspect'))
	width, height := number(get(a.properties, 'video-params/w')), number(get(a.properties,
		'video-params/h'))
	mut crop := ''
	if target > 0 && source > 0 && width > 0 && height > 0 {
		w := if target < source { math.round_to_even(width * target / source) } else { width }
		h := if target > source { math.round_to_even(height * source / target) } else { height }
		crop = '${int(w)}x${int(h)}'
	}
	keep := a.aspect != 'stretch'
	if !a.aspect_initialized || a.applied_aspect != crop || a.applied_keepaspect != keep {
		a.aspect_initialized = true
		a.applied_aspect = crop
		a.applied_keepaspect = keep
		a.try_set('keepaspect', keep)
		a.try_set('video-crop', crop)
	}
}

fn (mut a App) go_home() {
	a.persist()
	a.revision++
	a.pending_load = false
	a.pending_playlist = ''
	a.load_failed_at = 0
	a.command([json2.Any('stop')])
	a.has_media = false
	a.current = ''
	a.resume_target = ''
	a.index = -1
	a.panel_mode = ''
	a.set_queue([]Entry{})
	a.fill_panel()
	a.update_transport()
	a.layout()
}
