module main

import os
import time
import strconv
import x.json2

struct Profile {
mut:
	directory      string
	settings       map[string]json2.Any
	positions      map[string]json2.Any
	recents        []json2.Any
	favourites     []json2.Any
	playlist_items map[string]json2.Any
	audio          map[string]json2.Any
	subtitles      map[string]json2.Any
}

fn default_profile_directory() string {
	base := os.getenv('APPDATA')
	return os.join_path(if base == '' { os.home_dir() } else { base }, 'Lunoir V')
}

fn new_profile(directory string) Profile {
	mut p := Profile{
		directory: directory
	}
	p.settings = object(json_decode($embed_file('defaults.json').to_string()) or { panic(err) })
	for key, value in object(p.read('settings.json', map[string]json2.Any{})) {
		p.settings[key] = value
	}
	p.positions = object(p.read('positions.json', map[string]json2.Any{}))
	p.recents = list_value(p.read('recents.json', []json2.Any{}))
	p.favourites = list_value(p.read('favourites.json', []json2.Any{}))
	p.playlist_items = object(p.read('playlist-progress.json', map[string]json2.Any{}))
	for key, value in object(p.read('audio-selections.json', map[string]json2.Any{})) {
		if valid_audio(value) { p.audio[key] = value }
	}
	for key, value in object(p.read('subtitle-selections.json', map[string]json2.Any{})) {
		if valid_subtitle(value) { p.subtitles[key] = value }
	}
	return p
}

fn (p &Profile) read(name string, fallback json2.Any) json2.Any {
	return json_read(os.join_path(p.directory, name), fallback)
}

fn (p &Profile) write(name string, data json2.Any) ! {
	os.mkdir_all(p.directory)!
	path := os.join_path(p.directory, name)
	temporary := path + '.tmp'
	os.write_file(temporary, json_encode(data))!
	atomic_replace(temporary, path)!
}

fn (mut p Profile) set_setting(key string, value json2.Any) ! {
	p.settings[key] = value
	p.write('settings.json', p.settings)!
}

fn (mut p Profile) save_position(target string, seconds f64, duration f64, seekable bool) ! {
	if target == '' || !seekable || !truth(get(p.settings, 'resumePlayback')) { return }
	if duration > 0 && seconds > duration - 10 {
		if target !in p.positions { return }
		p.positions.delete(target)
	} else if seconds > 5 {
		if number(get(p.positions, target)) == seconds { return }
		p.positions[target] = seconds
	} else {
		return
	}
	p.write('positions.json', p.positions)!
}

fn (mut p Profile) clear_position(target string) ! {
	if target in p.positions {
		p.positions.delete(target)
		p.write('positions.json', p.positions)!
	}
}

fn valid_audio(value json2.Any) bool {
	if value !is map[string]json2.Any { return false }
	kind := text_value(get(object(value), 'type'))
	id := get(object(value), 'id')
	path := get(object(value), 'path')
	return (kind == 'embedded' && (id is int || id is i64))
		|| (kind == 'external' && path is string)
}

fn valid_subtitle(value json2.Any) bool {
	if value !is map[string]json2.Any { return false }
	kind := text_value(get(object(value), 'type'))
	id := get(object(value), 'id')
	path := get(object(value), 'path')
	return kind == 'none' || (kind == 'embedded' && (id is int || id is i64) && number(id) > 0)
		|| (kind == 'external' && path is string && path.len > 0)
}

fn (p &Profile) subtitle_files(target string) []string {
	saved := object(get(p.subtitles, target))
	mut files := []string{}
	for item in list_value(get(saved, 'externalPaths')) {
		if item is string && item.len > 0 && item !in files { files << item }
	}
	path := text_value(get(saved, 'path'))
	if text_value(get(saved, 'type')) == 'external' && path != '' && path !in files { files << path }
	return files
}

fn (mut p Profile) save_audio(target string, selection json2.Any) ! {
	if target != '' && valid_audio(selection) {
		p.audio[target] = selection
		p.write('audio-selections.json', p.audio)!
	}
}

fn (mut p Profile) save_subtitle(target string, selection json2.Any) ! {
	if target == '' || !valid_subtitle(selection) { return }
	mut files := p.subtitle_files(target)
	mut saved := object(selection).clone()
	path := text_value(get(saved, 'path'))
	if text_value(get(saved, 'type')) == 'external' && path !in files { files << path }
	saved['externalPaths'] = files.map(json2.Any(it))
	p.subtitles[target] = saved
	p.write('subtitle-selections.json', p.subtitles)!
}

fn (mut p Profile) save_playlist_item(key string, item string) ! {
	if key != '' && text_value(get(p.playlist_items, key)) != item {
		p.playlist_items[key] = item
		p.write('playlist-progress.json', p.playlist_items)!
	}
}

fn target_kind(target string) string {
	return if is_url(target) { 'url' } else { 'file' }
}

fn (mut p Profile) recent(target string, name string, kind string) ! {
	entry := json2.Any({
		'target': json2.Any(target)
		'name':   name
		'kind':   if kind == '' { target_kind(target) } else { kind }
		'at':     time.now().unix_milli()
	})
	previous := p.recents.clone()
	p.recents = [entry]
	for item in previous {
		if text_value(get(object(item), 'target')) != target && p.recents.len < 20 {
			p.recents << item
		}
	}
	p.write('recents.json', p.recents)!
}

fn (mut p Profile) rename_recent(target string, name string) ! {
	for i, item in p.recents {
		mut record := object(item).clone()
		if text_value(get(record, 'target')) == target && name != '' {
			record['name'] = name
			p.recents[i] = record
		}
	}
	p.write('recents.json', p.recents)!
}

fn (mut p Profile) remove_recent(target string) ! {
	p.recents = p.recents.filter(text_value(get(object(it), 'target')) != target)
	p.write('recents.json', p.recents)!
}

fn (p &Profile) is_favourite(target string) bool {
	return p.favourites.any(text_value(get(object(it), 'target')) == target)
}

fn (mut p Profile) toggle_favourite(target string, name string, kind string, extra map[string]json2.Any) !bool {
	saved := !p.is_favourite(target)
	if !saved {
		p.favourites = p.favourites.filter(text_value(get(object(it), 'target')) != target)
	} else {
		mut entry := extra.clone()
		entry['target'] = target
		entry['name'] = name
		entry['kind'] = if kind == '' { target_kind(target) } else { kind }
		entry['at'] = time.now().unix_milli()
		p.favourites.prepend(json2.Any(entry))
	}
	p.write('favourites.json', p.favourites)!
	return saved
}

fn (mut p Profile) rename_favourite(target string, name string) ! {
	if name.trim_space() == '' { return }
	for i, item in p.favourites {
		mut entry := object(item).clone()
		if text_value(get(entry, 'target')) == target {
			entry['name'] = name.trim_space()
			p.favourites[i] = entry
		}
	}
	p.write('favourites.json', p.favourites)!
}

fn queue_key(paths []string) string {
	mut hash := u32(0)
	for r in paths.join('|').runes() {
		if u32(r) > 0xffff {
			value := u32(r) - 0x10000
			hash = hash * 31 + 0xd800 + (value >> 10)
			hash = hash * 31 + 0xdc00 + (value & 0x3ff)
		} else {
			hash = hash * 31 + u32(r)
		}
	}
	return 'pl:' + strconv.format_uint(u64(hash), 36)
}
