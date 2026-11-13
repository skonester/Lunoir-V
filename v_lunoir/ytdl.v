module main

import os
import time
import crypto.sha256
import net.urllib
import x.json2

const ytdl_releases = 'https://github.com/yt-dlp/yt-dlp/releases'

fn is_youtube_url(url string) bool {
	parsed := urllib.parse(url) or { return false }
	host := parsed.hostname().to_lower()
	return host == 'youtu.be' || host == 'youtube.com' || host.ends_with('.youtube.com')
}

fn youtube_hls_format(quality string) string {
	cap := if quality in ['2160', '1080', '720', '480'] { '[height<=?${quality}]' } else { '' }
	return 'bestvideo[protocol^=m3u8]${cap}+bestaudio[protocol^=m3u8]/best[protocol^=m3u8]${cap}/best${cap}'
}

fn (mut a App) retry_youtube_hls() bool {
	if a.ytdl_hls_retry || a.ytdl_http_error != 'HTTP 403 Forbidden' || a.source_type == 'iptv'
		|| !is_youtube_url(a.current) {
		return false
	}
	a.ytdl_hls_retry = true
	a.ytdl_http_error = ''
	a.ytdl_error = ''
	a.try_set('ytdl-format',
		youtube_hls_format(text_value(get(a.profile.settings, 'streamQuality'))))
	log_native('YouTube returned HTTP 403; retrying once with HLS audio and video')
	a.load_current()
	return true
}

struct WorkResult {
	kind     string
	revision i64
	data     json2.Any
	error    string
}

fn needs_ytdl(url string) bool {
	if !is_http(url) { return false }
	ext := url.all_before('?').all_before('#').all_after_last('.').to_lower()
	return ext !in video_extensions && ext !in ['m3u8', 'mpd']
}

fn is_playlist_url(url string) bool {
	return is_url(url) && url.to_lower().contains('/playlist?')
}

fn ytdl_playlist_key(url string) string {
	for part in url.all_after('?').split('&') {
		key, value := part.split_once('=') or { continue }
		if key.to_lower() == 'list' { return 'list:' + value }
	}
	return 'list:' + url
}

fn ytdl_error_text(text string) string {
	at := text.to_upper().index('ERROR:') or { return '' }
	mut reason := text[at + 6..].trim_space()
	for tail in ['; please report this issue', 'You might want to use'] {
		if pos := reason.to_lower().index(tail.to_lower()) { reason = reason[..pos].trim_space() }
	}
	runes := reason.runes()
	return if runes.len > 200 { runes[..200].string() } else { reason }
}

fn ytdl_outdated(reason string) bool {
	lower := reason.to_lower()
	return ['outdated', 'out-of-date', 'out of date', 'update yt-dlp', 'update to the latest',
		'nightly'].any(lower.contains(it))
}

fn ytdl_executable(directory string) string {
	return os.join_path(directory, 'yt-dlp', 'yt-dlp.exe')
}

fn ytdl_stale(exe string) bool {
	return !os.is_file(exe) || time.now().unix() - os.file_last_mod_unix(exe) > 14 * 24 * 3600
}

fn ytdl_installed_version(exe string) string {
	return (capture_process([exe, '--version'], 30 * time.second) or { return '' }).trim_space()
}

fn valid_ytdl_tag(tag string) bool {
	parts := tag.split('.')
	if parts.len !in [3, 4] || parts[0].len != 4 || parts[1].len != 2 || parts[2].len != 2 {
		return false
	}
	return parts.all(it.len > 0 && it.bytes().all(it.is_digit()))
}

fn update_ytdl(exe string) !json2.Any {
	return update_ytdl_from(exe, ytdl_releases)
}

fn update_ytdl_from(exe string, releases string) !json2.Any {
	latest := http_fetch(releases + '/latest', 'Lunoir-V')!
	tag := latest.url.trim_right('/').all_after_last('/')
	if !valid_ytdl_tag(tag) { return error('Unexpected yt-dlp release: ${latest.url}') }
	replaced := ytdl_installed_version(exe) != tag
	if replaced {
		checksums := http_fetch('${releases}/download/${tag}/SHA2-256SUMS', 'Lunoir-V')!
		mut expected := ''
		for line in checksums.body.split_into_lines() {
			parts := line.fields()
			if parts.len >= 2 && parts[1].trim_left('*') == 'yt-dlp.exe' {
				expected = parts[0].to_lower()
				break
			}
		}
		if expected.len != 64 { return error('No published checksum for yt-dlp.exe ${tag}') }
		response := http_fetch('${releases}/download/${tag}/yt-dlp.exe', 'Lunoir-V')!
		if sha256.sum(response.body.bytes()).hex() != expected {
			return error('yt-dlp.exe ${tag} does not match its published checksum')
		}
		os.mkdir_all(os.dir(exe))!
		part := exe + '.part'
		defer { os.rm(part) or {} }
		os.write_file(part, response.body)!
		for attempt in 0 .. 8 {
			time.sleep(attempt * 500 * time.millisecond)
			atomic_replace(part, exe) or {
				if attempt == 7 { return err }
				continue
			}
			break
		}
	} else {
		os.utime(exe, time.now().unix(), time.now().unix())!
	}
	return {
		'path':     json2.Any(exe)
		'version':  tag
		'replaced': replaced
	}
}

fn ytdl_worker(results chan WorkResult, exe string) {
	data := update_ytdl(exe) or {
		results <- WorkResult{
			kind:  'ytdl'
			error: err.msg()
		}
		return
	}
	results <- WorkResult{
		kind: 'ytdl'
		data: data
	}
}

