module main

import os
import time
import math
import x.json2

fn test_formatting_matches_existing_player() {
	assert clock(65) == '01:05'
	assert clock(3725) == '1:02:05'
	assert clock(math.inf(1)) == '00:00'
	assert duration_text(65) == '1:05'
	assert timecode(current_frame(0, 10.5, 24), 23.976) == '00:00:10:12'
	assert audio_badge('eac3', 6) == 'DD+ 5.1'
	assert audio_badge('pcm_s16le', 2) == 'PCM 2.0'
	assert resolution_tier(1920, 800) == 1080
	assert resolution_tier(960, 544) == 540
	assert screenshot_template('Show.S01E02.1080p.WEB-DL.x264-GRP.mkv', 3725) == 'Show.S01E02_01-02-05_%ty%tm%td_%tH%tM%tS'
	assert clean_base_name('100%.mkv') == '100'
	assert clean_base_name('電影.2160p.mkv') == '電影'
}

fn test_track_labels_match_existing_player() {
	a := App{
		t: new_translator(os.dir(os.dir(@FILE)), 'en')
	}
	assert a.track_label({
		'title':               json2.Any('Film 1080p WEB-DL')
		'lang':                'eng'
		'codec':               'opus'
		'demux-channel-count': 2
		'demux-bitrate':       128000
	}, true) == 'English Opus 2.0   128 kbps'
	assert a.track_label({
		'title':               json2.Any('Commentary')
		'lang':                'eng'
		'codec':               'aac'
		'demux-channel-count': 4
	}, true) == 'Commentary · English AAC 4ch'
	assert a.track_label({
		'title': json2.Any('Accessible SDH Forced')
		'lang':  'eng'
	}, false) == 'English SDH Forced'
	assert a.track_label({
		'title': json2.Any('English_Commentary.ASS')
	}, false) == 'English Commentary'
}

fn test_playlists_and_queue_hash_match_existing_player() {
	assert queue_key(['C:/v/电影 01.mkv', 'https://www.youtube.com/watch?v=a', '😀.mp4']) == 'pl:hhu0et'
	assert queue_key(['']) == 'pl:0'
	entries := parse_local_m3u('C:/Media/list.m3u',
		'\ufeff#EXTM3U\n#EXTINF:-1 tvg-name="a, b",Episode 1\nshow/one.mkv\n"two.mp4"\nfile:///C:/Media/three%20x.mkv\nhttps://example.com/v.mp4\n')
	assert entries.len == 4
	assert entries[0].title == 'Episode 1'
	assert entries[0].path.replace('\\', '/') == 'C:/Media/show/one.mkv'
	assert entries[1].title == 'two.mp4'
	assert entries[2].path == 'C:\\Media\\three x.mkv'
	channels :=
		parse_channel_list('#EXTM3U\n#EXTINF:-1 group-title="News",World, Live\nhttp://a/1.m3u8\n#EXTINF:-1,No group\nhttps://a/2\n#EXTINF:-1,Skipped\nrtmp://not-http\n')
	assert channels.len == 2 && channels[0].title == 'World, Live' && channels[0].group == 'News'
	assert parse_channel_list('Sport,#genre#\nOne,http://b/1\nbad line\nTwo,https://b/2')[1].group == 'Sport'
	assert is_local_queue('C:/a/b.M3U') && !is_local_queue('http://x/b.m3u')
	assert is_channel_list('http://x/list.txt?token=1') && !is_channel_list('http://x/live.m3u8')
	assert natural_compare('ep2.mkv', 'ep10.mkv') < 0
	assert natural_compare('ep9999999999999999999999.mkv', 'ep10000000000000000000000.mkv') < 0
}

fn test_profile_round_trip_selections_and_history() {
	directory := os.join_path(os.temp_dir(), 'lunoir-v-profile-test-${time.now().unix_micro()}')
	defer { os.rmdir_all(directory) or {} }
	mut p := new_profile(directory)
	p.set_setting('screenshotDir', 'D:/shots')!
	p.save_audio('film.mkv', {
		'type': json2.Any('embedded')
		'id':   2
	})!
	p.save_subtitle('film.mkv', {
		'type': json2.Any('external')
		'path': 'C:/s/en.srt'
	})!
	p.save_subtitle('film.mkv', {
		'type': json2.Any('none')
	})!
	p.save_audio('film.mkv', {
		'type': json2.Any('embedded')
		'id':   'bad'
	})!
	p.save_position('film.mkv', 75, 100, true)!
	p.save_playlist_item('file:c:/list.m3u', 'b.mkv')!
	p.recent('https://x/v', 'Old', 'url')!
	p.rename_recent('https://x/v', 'Real title')!
	assert p.toggle_favourite('list.m3u', 'List', 'list', {
		'channels': json2.Any([]json2.Any{})
	})!
	restored := new_profile(directory)
	assert get(object(get(restored.audio, 'film.mkv')), 'id').int() == 2
	assert restored.subtitle_files('film.mkv') == ['C:/s/en.srt']
	assert text_value(get(object(get(restored.subtitles, 'film.mkv')), 'type')) == 'none'
	assert number(get(restored.positions, 'film.mkv')) == 75
	assert text_value(get(object(restored.recents[0]), 'name')) == 'Real title'
	assert restored.is_favourite('list.m3u')
	assert startup_properties(restored.settings).any(it.name == 'image-subs-hdr-peak'
		&& number(it.value) == 120)
	assert sub_font_chain('Segoe UI') == 'Segoe UI,Microsoft YaHei'
	p.save_position('film.mkv', 95, 100, true)!
	assert 'film.mkv' !in p.positions
}

fn test_translations_and_flet_shell() {
	parsed := parse_locale('{"a":"it\\u0027s\\nfine","b":"x \\u00e9"}')
	assert parsed == {
		'a': "it's\nfine"
		'b': 'x é'
	}
	assert resolve_system_locale('zh-Hans-CN') == 'zh-CN'
	assert resolve_system_locale('zh-TW') == 'en'
	assert resolve_system_locale('pt_BR') == 'pt'
	root := os.dir(os.dir(@FILE))
	en := new_translator(root, 'en')
	reference := new_flet(&en)
	for language in locales {
		t := new_translator(root, language)
		assert t.strings.len == t.fallback.len
		assert t.strings.len >= 305
		ui := new_flet(&t)
		assert ui.controls.len > 70
		assert ui.events.len == 41
		for id, control in ui.controls {
			assert get(control, '_c') == get(reference.controls[id] or {
				map[string]json2.Any{}
			}, '_c')
		}
		encoded := msgpack_pack(ui.tree(1))
		assert json_encode(msgpack_unpack(encoded)!) == json_encode(ui.tree(1))
	}
}

fn test_msgpack_boundaries_and_malformed_frames() {
	assert object(json2.Any(json2.Null{})).len == 0
	assert list_value(json2.Any(json2.Null{})).len == 0
	values := [json2.Any(-33), i64(-9223372036854775807), i64(9223372036854775807), 0, 127, 128,
		true, false, json2.Null{}, 3.141592653589793, '😀'.repeat(1000),
		{
			'nested': json2.Any([json2.Any('a'), 55])
		}]
	for value in values {
		assert json_encode(msgpack_unpack(msgpack_pack(value))!) == json_encode(value)
	}
	if _ := msgpack_unpack([u8(0xdb), 255, 255, 255, 255]) { assert false
	 }
	if _ := msgpack_unpack([u8(0x91)]) { assert false
	 }
	assert quote_argument('C:\\folder with space\\') == '"C:\\folder with space\\\\"'
}
