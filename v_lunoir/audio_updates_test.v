module main

import os
import time
import x.json2

// These checks enumerate an idle null-output core or supply state/events.
// No media is loaded, no sound is played, and no windows are created.
fn test_audio_device_list_validation_and_deduplication() {
	devices := parse_audio_devices([
		json2.Any({
			'name':        json2.Any('auto')
			'description': 'automatic'
		}),
		{
			'name':        json2.Any('wasapi/speakers')
			'description': 'Speakers'
		},
		{
			'name':        json2.Any('wasapi/speakers')
			'description': 'duplicate'
		},
		{
			'name':        json2.Any('wasapi/headphones')
			'description': ''
		},
		{
			'name': json2.Any(12)
		},
		{
			'description': json2.Any('missing id')
		},
		'invalid',
	])!
	assert devices.len == 3 && devices[0].name == 'auto'
	assert devices[1].description == 'Speakers'
	assert devices[2].description == 'wasapi/headphones'
	assert parse_audio_devices([]json2.Any{})!.len == 1
	if _ := parse_audio_devices(json2.Any('invalid')) { assert false
	 }
}

fn test_saved_audio_output_defers_opening_until_the_selection_is_ready() {
	mut a := App{
		profile: Profile{
			settings: {
				'audioDevice': json2.Any('wasapi/saved')
			}
		}
	}
	assert a.defer_audio_open(['first.mkv'], '', '')
	assert a.defer_audio_open([]string{}, 'https://example.test/video', 'custom-agent')
	assert a.audio_outputs.pending_open.paths.len == 0
	assert a.audio_outputs.pending_open.agent == 'custom-agent'
	a.audio_outputs.known = true
	a.audio_outputs.changing = true
	assert !a.audio_output_ready()
	a.audio_outputs.changing = false
	assert a.audio_output_ready()
	a.profile.settings['audioDevice'] = 'auto'
	a.audio_outputs.reading = true
	a.audio_outputs.known = false
	assert a.audio_output_ready()
}

fn test_worker_discovery_preserves_playback_replies_and_restores_missing_device() {
	directory := os.join_path(os.temp_dir(), 'lunoir-audio-idle-${time.now().unix_micro()}')
	previous_logs := os.getenv('LOCALAPPDATA')
	os.setenv('LOCALAPPDATA', directory, true)
	defer {
		os.setenv('LOCALAPPDATA', previous_logs, true)
		os.rmdir_all(directory) or {}
	}
	t := new_translator(os.dir(os.dir(@FILE)), 'en')
	mut a := App{
		t:          t
		ui:         new_flet(&t)
		profile:    new_profile(directory)
		properties: {
			'audio-device': json2.Any('auto')
		}
	}
	a.profile.set_setting('audioDevice', 'wasapi/disconnected-test-device')!
	a.backend.start(unsafe { nil }, ['vo=null', 'ao=null'], false)!
	defer {
		a.audio_outputs.close()
		a.backend.close()
	}
	a.start_audio_discovery(false)
	assert a.audio_outputs.reading && a.audio_outputs.worker_started
	assert a.backend.queued.len == 0 && a.backend.active.id == 0
	request := a.backend.set_property_tracked('volume', 42)!
	mut saw_reply := false
	a.revision++ // Output choices are global, independent of the queue item.
	deadline := time.now().unix_milli() + 5000
	for time.now().unix_milli() < deadline {
		for event in a.backend.events() {
			if get(event, 'request_id').i64() == i64(request) {
				assert text_value(get(event, 'error')) == ''
				saw_reply = true
			}
			a.handle_event(event)
		}
		a.poll_audio_devices()
		if saw_reply && a.audio_outputs.known && !a.audio_outputs.reading && !a.audio_outputs.changing { break
		 }
		time.sleep(time.millisecond)
	}
	assert saw_reply && a.audio_outputs.known && !a.audio_outputs.worker_started
	assert !a.audio_outputs.changing && a.audio_outputs.devices[0].name == 'auto'
	assert text_value(get(a.profile.settings, 'audioDevice')) == 'auto'
	assert a.profile.settings_dirty
	assert text_value(get(new_profile(directory).settings, 'audioDevice')) == 'wasapi/disconnected-test-device'
	a.profile.flush_settings(0, true)!
	assert text_value(get(new_profile(directory).settings, 'audioDevice')) == 'auto'
	assert a.audio_outputs.notice.contains('disconnected-test-device')
	// Closing during another discovery joins the worker before core teardown.
	a.start_audio_discovery(true)
	a.audio_outputs.close()
	assert !a.audio_outputs.worker_started && !a.audio_outputs.reading
}

