module main

import os
import time
import x.json2

fn test_live_diagnostics_preserve_zero_missing_values_and_update_in_place() {
	t := new_translator(os.dir(os.dir(@FILE)), 'en')
	mut a := App{
		t:          t
		ui:         new_flet(&t)
		panel_mode: 'info'
		has_media:  true
	}
	a.handle_event({
		'event': json2.Any('property-change')
		'name':  'hwdec-current'
		'data':  'no'
	})
	a.handle_event({
		'event': json2.Any('property-change')
		'name':  'decoder-frame-drop-count'
		'data':  0
	})
	a.handle_event({
		'event': json2.Any('property-change')
		'name':  'avsync'
		'data':  -0.025
	})
	a.handle_event({
		'event': json2.Any('property-change')
		'name':  'cache-buffering-state'
		'data':  37
	})
	a.handle_event({
		'event': json2.Any('property-change')
		'name':  'paused-for-cache'
		'data':  true
	})
	a.fill_panel()
	before_id := a.ui.next_id
	fields := a.info_fields.clone()
	a.refresh_statistics(100)
	assert a.ui.next_id == before_id && a.info_fields == fields
	assert text_value(get(a.ui.controls[fields['decoder']], 'value')) == a.t.tr('stats.software')
	assert text_value(get(a.ui.controls[fields['decoderDrops']], 'value')) == '0'
	assert text_value(get(a.ui.controls[fields['displayDrops']], 'value')) == '—'
	assert text_value(get(a.ui.controls[fields['avsync']], 'value')) == '-25.0 ms'
	assert text_value(get(a.ui.controls[fields['bufferFill']], 'value')) == '37%'
	assert text_value(get(a.ui.controls[fields['state']], 'value')) == a.t.tr('stats.buffering')
	assert a.info_refresh_at == 1100
	a.handle_event({
		'event': json2.Any('property-change')
		'name':  'hwdec-current'
		'data':  'd3d11va'
	})
	a.refresh_statistics(1100)
	assert a.ui.next_id == before_id
	assert text_value(get(a.ui.controls[fields['decoder']], 'value')) == 'd3d11va'
	assert 'hwdec-current' !in a.properties
}

fn test_preset_validation_round_trip_replacement_and_malformed_entries() {
	directory := os.join_path(os.temp_dir(), 'lunoir-presets-${time.now().unix_micro()}')
	defer { os.rmdir_all(directory) or {} }
	mut p := new_profile(directory)
	p.save_preset('Cinema 一', {
		'pictureBrightness': json2.Any(12)
		'pictureDeband':     true
	})!
	mut loaded := new_profile(directory)
	assert number(get(object(get(loaded.presets, 'Cinema 一')), 'pictureBrightness')) == 12
	assert truth(get(object(get(loaded.presets, 'Cinema 一')), 'pictureDeband'))
	// Partial presets replace the managed set using defaults for absent keys.
	p.save_preset('Cinema 一', {
		'pictureContrast': json2.Any(7)
	})!
	loaded = new_profile(directory)
	assert number(get(object(get(loaded.presets, 'Cinema 一')), 'pictureBrightness')) == 0
	assert !truth(get(object(get(loaded.presets, 'Cinema 一')), 'pictureDeband'))
	assert !valid_preset_name('') && !valid_preset_name(' name')
	assert !valid_preset_name('line\nbreak') && !valid_preset_name('a'.repeat(65))
	for bad in [json2.Any(4), {
		'pictureBrightness': json2.Any(101)
	}, {
		'pictureDeband': json2.Any('yes')
	}, {
		'pictureScaler': json2.Any('unknown')
	}, {
		'arbitrary-mpv-option': json2.Any('yes')
	}] {
		if _ := normalize_preset(bad) { assert false
		 }
	}
	p.presets['malformed'] = 'broken'
	p.write('presets.json', p.presets)!
	loaded = new_profile(directory)
	assert loaded.presets.len == 1
	loaded.delete_preset('Cinema 一')!
	assert new_profile(directory).presets.len == 0
}

