module main

import os
import time
import math
import x.json2

#include "@VMODROOT/v_lunoir/native_test_helpers.h"

fn C.lv_test_parent() voidptr
fn C.lv_test_drop_payload(int, &int) &char
fn C.lv_test_drop_lifecycle() int

fn test_native_drop_reads_real_com_data_objects() {
	mut effect := 0
	files := owned_c_string(C.lv_test_drop_payload(0, &effect)).split_into_lines()
	assert effect == 1
	assert files == ['C:\\Film 一.mkv', 'D:\\two.mp4']
	url := owned_c_string(C.lv_test_drop_payload(1, &effect)).trim_space()
	assert effect == 1 && url == 'https://example.test/video?id=one'
	assert owned_c_string(C.lv_test_drop_payload(2, &effect)) == '' && effect == 0
	assert C.lv_test_drop_lifecycle() == 1
}

fn test_single_instance_forwards_and_releases_the_profile_lock() {
	directory := os.join_path(os.temp_dir(),
		'lunoir-native-instance-${os.getpid()}-${time.now().unix_micro()}')
	first := new_instance(directory)
	second := new_instance(directory)
	assert C.lv_instance_claimed(first) == 1
	assert C.lv_instance_claimed(second) == 0
	C.lv_instance_serve(first, unsafe { nil })
	message := '["C:/Film 一.mkv","https://example.test/watch"]'
	assert C.lv_instance_forward(second, &char(message.str), 5000) == 1
	assert instance_requests(first) == [
		['C:/Film 一.mkv', 'https://example.test/watch'],
	]
	C.lv_instance_close(second)
	C.lv_instance_close(first)
	third := new_instance(directory)
	assert C.lv_instance_claimed(third) == 1
	C.lv_instance_close(third)
}

fn native_test_clip(path string) ! {
	mut encoder := MpvController{}
	encoder.start(unsafe { nil }, ['o=${path}', 'of=matroska', 'ovc=mjpeg', 'vo=null', 'ao=null',
		'keep-open=no'], false)!
	defer { encoder.close() }
	encoder.command([json2.Any('loadfile'), 'av://lavfi:testsrc=duration=40:size=160x120:rate=24'])!
	deadline := time.now().unix_milli() + 30000
	for time.now().unix_milli() < deadline {
		for event in encoder.events() {
			if text_value(get(event, 'event')) == 'end-file' {
				if text_value(get(event, 'reason')) == 'error' {
					return error('Could not encode the test clip')
				}
				return
			}
		}
		time.sleep(5 * time.millisecond)
	}
	return error('Encoding the test clip timed out')
}

fn pump_native(mut a App, milliseconds i64) {
	until := time.now().unix_milli() + milliseconds
	for time.now().unix_milli() < until {
		C.lv_pump()
		for event in a.backend.events() {
			a.handle_event(event)
		}
		a.thumbs.tick()
		time.sleep(10 * time.millisecond)
	}
}

fn test_native_playback_restores_subtitles_resume_preview_and_screenshots() {
	directory := os.join_path(os.temp_dir(), 'lunoir-native-media-${time.now().unix_micro()}')
	os.mkdir_all(directory)!
	defer { os.rmdir_all(directory) or {} }
	clip := os.join_path(directory, 'clip.mkv')
	second := os.join_path(directory, 'second.mkv')
	subtitle := os.join_path(directory, 'English.srt')
	native_test_clip(clip)!
	os.cp(clip, second)!
	os.write_file(subtitle, '1\n00:00:00,000 --> 00:00:35,000\nNative V subtitle\n')!
	mut profile := new_profile(os.join_path(directory, 'profile'))
	profile.set_setting('screenshotDir', os.join_path(directory, 'shots'))!
	profile.save_position(clip, 9, 40, true)!
	profile.save_subtitle(clip, {
		'type': json2.Any('external')
		'path': subtitle
	})!
	root := os.dir(os.dir(@FILE))
	t := new_translator(root, 'en')
	parent := C.lv_test_parent()
	defer { C.lv_destroy(parent) }
	mut a := App{
		root:       root
		profile:    profile
		t:          t
		ui:         new_flet(&t)
		surface:    new_video(parent, 0)!
		ready:      true
		properties: {
			'volume':   json2.Any(100)
			'pause':    false
			'speed':    1
			'seekable': true
		}
	}
	a.thumbs.parent = parent
	a.backend.start(a.surface.hwnd, ['ao=null', 'hwdec=no'], true)!
	defer { a.close() }
	for property in startup_properties(a.profile.settings) {
		a.try_set(property.name, property.value)
	}
	a.open_paths([clip, second])
	pump_native(mut a, 1500)
	assert a.queue.len == 2 && a.index == 0
	assert number(a.backend.get_property('time-pos')) > 8
	assert list_value(a.backend.get_property('track-list')).any(text_value(get(object(it),
		'external-filename')) == subtitle)
	assert number(a.backend.get_property('sid')) > 0
	assert a.thumbs.file_ready && a.thumbs.video_h == 240
	a.try_set('pause', true)
	pump_native(mut a, 100)
	a.thumbs.preview(17, 400, 400, 800, false)
	pump_native(mut a, 1000)
	assert a.thumbs.has_frame && a.thumbs.queued < 0
	assert math.abs(number(a.thumbs.backend.get_property('time-pos')) - 17) < 0.2
	assert truth(a.thumbs.backend.get_property('pause'))
	assert a.thumbs.surface.bounds == [240, 130, 320, 262]
	a.screenshot()
	assert (os.ls(os.join_path(directory, 'shots'))!).any(it.ends_with('.png'))
	a.dispatch('volume_start', []json2.Any{}, json2.Null{})
	a.dispatch('volume_change', []json2.Any{}, 37)
	a.dispatch('volume_end', []json2.Any{}, 37)
	pump_native(mut a, 100)
	assert number(a.backend.get_property('volume')) == 37 && !a.volume_dragging
	a.advance(1, false)
	pump_native(mut a, 500)
	assert a.current == second && a.index == 1
	a.advance(-1, false)
	pump_native(mut a, 500)
	assert a.current == clip && a.index == 0
	a.panel_mode = 'playlist'
	a.fill_panel()
	a.save_collection()
	assert a.profile.is_favourite(queue_key([clip, second]))
	a.remove_item(1)
	assert a.queue.len == 1 && a.index == 0
	a.change_setting('uiLanguage', 'de')
	assert a.t.locale == 'de'
	assert text_value(get(a.ui.controls[3] or {
		map[string]json2.Any{}
	}, '_c')) == 'View'
	a.go_home()
	pump_native(mut a, 50)
	assert !a.has_media && a.queue.len == 0 && !a.thumbs.enabled
}
