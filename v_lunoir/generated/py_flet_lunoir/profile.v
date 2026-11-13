module py_flet_lunoir

import json
import os
import time

// TODO(py2v): 1 except handler(s) need a V Result equivalent:
//   except OSError | ValueError (1 stmt)

const defaults = {
	'uiLanguage': 'system',
	'scanFolderIntoPlaylist': false,
	'resumePlayback': true,
	'resumePlaylistItem': true,
	'keepPitch': true,
	'audioLang': '',
	'subLang': '',
	'subsDefaultOn': true,
	'autoLoadSubs': true,
	'subCodepage': 'auto',
	'audioPassthrough': false,
	'passthroughCodecs': 'ac3,eac3,truehd,dts,dts-hd',
	'oscHideDelay': 5,
	'oscStyle': 'floating',
	'seekPreview': true,
	'frostStrength': 50,
	'subHdrPeak': 120,
	'hwdec': 'auto',
	'enhance': false,
	'deblock': 3,
	'nr': 0,
	'sharpen': 0.2,
	'artcnn': false,
	'cfl': false,
	'deinterlace': 'no',
	'streamQuality': 'best',
	'useCookies': false,
	'cookiesBrowser': 'edge',
	'subFont': 'Microsoft YaHei',
	'subFontSize': 38,
	'subSpacing': 0,
	'subBold': false,
	'subOutline': 3,
	'subMarginY': 34,
	'timeFormat': 'time',
	'timecodeOverlay': false,
	'screenshotSubs': true,
	'screenshotFormat': 'png',
	'screenshotDir': '',
	'recordingDir': '',
	'hideTitleBar': false,
	'rememberWindow': true,
	'rememberVolume': true,
	'checkForUpdates': true,
	'experimentalTimeline': false,
	'pinOscInTrim': true,
	'volume': 100,
	'windowBounds': none,
}
const recents_cap = 20

pub struct Profile {
pub mut:
	directory Any
	settings Any
	positions Any
	recents Any
	favourites Any
	playlist_items Any
	audio Any
	subtitles Any
}

pub fn (mut self Profile) init(directory ?Path) {
	self.directory = directory || self.default_directory()
	self.settings = defaults
	self.settings.update(self.read('settings.json', map[string]Any{}))
	self.positions = self.read('positions.json', map[string]Any{})
	self.recents = self.read('recents.json', [])
	self.favourites = self.read('favourites.json', [])
	self.playlist_items = self.read('playlist-progress.json', map[string]Any{})
	self.audio = (fn () map[string]Any {
	mut result := map[string]Any{}
	for [key, value] in self.read('audio-selections.json', map[string]Any{}).items() {
	if valid_audio(value) {
	result[key] = value
	}
	}
	return result
	}())
	self.subtitles = (fn () map[string]Any {
	mut result := map[string]Any{}
	for [key, value] in self.read('subtitle-selections.json', map[string]Any{}).items() {
	if valid_subtitle(value) {
	result[key] = value
	}
	}
	return result
	}())
}

pub fn (self Profile) read(name Any, default Any) Any {
	value := json.loads(os.read_file((self.directory / name)) or { '' })
	return if value is @type(default) { value } else { default }
	// except handlers are not translated: see the TODO(py2v) note above
	//   except OSError | ValueError: 1 statement(s) need an `or { ... }` equivalent
}

pub fn (self Profile) write(name Any, data Any)  {
	self.directory.mkdir(true, true)
	path := self.directory / name
	temporary := path.with_suffix('.tmp')
	os.write_file(temporary, json.dumps(data, false, 2))!
	temporary
}

pub fn (mut self Profile) set(key string, value Any)  {
	self.settings[key] = value
	self.write('settings.json', self.settings)
}

pub fn (mut self Profile) save_position(target string, seconds f64, duration f64, seekable bool)  {
	if !target || !seekable || !self.settings.get('resumePlayback') {
		return
	}
	near_end := duration > 0 && seconds > duration - 10
	if near_end {
		if (self.positions[target] or { 0 }) == none {
			return
		}
	} else if seconds > 5 {
		if self.positions.get(target) == seconds {
			return
		}
		self.positions[target] = seconds
	} else {
		return
	}
	self.write('positions.json', self.positions)
}

pub fn (self Profile) clear_position(target string)  {
	if (self.positions[target] or { 0 }) != none {
		self.write('positions.json', self.positions)
	}
}

