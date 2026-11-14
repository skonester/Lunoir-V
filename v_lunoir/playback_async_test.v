module main

import os
import time
import x.json2

// This file never loads media or creates a window. The real-core check uses
// an idle null-output instance; the remaining checks supply replies/state.
fn collect_playback_replies(mut b MpvController, ids []u64) map[u64]map[string]json2.Any {
	mut replies := map[u64]map[string]json2.Any{}
	deadline := time.now().unix_milli() + 3000
	for replies.len < ids.len && time.now().unix_milli() < deadline {
		for event in b.events() {
			id := u64(get(event, 'request_id').i64())
			if text_value(get(event, 'event')) == 'backend-reply' && id in ids {
				replies[id] = event.clone()
			}
		}
		time.sleep(time.millisecond)
	}
	assert replies.len == ids.len
	return replies
}

fn test_async_backend_preserves_dependencies_and_reports_errors_without_media() {
	mut b := MpvController{}
	b.start(unsafe { nil }, ['vo=null', 'ao=null'], false)!
	defer { b.close() }
	first := b.set_property('volume', 11)!
	second := b.set_property('volume', 22)!
	assert b.set_property('volume', 33)! == second
	barrier := b.command([json2.Any('expand-text'), r'${volume}'])!
	last := b.set_property('volume', 44)!
	read := b.read_property('volume')!
	bad := b.set_property('lunoir-test-nonexistent-property', true)!
	assert first > u64(1) << 32
	assert last != second
	replies := collect_playback_replies(mut b, [first, second, barrier, last, read, bad])
	assert text_value(get(replies[barrier], 'data')).f64() == 33
	assert number(get(replies[read], 'data')) == 44
	assert text_value(get(replies[bad], 'error')) != ''
	assert text_value(get(replies[bad], 'name')) == 'lunoir-test-nonexistent-property'
	assert b.active.id == 0 && b.queued.len == 0
	// A rejected request must not stop subsequent work.
	after_error := b.command([json2.Any('expand-text'), 'still responsive'])!
	result := collect_playback_replies(mut b, [after_error])
	assert text_value(get(result[after_error], 'data')) == 'still responsive'
	// Invalid commands can be rejected by the submission call itself, without
	// a native reply event. They still need exactly one correlated completion.
	invalid := b.command([json2.Any('lunoir-test-nonexistent-command')])!
	missing := b.read_property('lunoir-test-nonexistent-property')!
	rejected := collect_playback_replies(mut b, [invalid, missing])
	assert text_value(get(rejected[invalid], 'error')) != ''
	assert text_value(get(rejected[missing], 'error')) != ''
	assert get(rejected[missing], 'data') is json2.Null
}

fn test_async_backend_ignores_unrelated_replies_and_bounds_queued_work() {
	mut b := MpvController{
		active: MpvRequest{
			id:   55
			kind: 'command'
			name: 'seek'
		}
	}
	assert b.complete(1, '', json2.Null{}).len == 0
	assert b.active.id == 55
	for _ in 0 .. max_mpv_requests {
		b.enqueue(MpvRequest{ kind: 'get', name: 'volume' })!
	}
	if _ := b.enqueue(MpvRequest{ kind: 'get', name: 'volume' }) {
		assert false, 'The request queue must be bounded'
	}
	b.cancel_pending()
	assert b.queued.len == 0 && b.cancelling
	assert b.replies.len == max_mpv_requests
	assert b.complete(55, 'cancelled', json2.Null{}).len > 0
	assert !b.cancelling && b.active.id == 0
	assert b.complete(55, '', json2.Null{}).len == 0
	// A new queue item drops stale reads/commands while retaining its options.
	b.active = MpvRequest{
		id:   56
		kind: 'command'
		name: 'audio-add'
	}
	b.queued = [MpvRequest{ id: 57, kind: 'get', name: 'track-list' },
		MpvRequest{ id: 58, kind: 'set', name: 'ytdl-format', value: 'best' },
		MpvRequest{ id: 59, kind: 'command', name: 'sub-add' }]
	b.cancel_commands()
	assert b.cancelling && b.queued.len == 1 && b.queued[0].id == 58
}