fn test_audio_selection_failure_stale_reply_and_picker_translations() {
	directory := os.join_path(os.temp_dir(), 'lunoir-audio-state-${time.now().unix_micro()}')
	previous_logs := os.getenv('LOCALAPPDATA')
	os.setenv('LOCALAPPDATA', directory, true)
	defer {
		os.setenv('LOCALAPPDATA', previous_logs, true)
		os.rmdir_all(directory) or {}
	}
	root := os.dir(os.dir(@FILE))
	t := new_translator(root, 'en')
	mut a := App{
		t:             t
		ui:            new_flet(&t)
		profile:       new_profile(directory)
		revision:      3
		audio_outputs: AudioOutputs{
			changing:  true
			selection: 2
			previous:  'wasapi/speakers'
		}
	}
	a.playback_actions[51] = PlaybackAction{
		kind:   'audio-output'
		token:  1
		target: 'old-device'
	}
	a.handle_backend_reply(mpv_reply(MpvRequest{ id: 51 }, '', json2.Null{}))
	assert a.audio_outputs.changing && get(a.profile.settings, 'audioDevice') == json2.Any('auto')
	a.playback_actions[52] = PlaybackAction{
		kind:   'audio-output'
		token:  2
		target: 'wasapi/headphones'
	}
	a.handle_backend_reply(mpv_reply(MpvRequest{ id: 52 }, 'rejected', json2.Null{}))
	assert !a.audio_outputs.changing && !a.profile.settings_dirty
	assert get(a.properties, 'audio-device') == json2.Any('wasapi/speakers')
	for language in locales {
		translated := new_translator(root, language)
		for key in ['audio.title', 'audio.default', 'audio.refresh', 'audio.unavailable'] {
			assert key in translated.strings && translated.tr(key) != key
		}
		mut ui := App{
			t:             translated
			ui:            new_flet(&translated)
			panel_mode:    'settings'
			settings_tab:  'playback'
			audio_outputs: AudioOutputs{
				known: true
			}
		}
		ui.fill_panel()
		assert_flat_control_children(ui.ui.tree(ui.ui.id('panel_body')))
		assert ui.ui.events.values().any(it.name == 'audio_output_select')
		assert ui.ui.events.values().any(it.name == 'audio_output_refresh')
		assert msgpack_pack(ui.ui.tree(ui.ui.id('panel_body'))).len > 0
	}
}

fn assert_flat_control_children(value json2.Any) {
	if value is map[string]json2.Any {
		if 'controls' in value {
			assert list_value(get(value, 'controls')).all(it is map[string]json2.Any)
		}
		for _, child in value {
			assert_flat_control_children(child)
		}
	} else if value is []json2.Any {
		for child in value {
			assert_flat_control_children(child)
		}
	}
}

fn test_settings_debounce_unchanged_values_revert_force_flush_and_retry() {
	directory := os.join_path(os.temp_dir(), 'lunoir-save-batch-${time.now().unix_micro()}')
	defer { os.rmdir_all(directory) or {} }
	mut p := new_profile(directory)
	p.set_setting('volume', 77)!
	path := os.join_path(directory, 'settings.json')
	p.stage_setting('volume', 78, 1000)
	p.stage_setting('volume', 80, 1500)
	p.stage_setting('volume', 80, 1800) // Unchanged input does not move the deadline.
	assert p.settings_save_at == 2500
	p.flush_settings(2499, false)!
	assert number(get(new_profile(directory).settings, 'volume')) == 77
	p.flush_settings(2500, false)!
	assert !p.settings_dirty && number(get(new_profile(directory).settings, 'volume')) == 80
	os.utime(path, 1234567890, 1234567890)!
	p.set_setting('volume', 80)!
	p.stage_setting('volume', 90, 3000)
	p.stage_setting('volume', 80, 3100)
	p.flush_settings(10000, true)!
	assert !p.settings_dirty && p.settings_save_at == 0
	assert os.file_last_mod_unix(path) == 1234567890
	// Shutdown persists pending accepted settings even if startup was incomplete.
	t := new_translator(os.dir(os.dir(@FILE)), 'en')
	mut a := App{
		t:       t
		ui:      new_flet(&t)
		profile: p
	}
	a.queue_setting('volume', 90)
	a.close()
	assert number(get(new_profile(directory).settings, 'volume')) == 90
	// An IO failure keeps the change dirty, with a bounded retry cadence.
	mut retry := new_profile(directory)
	blocked := os.join_path(directory, 'not-a-directory')
	os.write_file(blocked, 'fixture')!
	retry.stage_setting('volume', 91, 4000)
	retry.directory = blocked
	if _ := retry.flush_settings(5000, false) { assert false
	 }
	assert retry.settings_dirty && retry.settings_save_at == 6000
	retry.directory = directory
	retry.flush_settings(5999, false)!
	assert number(get(new_profile(directory).settings, 'volume')) == 90
	retry.flush_settings(6000, false)!
	assert number(get(new_profile(directory).settings, 'volume')) == 91
}

