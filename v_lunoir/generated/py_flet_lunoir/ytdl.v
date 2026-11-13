module py_flet_lunoir

import crypto
import log
import os
import regex
import time

// TODO(py2v): no V equivalent for import asyncio, urllib.request
// Provide one in python_to_v_import (types.v) or port the module.

// TODO(py2v): no V mapping for subprocess.run
// Each site below is stubbed with a zero value.

// TODO(py2v): 2 except handler(s) need a V Result equivalent:
//   except OSError (1 stmt)
//   except OSError | subprocess.TimeoutExpired (1 stmt)

const releases = 'https://github.com/yt-dlp/yt-dlp/releases'
const stale_seconds = 14 * 24 * 3600
const media_url_ext = regex.regex_opt('\\.(mp4|mkv|webm|m4v|mov|avi|flv|ts|m2ts|mpg|mpeg|m3u8|mpd|mp3|flac|aac|wav|ogg|opus|m4a)(\\?|#|$)') or { panic(err) }
const outdated = regex.regex_opt('out.?of.?date|outdated|update (yt-dlp|to the latest)|nightly') or { panic(err) }
const log = log :=

pub struct Ytdl {
pub mut:
	exe Any
	task ?asyncio.Task
	version ?string
	replaced Any
}

pub fn (mut self Ytdl) init(profile_dir Path) {
	self.exe = profile_dir / 'yt-dlp' / 'yt-dlp.exe'
	self.task = none
	self.version = none
	self.replaced = false
}

pub fn (self Ytdl) stale() bool {
	return time.time() - self.exe.stat().st_mtime > stale_seconds
	// except handlers are not translated: see the TODO(py2v) note above
	//   except OSError: 1 statement(s) need an `or { ... }` equivalent
}

pub fn (mut self Ytdl) update_()  {
	tag := latest_tag()
	self.replaced = installed_version(self.exe) != tag
	if self.replaced {
		download_(tag, self.exe)
	} else {
		os.utime(self.exe)
	}
	self.version = tag
}

pub fn (mut self Ytdl) start_() Task {
	if !self.task || self.task.done() {
		self.task = go self._fetch()
	}
	return self.task
}

pub fn (self Ytdl) downloading() bool {
	return (self.task && !self.task.done() != 0)
}

pub fn needs_ytdl(url string) bool {
	return ((regex.regex_opt('^https?://') or { panic(err) }).match_string(url) != 0) && !media_url_ext.search(url)
}

pub fn is_playlist_url(url string) bool {
	return is_url(url) && ((regex.regex_opt('/playlist\\?') or { panic(err) }).find(url) != 0)
}

pub fn playlist_key(url string) string {
	@match := (regex.regex_opt('[?&]list=([^&]+)') or { panic(err) }).find(url)
	return 'list:' + (if @match { @match.group(1) } else { url })
}

pub fn error_text(text string) string {
	@match := (regex.regex_opt('\\bERROR:\\s*(.+)$') or { panic(err) }).find(text.trim_space())
	if !@match {
		return ''
	}
	mut reason := (regex.regex_opt('\\s*;\\s*please report this issue.*') or { panic(err) }).replace(@match.group(1), '')
	reason = (regex.regex_opt('\\s*You might want to use.*') or { panic(err) }).replace(reason, '')
	return reason.trim_space()[..200]
}

pub fn open_(url string) Any {
	return urllib.request.urlopen(urllib.request.Request(url, map[string]Any{
		'User-Agent': 'Lunoir-V',
	}), 60)
}

pub fn latest_tag() string {
	if true {
		response := open_(releases + '/latest')
		address := response.geturl()
	}
	tag := address.trim_right('/').rsplit('/', 1)[address.trim_right('/').rsplit('/', 1).len - 1]
	if !(regex.regex_opt('\\d{4}\\.\\d{2}\\.\\d{2}(\\.\\d+)?') or { panic(err) }).match_string(tag) {
		panic('ValueError: ' + 'unexpected release address: ${address}')
	}
	return tag
}

pub fn installed_version(exe Path) string {
	result := Any(0)
	// except handlers are not translated: see the TODO(py2v) note above
	//   except OSError | subprocess.TimeoutExpired: 1 statement(s) need an `or { ... }` equivalent
	return if result.returncode == 0 { result.stdout.decode('ascii', 'replace').trim_space() } else { '' }
}

pub fn published_sha256_(tag string) string {
	if true {
		response := open_('${releases}/download/${tag}/SHA2-256SUMS')
		for line in response.read().decode('ascii', 'replace').split_into_lines() {
			py2v_unpack1 := line.trim_space().partition(' ')
			mut digest := py2v_unpack1[0]
			_ := py2v_unpack1[1]
			mut name := py2v_unpack1[2]
			if name.trim_space().trim_left('*') == 'yt-dlp.exe' {
				return digest.to_lower()
			}
		}
	}
	panic('ValueError: ' + 'no checksum for yt-dlp.exe in release ${tag}')
}

pub fn download_(tag string, dest Path)  {
	dest.parent.mkdir(true, true)
	part := dest.with_name(dest.name + '.part')
	defer {
		part.unlink()
	}
	expected := published_sha256_(tag)
	digest := hashlib.sha256()
	if true {
		response := open_('${releases}/download/${tag}/yt-dlp.exe')
		out := part.open('wb')
		for (chunk := response.read(1 << 16)) {
			digest.update(chunk)
			out.write(chunk)
		}
	}
	if digest.hexdigest() != expected {
		panic('ValueError: ' + 'yt-dlp.exe ${tag} does not match its published checksum')
	}
	for attempt in []int{len: 8, init: index} {
		time.sleep(0.5 * attempt)
		os.replace(part, dest)
		return
		// except handlers are not translated: see the TODO(py2v) note above
		//   except OSError: 1 statement(s) need an `or { ... }` equivalent
	}
}