fn test_playback_side_effects_wait_for_success_and_ignore_stale_replies() {
	directory := os.join_path(os.temp_dir(), 'lunoir-async-state-${time.now().unix_micro()}')
	previous_logs := os.getenv('LOCALAPPDATA')
	os.setenv('LOCALAPPDATA', directory, true)
	defer {
		os.setenv('LOCALAPPDATA', previous_logs, true)
		os.rmdir_all(directory) or {}
	}
	t := new_translator(os.dir(os.dir(@FILE)), 'en')
	mut a := App{
		t:        t
		ui:       new_flet(&t)
		profile:  new_profile(directory)
		revision: 2
	}
	selection := json2.Any({
		'type': json2.Any('external')
		'path': 'saved.srt'
	})
	a.playback_actions[60] = PlaybackAction{
		kind:     'save-subtitle'
		revision: 2
		target:   'film.mkv'
		value:    selection
	}
	assert 'film.mkv' !in a.profile.subtitles
	a.handle_backend_reply(mpv_reply(MpvRequest{ id: 60, name: 'sub-add' }, 'rejected', json2.Null{}))
	assert 'film.mkv' !in a.profile.subtitles
	assert !os.is_file(os.join_path(directory, 'subtitle-selections.json'))
	a.playback_actions[61] = PlaybackAction{
		kind:     'save-subtitle'
		revision: 1
		target:   'old.mkv'
		value:    selection
	}
	a.handle_backend_reply(mpv_reply(MpvRequest{ id: 61 }, '', json2.Null{}))
	assert 'old.mkv' !in a.profile.subtitles
	a.playback_actions[62] = PlaybackAction{
		kind:     'save-subtitle'
		revision: 2
		target:   'film.mkv'
		value:    selection
	}
	a.handle_backend_reply(mpv_reply(MpvRequest{ id: 62 }, '', json2.Null{}))
	assert a.profile.subtitle_files('film.mkv') == ['saved.srt']
	assert os.is_file(os.join_path(directory, 'subtitle-selections.json'))
	a.toast_until = 0
	a.playback_actions[63] = PlaybackAction{
		kind:     'screenshot'
		revision: 2
	}
	assert a.toast_until == 0
	a.handle_backend_reply(mpv_reply(MpvRequest{ id: 63 }, '', json2.Null{}))
	assert text_value(a.ui.prop('toast_text', 'value')) == a.t.tr('toast.screenshotSaved')
	assert a.playback_actions.len == 0
	// Reopening Info or changing subtitle selection invalidates older work.
	a.panel_mode = 'info'
	a.info_token = 3
	a.playback_actions[64] = PlaybackAction{
		kind:     'info'
		revision: 2
		token:    2
		name:     'duration'
	}
	a.handle_backend_reply(mpv_reply(MpvRequest{ id: 64 }, '', 99))
	assert a.info_data.len == 0
	a.subtitle_restore_token = 4
	a.playback_actions[65] = PlaybackAction{
		kind:     'restore-list'
		revision: 2
		token:    3
	}
	a.handle_backend_reply(mpv_reply(MpvRequest{ id: 65 }, '', []json2.Any{}))
	assert a.playback_actions.len == 0
}

fn test_preview_watchdog_resets_each_wait_and_limits_recovery() {
	directory := os.join_path(os.temp_dir(), 'lunoir-preview-state-${time.now().unix_micro()}')
	previous_logs := os.getenv('LOCALAPPDATA')
	os.setenv('LOCALAPPDATA', directory, true)
	defer {
		os.setenv('LOCALAPPDATA', previous_logs, true)
		os.rmdir_all(directory) or {}
	}
	for stage in [PreviewStage.loading, .warming, .pausing, .seeking] {
		mut p := Thumbnails{
			enabled:    true
			loaded:     'state-only.mkv'
			stage:      stage
			deadline:   100
			visible:    true
			file_ready: true
			has_frame:  true
			queued:     17
			requested:  17
		}
		p.watchdog(99)
		assert p.stage == stage && p.retries == 0
		p.watchdog(100)
		assert p.stage == .idle && p.deadline == 0
		assert p.enabled && p.retries == 1 && p.retry_at == 350
		assert !p.visible && !p.file_ready && !p.has_frame
		assert p.queued == -1 && p.requested == -1
		// The retry gets its own deadline; failure then stops automatic retries.
		p.retry_at = 0
		p.stage = stage
		p.deadline = 500
		p.watchdog(500)
		assert !p.enabled && p.retry_at == 0 && p.retries == 1
		p.sync_file('')!
		assert p.loaded == '' && p.stage == .idle
	}
}

fn test_preview_waits_for_current_load_and_pause_acknowledgement() {
	mut p := Thumbnails{
		enabled:        true
		stage:          .loading
		awaiting_start: true
		deadline:       100
		load_id:        70
	}
	p.handle_event({
		'event': json2.Any('playback-restart')
	}, 10)
	assert !p.file_ready && p.stage == .loading
	p.handle_event({
		'event': json2.Any('start-file')
	}, 11)
	p.handle_event({
		'event': json2.Any('playback-restart')
	}, 12)
	assert p.file_ready && p.stage == .idle && p.deadline == 0
	p.stage = .pausing
	p.pause_id = 72
	p.deadline = 100
	p.handle_event(mpv_reply(MpvRequest{ id: 69 }, 'old failure', json2.Null{}), 13)
	assert p.stage == .pausing && p.retries == 0
	p.handle_event(mpv_reply(MpvRequest{ id: 71 }, '', json2.Null{}), 14)
	assert !p.has_frame
	p.handle_event(mpv_reply(MpvRequest{ id: 72 }, '', json2.Null{}), 15)
	assert p.has_frame && p.stage == .idle && p.deadline == 0
}