fn test_transport_batch_coalesces_patches_and_preserves_dragged_sliders() {
	t := new_translator(os.dir(os.dir(@FILE)), 'en')
	mut a := App{
		t:          t
		ui:         new_flet(&t)
		properties: {
			'duration': json2.Any(100)
			'time-pos': 0
			'volume':   50
			'mute':     false
			'speed':    1
		}
	}
	a.update_transport()
	a.flush_playback_ui()
	a.ui.pending.clear()
	for position in [10, 20] {
		a.handle_event({
			'event': json2.Any('property-change')
			'name':  'time-pos'
			'data':  position
		})
	}
	for volume in [60, 80] {
		a.handle_event({
			'event': json2.Any('property-change')
			'name':  'volume'
			'data':  volume
		})
	}
	assert a.ui.pending.len == 0 && a.transport_dirty
	a.flush_playback_ui()
	assert !a.transport_dirty && number(a.ui.prop('seek', 'value')) == 0.2
	assert number(a.ui.prop('volume', 'value')) == 80
	seek_ops := a.ui.pending[a.ui.id('seek')] or { []json2.Any{} }
	assert seek_ops.filter(text_value(list_value(it)[2]) == 'value').len == 1
	a.ui.pending.clear()
	a.dragging = true
	a.volume_dragging = true
	a.handle_event({
		'event': json2.Any('property-change')
		'name':  'time-pos'
		'data':  30
	})
	a.handle_event({
		'event': json2.Any('property-change')
		'name':  'volume'
		'data':  70
	})
	a.flush_playback_ui()
	assert number(a.ui.prop('seek', 'value')) == 0.2 && number(a.ui.prop('volume', 'value')) == 80
	a.dragging = false
	a.volume_dragging = false
	a.update_transport()
	a.flush_playback_ui()
	assert number(a.ui.prop('seek', 'value')) == 0.3 && number(a.ui.prop('volume', 'value')) == 70
}

fn test_flet_pending_properties_keep_only_final_values_and_original_operation() {
	t := new_translator(os.dir(os.dir(@FILE)), 'en')
	mut ui := new_flet(&t)
	id := ui.id('panel_body')
	ui.set_id(id, 'audio-fixture', 1)
	ui.set_id(id, 'audio-fixture', 2)
	operations := ui.pending[id] or { []json2.Any{} }
	assert operations.len == 1
	assert list_value(operations[0]) == [json2.Any(1), 0, 'audio-fixture', 2]
	first := ui.create('Text', {
		'value': json2.Any('obsolete')
	})
	ui.set('panel_body', 'controls', [first])
	ui.prune()
	last := ui.create('Text', {
		'value': json2.Any('final')
	})
	ui.set('panel_body', 'controls', [last])
	ui.prune()
	assert get(object(first), '_i').int() !in ui.controls
	patches := ui.pending[id] or { []json2.Any{} }
	final_patch := patches.filter(text_value(list_value(it)[2]) == 'controls')
	assert final_patch.len == 1
	assert json_encode(ui.expand(final_patch[0])).contains('final')
	assert !json_encode(ui.expand(final_patch[0])).contains('obsolete')
	mut a := App{
		t:          t
		ui:         new_flet(&t)
		panel_mode: 'info'
	}
	a.fill_panel()
	assert_flat_control_children(a.ui.tree(a.ui.id('panel_body')))
}