pub fn (mut self Profile) save_audio(target string, selection map[string]Any)  {
	if target && valid_audio(selection) {
		self.audio[target] = selection
		self.write('audio-selections.json', self.audio)
	}
}

pub fn (self Profile) subtitle_files(target string) []string {
	saved := self.subtitles.get(target) || map[string]Any{}
	mut files := saved.get('externalPaths', []).filter(it is str && it).map(it)
	if saved.get('type') == 'external' {
		files << saved['path']
	}
	return dict.fromkeys(files)
}

pub fn (mut self Profile) save_subtitle(target string, selection map[string]Any)  {
	if !target || !valid_subtitle(selection) {
		return
	}
	mut files := self.subtitle_files(target)
	if selection['type'] == 'external' {
		files << selection['path']
	}
	self.subtitles[target] = {
		'externalPaths': dict.fromkeys(files),
	}
	self.write('subtitle-selections.json', self.subtitles)
}

pub fn (mut self Profile) save_playlist_item(key string, item string)  {
	if key && self.playlist_items.get(key) != item {
		self.playlist_items[key] = item
		self.write('playlist-progress.json', self.playlist_items)
	}
}

pub fn (mut self Profile) recent(target string, name string, kind ?string)  {
	entry := {
		'target': target,
		'name': name,
		'kind': kind || (if target.contains('://') { 'url' } else { 'file' }),
		'at': int(time.time() * 1000),
	}
	self.recents = ([entry] + self.recents.filter(it.get('target') != target).map(it))[..recents_cap]
	self.write('recents.json', self.recents)
}

pub fn (self Profile) rename_recent(target string, name string)  {
	for item in self.recents {
		if item.get('target') == target && name && item.get('name') != name {
			item['name'] = name
			self.write('recents.json', self.recents)
		}
	}
}

pub fn (mut self Profile) remove_recent(target string)  {
	self.recents = self.recents.filter(it.get('target') != target).map(it)
	self.write('recents.json', self.recents)
}

pub fn (mut self Profile) clear_recents()  {
	self.recents = []
	self.write('recents.json', self.recents)
}

pub fn (self Profile) is_favourite(target string) bool {
	return self.favourites.map(it.get('target') == target).any(it)
}

pub fn (mut self Profile) toggle_favourite(target string, name string, kind ?string, extra map[string]Any) bool {
	if self.is_favourite(target) {
		self.favourites = self.favourites.filter(it.get('target') != target).map(it)
		mut saved := false
	} else {
		self.favourites.insert(0, map[string]Any{
			'target': target,
			'name': name,
			'kind': kind || (if target.contains('://') { 'url' } else { 'file' }),
			'at': int(time.time() * 1000),
		})
		saved = true
	}
	self.write('favourites.json', self.favourites)
	return saved
}

pub fn (self Profile) rename_favourite(target string, name string)  {
	name = name.trim_space()
	for item in self.favourites {
		if item.get('target') == target && name && item.get('name') != name {
			item['name'] = name
			self.write('favourites.json', self.favourites)
		}
	}
}

// @staticmethod
pub fn Profile_default_directory() Path {
	return os.join_path(os.environ.get('APPDATA', Path.home()), 'Lunoir V')
}

pub fn queue_key(paths []string) string {
	data := paths.join('|').bytes()
	mut h := 0
	for i := 0; i < data.len; i += 2 {
		h = (h * 31 + int.from_bytes(data[i..i + 2], 'little')) & 4.294967295e+09
	}
	mut digits := ''
	for {
		py2v_unpack1 := (h / 36, h % 36)
		h = py2v_unpack1[0]
		mut r := py2v_unpack1[1]
		digits = '0123456789abcdefghijklmnopqrstuvwxyz'[r] + digits
		if !h {
			return 'pl:' + digits
		}
	}
}

pub fn valid_audio(value Any) bool {
	return value is dict && ((value.get('type') == 'embedded' && value.get('id') is int) || (value.get('type') == 'external' && value.get('path') is str))
}

pub fn valid_subtitle(value Any) bool {
	return value is dict && (value.get('type') == 'none' || (value.get('type') == 'embedded' && value.get('id') is int && value['id'] > 0) || (value.get('type') == 'external' && value.get('path') is str && (value['path'] != 0)))
}
