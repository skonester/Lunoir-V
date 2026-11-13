module py_flet_lunoir

import os
import regex

// TODO(py2v): no V equivalent for import urllib.parse, urllib.request
// Provide one in python_to_v_import (types.v) or port the module.

// TODO(py2v): 1 except handler(s) need a V Result equivalent:
//   except OSError (1 stmt)

const video_ext = ['mp4', 'mkv', 'avi', 'mov', 'flv', 'wmv', 'webm', 'm4v', 'ts', 'mpg', 'mpeg', 'm2ts', 'rmvb', '3gp', 'ogv', 'mp3', 'flac', 'aac', 'wav', 'm4a', 'ogg', 'opus']
const open_ext = video_ext + ['m3u']
const audio_ext = ['aac', 'ac3', 'dts', 'eac3', 'flac', 'm4a', 'mka', 'mp2', 'mp3', 'ogg', 'opus', 'thd', 'truehd', 'wav', 'w64', 'wv']
const subtitle_ext = ['srt', 'ass', 'ssa', 'vtt', 'sub', 'sup', 'idx', 'lrc']
const max_folder_scan = 500
const iptv_ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'

pub struct Entry {
pub mut:
	path string
	title string = ''
	group string = ''
}

pub fn is_url(target string) bool {
	return ((regex.regex_opt('^[a-z][a-z0-9+.-]*://') or { panic(err) }).match_string(target) != 0)
}

pub fn is_http(target string) bool {
	return ((regex.regex_opt('^https?://') or { panic(err) }).match_string(target) != 0)
}

pub fn media_name(target string) string {
	if is_url(target) {
		tail := urllib.parse.unquote(target.trim_right('/').rsplit('/', 1)[target.trim_right('/').rsplit('/', 1).len - 1].split('?')[0])
		return tail || target
	}
	return target.name
}

pub fn natural_(name string) Any {
	return (regex.regex_opt('(\\d+)') or { panic(err) }).split(name).filter(it).map(if (it.len > 0 && it.bytes().all(fn (c u8) bool { return c.is_digit() })) { [0, int(it), ''] } else { [1, 0, it.casefold()] })
}

pub fn scan_folder(directory string) []string {
	names := os.scandir(directory).filter(it.is_file() && (it.name.rsplit('.', 1)[it.name.rsplit('.', 1).len - 1].to_lower() in video_ext) && ('.' in it.name)).map(it.name)
	// except handlers are not translated: see the TODO(py2v) note above
	//   except OSError: 1 statement(s) need an `or { ... }` equivalent
	return (fn (a []Any) []Any { mut b := a.clone(); b.sort(); return b }(names)).map(directory.join(os.path))
}

pub fn extinf_title_(line string) string {
	quote := line.last_index('\"') or { -1 }
	comma := line.index(',') or { -1 }
	return if comma >= 0 { line[comma + 1..].trim_space() } else { '' }
}

pub fn parse_local_m3u(source string, text ?string) []Entry {
	if text == none {
		text = os.read_file(source) or { '' }
	}
	base := os.abs_path(source).parent
	entries, title = [], ''
	for raw in text.split_into_lines() {
		line := raw.trim_space().trim_left('﻿')
		if (regex.regex_opt('^#EXTINF') or { panic(err) }).match_string(line) {
			title = extinf_title_(line)
			continue
		}
		if !line || line.starts_with('#') {
			continue
		}
		mut target := line
		if target.len >= 2 && target[0] == target[target.len - 1] && '\"\''.contains(target[0]) {
			target = target[1..target.len - 1]
		}
		if (regex.regex_opt('^file://') or { panic(err) }).match_string(target) {
			parsed := urllib.parse.urlparse(target)
			target = urllib.request.url2pathname(urllib.parse.unquote(parsed.netloc + parsed.path))
			if parsed.netloc {
				target = '\\\\' + target.trim_left('\\')
			}
		} else if !is_url(target) {
			target = (os.abs_path((base / target)))
		}
		entries << Entry{
			path: target
			title: title || media_name(target)
		}
		title = ''
	}
	return entries
}

pub fn parse_channel_list(text string) []Entry {
	lines := text.split_into_lines()
	mut channels := []Entry{}
	m3u := (lines && (regex.regex_opt('^﻿?#EXTM3U') or { panic(err) }).match_string(lines[0]) != 0) || lines.map((regex.regex_opt('^#EXTINF') or { panic(err) }).match_string(it.trim_space())).any(it)
	if m3u {
		mut pending := none
		for raw in lines {
			mut line := raw.trim_space()
			if (regex.regex_opt('^#EXTINF') or { panic(err) }).match_string(line) {
				mut group := (regex.regex_opt('group-title=\"([^\"]*)\"') or { panic(err) }).find(line)
				pending = [extinf_title_(line), if group { group.group(1).trim_space() } else { '' }]
			} else if line && !line.starts_with('#') {
				if is_http(line) {
					channels << Entry{
						path: line
						title: (pending && pending[0]) || line
						group: (pending && pending[1]) || ''
					}
				}
				pending = none
			}
		}
	} else {
		group = ''
		for raw in lines {
			line = raw.trim_space()
			py2v_unpack1 := line.partition(',')
			mut left := py2v_unpack1[0]
			mut comma := py2v_unpack1[1]
			mut right := py2v_unpack1[2]
			if !comma {
				continue
			}
			left, right = left.trim_space(), right.trim_space()
			if right == '#genre#' {
				group = left
			} else if is_http(right) {
				channels << Entry{
					path: right
					title: left || right
					group: group
				}
			}
		}
	}
	return channels
}

pub fn read_source(source string, user_agent string) string {
	if is_http(source) {
		request := urllib.request.Request(source, map[string]Any{
			'User-Agent': user_agent || iptv_ua,
		})
		if true {
			response := urllib.request.urlopen(request, 20)
			charset := response.headers.get_content_charset() || 'utf-8'
			return response.read().decode(charset, 'replace')
		}
	}
	return os.read_file(source) or { '' }
}

pub fn is_local_queue(target string) bool {
	return !is_url(target) && target.to_lower().ends_with('.m3u')
}

pub fn is_channel_list(target string) bool {
	return ((regex.regex_opt('\\.(m3u|txt)(\\?|#|$)') or { panic(err) }).find(target) != 0)
}