fn test_picture_settings_apply_and_persist_after_real_idle_mpv_replies() {
	directory := os.join_path(os.temp_dir(), 'lunoir-picture-idle-${time.now().unix_micro()}')
	previous_logs := os.getenv('LOCALAPPDATA')
	os.setenv('LOCALAPPDATA', directory, true)
	defer {
		os.setenv('LOCALAPPDATA', previous_logs, true)
		os.rmdir_all(directory) or {}
	}
	t := new_translator(os.dir(os.dir(@FILE)), 'en')
	mut a := App{
		t:       t
		ui:      new_flet(&t)
		profile: new_profile(directory)
	}
	a.backend.start(unsafe { nil }, ['vo=null', 'ao=null'], false)!
	defer { a.backend.close() }
	values := normalize_preset({
		'pictureBrightness':    json2.Any(13)
		'pictureDeband':        true
		'pictureInterpolation': true
		'pictureScaler':        'ewa_lanczossharp'
	})!
	a.apply_picture_changes(values, 'Cinema')
	assert a.picture_change.remaining > 0
	assert !os.is_file(os.join_path(directory, 'settings.json'))
	// Options apply to the controller even if the queue item changes meanwhile.
	a.revision++
	deadline := time.now().unix_milli() + 4000
	for a.picture_change.remaining > 0 && time.now().unix_milli() < deadline {
		for event in a.backend.events() {
			a.handle_event(event)
		}
		time.sleep(time.millisecond)
	}
	assert a.picture_change.remaining == 0
	assert number(get(a.profile.settings, 'pictureBrightness')) == 13
	assert number(a.backend.get_property('brightness')) == 13
	assert truth(a.backend.get_property('deband'))
	assert text_value(a.backend.get_property('video-sync')) == 'display-resample'
	assert truth(a.backend.get_property('interpolation'))
	assert text_value(a.backend.get_property('scale')) == 'ewa_lanczossharp'
	assert a.profile.settings_dirty
	a.profile.flush_settings(0, true)!
	assert number(get(new_profile(directory).settings, 'pictureBrightness')) == 13
	// Completion-tracked writes cannot be swallowed by slider coalescing.
	tracked := a.backend.set_property_tracked('brightness', 5)!
	assert a.backend.set_property('brightness', 6)! != tracked
}

fn test_rejected_picture_change_keeps_profile_and_missing_preset_options_reset() {
	directory := os.join_path(os.temp_dir(), 'lunoir-picture-rejected-${time.now().unix_micro()}')
	previous_logs := os.getenv('LOCALAPPDATA')
	os.setenv('LOCALAPPDATA', directory, true)
	defer {
		os.setenv('LOCALAPPDATA', previous_logs, true)
		os.rmdir_all(directory) or {}
	}
	t := new_translator(os.dir(os.dir(@FILE)), 'en')
	mut a := App{
		t:       t
		ui:      new_flet(&t)
		profile: new_profile(directory)
	}
	a.profile.set_setting('pictureBrightness', 3)!
	a.picture_change = PictureChange{
		token:       1
		remaining:   2
		values:      {
			'pictureBrightness': json2.Any(14)
			'pictureDeband':     true
		}
		previous:    preset_snapshot(a.profile.settings)
		preset_name: 'Rejected'
	}
	a.picture_reply(1, '')
	assert number(get(a.profile.settings, 'pictureBrightness')) == 3
	a.picture_reply(1, 'unsupported')
	assert a.picture_change.remaining == 0
	assert number(get(new_profile(directory).settings, 'pictureBrightness')) == 3
	assert get(a.profile.settings, 'picturePreset') is json2.Null
	assert properties_for('pictureInterpolation', {
		'pictureInterpolation': json2.Any(true)
	})[0].value == json2.Any('display-resample')
	assert properties_for('pictureInterpolation', {
		'pictureInterpolation': json2.Any(false)
	})[0].value == json2.Any('audio')
}

fn test_picture_panel_and_new_strings_in_every_locale() {
	root := os.dir(os.dir(@FILE))
	for language in locales {
		t := new_translator(root, language)
		for key in ['picture.title', 'preset.save', 'stats.title', 'stats.bufferFill'] {
			assert key in t.strings && t.tr(key) != key
		}
		mut a := App{
			t:            t
			ui:           new_flet(&t)
			panel_mode:   'settings'
			settings_tab: 'picture'
		}
		a.fill_panel()
		assert a.ui.events.values().any(it.name == 'preset_save_dialog')
		assert a.ui.events.values().any(it.name == 'setting_bool'
			&& it.args == [json2.Any('pictureInterpolation')])
		assert a.ui.events.values().any(it.name == 'setting_number'
			&& it.args[0] == json2.Any('pictureBrightness'))
		wire := msgpack_pack(a.ui.tree(a.ui.id('panel_body')))
		assert wire.len > 0 && object(msgpack_unpack(wire)!).len > 0
	}
}