fn channel_worker(results chan WorkResult, revision i64, source string, agent string) {
	text := read_source(source, agent) or {
		results <- WorkResult{
			kind:     'channels'
			revision: revision
			error:    err.msg()
		}
		return
	}
	items := parse_channel_list(text).map(json2.Any({
		'path':  json2.Any(it.path)
		'title': it.title
		'group': it.group
	}))
	results <- WorkResult{
		kind:     'channels'
		revision: revision
		data:     items
	}
}

fn playlist_worker(results chan WorkResult, revision i64, exe string, url string) {
	out := capture_process([exe, '--flat-playlist', '--no-warnings', '--encoding', 'utf-8', '--print',
		'%(url)s ||| %(title)s', url], 120 * time.second) or {
		results <- WorkResult{
			kind:     'playlist'
			revision: revision
			error:    err.msg()
		}
		return
	}
	mut items := []json2.Any{}
	for line in out.split_into_lines() {
		link, title := line.split_once(' ||| ') or { continue }
		if is_http(link.trim_space()) { items << json2.Any({
				'path':  json2.Any(link.trim_space())
				'title': title.trim_space()
			}) }
	}
	results <- WorkResult{
		kind:     'playlist'
		revision: revision
		data:     items
	}
}

fn version_worker(results chan WorkResult, exe string) {
	results <- WorkResult{
		kind: 'version'
		data: ytdl_installed_version(exe)
	}
}

fn (mut a App) read_ytdl_version() {
	if a.ytdl_version_known || a.ytdl_version_reading
		|| !os.is_file(ytdl_executable(a.profile.directory)) {
		return
	}
	a.ytdl_version_reading = true
	spawn version_worker(a.work, ytdl_executable(a.profile.directory))
}

fn (mut a App) start_ytdl(force bool) {
	if a.ytdl_working { return }
	exe := ytdl_executable(a.profile.directory)
	if !force && os.is_file(exe) && !ytdl_stale(exe) {
		a.ytdl_version = ytdl_installed_version(exe)
		a.work_result(WorkResult{
			kind: 'ytdl'
			data: {
				'path':     json2.Any(exe)
				'version':  a.ytdl_version
				'replaced': false
			}
		})
		return
	}
	a.ytdl_working = true
	a.ytdl_state = 'working'
	a.notify(a.t.tr('main.fetchingYtdl'))
	a.fill_panel()
	spawn ytdl_worker(a.work, exe)
}

fn (mut a App) work_result(result WorkResult) {
	if result.kind == 'version' {
		a.ytdl_version_reading = false
		a.ytdl_version_known = true
		a.ytdl_version = text_value(result.data)
		a.fill_panel()
		return
	}
	if result.kind == 'ytdl' {
		a.ytdl_working = false
		a.ytdl_state = if result.error == '' { 'done' } else { 'error' }
		data := object(result.data)
		if result.error == '' {
			a.ytdl_version = text_value(get(data, 'version'))
			a.ytdl_version_known = true
			a.try_set('script-opts', 'ytdl_hook-ytdl_path=' +
				text_value(get(data, 'path')).replace('\\', '/'))
			a.notify(
				a.t.tr(if truth(get(data, 'replaced')) { 'main.ytdlUpdated' } else { 'set.ytdl.done' }) +
				' · yt-dlp ' + a.ytdl_version)
		} else {
			log_native(result.error)
			a.notify(a.t.tr('main.ytdlFailed'))
		}
		if a.pending_playlist != '' {
			if result.error == '' {
				spawn playlist_worker(a.work, a.revision, ytdl_executable(a.profile.directory),
					a.pending_playlist)
			} else {
				a.pending_playlist = ''
			}
		} else if a.pending_load {
			a.pending_load = false
			a.load_current()
		}
		a.fill_panel()
		return
	}
	if result.revision != a.revision { return }
	mut entries := []Entry{}
	for item in list_value(result.data) {
		record := object(item)
		entries << Entry{
			path:  text_value(get(record, 'path'))
			title: text_value(get(record, 'title'))
			group: text_value(get(record, 'group'))
		}
	}
	if result.kind == 'playlist' {
		if entries.len == 0 {
			a.notify(a.t.tr('main.playlistFailed'))
			a.pending_playlist = ''
			return
		}
		a.playlist_key = ytdl_playlist_key(a.pending_playlist)
		a.pending_playlist = ''
		a.set_queue(entries)
		a.play_index(a.resume_index())
	} else if result.kind == 'channels' {
		if entries.len < 2 {
			for saved in a.profile.favourites {
				favourite := object(saved)
				if text_value(get(favourite, 'target')) == a.open_target {
					snapshot := list_value(get(favourite, 'channels'))
					if snapshot.len > 0 {
						entries.clear()
						for channel in snapshot {
							item := object(channel)
							entries << Entry{
								path:  text_value(get(item, 'url'))
								title: text_value(get(item, 'name'))
								group: text_value(get(item, 'group'))
							}
						}
					}
					break
				}
			}
		}
		if entries.len < 2 {
			a.set_queue([Entry{ path: a.open_target }])
		} else {
			a.set_queue(entries)
			a.source_type = 'iptv'
			for i, saved in a.profile.favourites {
				mut favourite := object(saved).clone()
				if text_value(get(favourite, 'target')) == a.open_target {
					favourite['channels'] = entries.map(json2.Any({
						'name':  json2.Any(it.title)
						'url':   it.path
						'group': it.group
					}))
					a.profile.favourites[i] = favourite
					a.profile.write('favourites.json', a.profile.favourites) or {}
					break
				}
			}
		}
		a.play_index(0)
	}
}
