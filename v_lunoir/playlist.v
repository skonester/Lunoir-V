module main

import os
import net.urllib

const video_extensions = ['mp4', 'mkv', 'avi', 'mov', 'flv', 'wmv', 'webm', 'm4v', 'ts', 'mpg',
	'mpeg', 'm2ts', 'rmvb', '3gp', 'ogv', 'mp3', 'flac', 'aac', 'wav', 'm4a', 'ogg', 'opus']
const audio_extensions = ['aac', 'ac3', 'dts', 'eac3', 'flac', 'm4a', 'mka', 'mp2', 'mp3', 'ogg',
	'opus', 'thd', 'truehd', 'wav', 'w64', 'wv']
const subtitle_extensions = ['srt', 'ass', 'ssa', 'vtt', 'sub', 'sup', 'idx', 'lrc']
const iptv_user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'

struct Entry {
	path  string
	title string
	group string
}

fn is_url(target string) bool {
	colon := target.index('://') or { return false }
	if colon == 0 || !target[0].is_letter() { return false }
	for c in target[..colon].bytes() {
		if !c.is_letter() && !c.is_digit() && c !in [`+`, `-`, `.`] { return false }
	}
	return true
}

fn is_http(target string) bool {
	lower := target.to_lower()
	return lower.starts_with('http://') || lower.starts_with('https://')
}

fn media_name(target string) string {
	if is_url(target) {
		tail := target.trim_right('/').all_after_last('/').all_before('?')
		name := urllib.path_unescape(tail) or { tail }
		return if name == '' { target } else { name }
	}
	return os.file_name(target)
}

fn natural_compare(a string, b string) int {
	x, y := a.to_lower().replace('ß', 'ss'), b.to_lower().replace('ß', 'ss')
	mut i, mut j := 0, 0
	for i < x.len && j < y.len {
		if x[i].is_digit() && y[j].is_digit() {
			mut ei, mut ej := i, j
			for ei < x.len && x[ei].is_digit() {
				ei++
			}
			for ej < y.len && y[ej].is_digit() {
				ej++
			}
			nx, ny := x[i..ei].trim_left('0'), y[j..ej].trim_left('0')
			if nx.len != ny.len { return if nx.len < ny.len { -1 } else { 1 }
			 }
			if nx != ny { return if nx < ny { -1 } else { 1 }
			 }
			i, j = ei, ej
		} else {
			if x[i] != y[j] { return if x[i] < y[j] { -1 } else { 1 }
			 }
			i++
			j++
		}
	}
	return if i == x.len && j == y.len {
		0
	} else if i == x.len {
		-1
	} else {
		1
	}
}

fn scan_folder(directory string) []string {
	mut names := (os.ls(directory) or { return []string{} }).filter(
		os.is_file(os.join_path(directory, it)) && it.contains('.')
		&& it.all_after_last('.').to_lower() in video_extensions)
	names.sort_with_compare(fn (a &string, b &string) int {
		return natural_compare(*a, *b)
	})
	return names.map(os.join_path(directory, it))
}

fn extinf_title(line string) string {
	quote := line.last_index('"') or { 0 }
	comma := line[quote..].index(',') or { return '' }
	return line[quote + comma + 1..].trim_space()
}

fn file_url_path(target string) string {
	rest := target[7..]
	decoded := urllib.path_unescape(rest) or { rest }
	mut path := decoded.replace('/', '\\')
	if !rest.starts_with('/') { return '\\\\' + path.trim_left('\\') }
	if path.len >= 3 && path[0] == `\\` && path[2] == `:` { path = path[1..] }
	return path
}

fn parse_local_m3u(source string, text string) []Entry {
	base := os.dir(os.abs_path(source))
	mut entries := []Entry{}
	mut title := ''
	for raw in text.split_into_lines() {
		line := raw.trim_space().trim_left('\ufeff')
		if line.to_upper().starts_with('#EXTINF') {
			title = extinf_title(line)
			continue
		}
		if line == '' || line.starts_with('#') { continue
		 }
		mut target := line
		if target.len >= 2 && target[0] == target[target.len - 1] && target[0] in [`"`, `'`] {
			target = target[1..target.len - 1]
		}
		if target.to_lower().starts_with('file://') {
			target = file_url_path(target)
		} else if !is_url(target) && !os.is_abs_path(target) {
			target = os.abs_path(os.join_path(base, target))
		} else if !is_url(target) {
			target = os.abs_path(target)
		}
		entries << Entry{
			path:  target
			title: if title != '' { title } else { media_name(target) }
		}
		title = ''
	}
	return entries
}

fn parse_channel_list(text string) []Entry {
	lines := text.split_into_lines()
	mut channels := []Entry{}
	m3u := (lines.len > 0 && lines[0].trim_left('\ufeff').to_upper().starts_with('#EXTM3U'))
		|| lines.any(it.trim_space().to_upper().starts_with('#EXTINF'))
	mut title, mut group := '', ''
	for raw in lines {
		line := raw.trim_space()
		if m3u {
			if line.to_upper().starts_with('#EXTINF') {
				title = extinf_title(line)
				group = ''
				if at := line.to_lower().index('group-title="') {
					group = line[at + 13..].all_before('"').trim_space()
				}
			} else if line != '' && !line.starts_with('#') {
				if is_http(line) { channels << Entry{
						path:  line
						title: if title == '' { line } else { title }
						group: group
					}
				 }
				title, group = '', ''
			}
		} else {
			left, right := line.split_once(',') or { continue }
			if right.trim_space() == '#genre#' {
				group = left.trim_space()
			} else if is_http(right.trim_space()) {
				channels << Entry{
					path:  right.trim_space()
					title: if left.trim_space() == '' {
						right.trim_space()
					} else {
						left.trim_space()
					}
					group: group
				}
			}
		}
	}
	return channels
}

fn is_local_queue(target string) bool {
	return !is_url(target) && target.to_lower().ends_with('.m3u')
}

fn is_channel_list(target string) bool {
	base := target.all_before('?').all_before('#').to_lower()
	return base.ends_with('.m3u') || base.ends_with('.txt')
}

fn read_source(source string, user_agent string) !string {
	if is_http(source) {
		response := http_fetch(source, if user_agent == '' { iptv_user_agent } else { user_agent })!
		return decode_source_text(response.body, response.content_type)
	}
	return os.read_file(source)!
}
