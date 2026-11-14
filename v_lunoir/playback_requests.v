module main

import os
import x.json2

// Completion-dependent UI/profile work stays on the main loop. The revision
// and token prevent replies for an earlier file or panel from changing it.
struct PlaybackAction {
	kind     string
	revision i64
	token    u64
	target   string
	name     string
	value    json2.Any
}

fn (mut a App) command_action(args []json2.Any, action PlaybackAction) bool {
	id := a.backend.command(args) or {
		a.notify(err.msg())
		return false
	}
	if id != 0 { a.playback_actions[id] = action }
	return true
}

fn (mut a App) read_property_action(name string, action PlaybackAction) {
	id := a.backend.read_property(name) or {
		log_native('mpv read ${name}: ${err.msg()}')
		return
	}
	a.playback_actions[id] = action
}

fn (mut a App) handle_backend_reply(event map[string]json2.Any) {
	id := u64(get(event, 'request_id').i64())
	action := a.playback_actions[id] or {
		// Ordinary property writes have no UI completion work, but errors must
		// still reach the native log just as synchronous write errors did.
		failure := text_value(get(event, 'error'))
		if failure != '' { log_native('mpv ${text_value(get(event, 'name'))}: ${failure}') }
		return
	}
	a.playback_actions.delete(id)
	if action.kind == 'picture-write' {
		a.picture_reply(action.token, text_value(get(event, 'error')))
		return
	}
	if action.kind == 'audio-output' {
		a.audio_output_reply(action.token, action.target, text_value(get(event, 'error')))
		return
	}
	if action.revision != a.revision { return }
	if action.kind.starts_with('restore-') && action.token != a.subtitle_restore_token { return }
	failure := text_value(get(event, 'error'))
	if failure != '' {
		if action.kind == 'info' { return }
		log_native('mpv ${text_value(get(event, 'name'))}: ${failure}')
		if action.kind !in ['info', 'restore-list', 'restore-subtitle'] { a.notify(failure) }
		if action.kind == 'restore-subtitle' { a.read_restore_tracks() }
		return
	}
	match action.kind {
		'screenshot' {
			a.notify(a.t.tr('toast.screenshotSaved'))
		}
		'save-audio' {
			a.profile.save_audio(action.target, action.value) or { log_native(err.msg()) }
		}
		'save-subtitle' {
			a.profile.save_subtitle(action.target, action.value) or { log_native(err.msg()) }
		}
		'info' {
			if a.panel_mode == 'info' && action.token == a.info_token {
				a.info_data[action.name] = get(event, 'data')
				a.info_dirty = true
			}
		}
		'restore-list' {
			a.restore_subtitles(list_value(get(event, 'data')))
		}
		'restore-subtitle' {
			a.read_restore_tracks()
		}
		'resume' {
			a.pending_resume = action.target
		}
		else {}
	}
}

fn (mut a App) read_restore_tracks() {
	a.read_property_action('track-list', PlaybackAction{
		kind:     'restore-list'
		revision: a.revision
		token:    a.subtitle_restore_token
	})
}

// Read after each attachment completes. Besides preserving selection order,
// this avoids adding a subtitle twice using an observer's older track list.
fn (mut a App) restore_subtitles(tracks []json2.Any) {
	for path in a.profile.subtitle_files(a.resume_target) {
		if path in a.subtitle_restore_attempted || (!is_url(path) && !os.exists(path)) { continue
		 }
		if tracks.any(text_value(get(object(it), 'external-filename')) == path
			&& text_value(get(object(it), 'type')) == 'sub')
		{
			continue
		}
		a.subtitle_restore_attempted << path
		if a.command_action([json2.Any('sub-add'), path, 'auto'], PlaybackAction{
			kind:     'restore-subtitle'
			revision: a.revision
			token:    a.subtitle_restore_token
		})
		{
			return
		}
	}
	saved := object(get(a.profile.subtitles, a.resume_target))
	match text_value(get(saved, 'type')) {
		'none' {
			a.try_set('sid', 'no')
		}
		'embedded' {
			if tracks.any(text_value(get(object(it), 'type')) == 'sub'
				&& !truth(get(object(it), 'external')) && get(object(it), 'id') == get(saved, 'id'))
			{
				a.try_set('sid', get(saved, 'id'))
			}
		}
		'external' {
			for value in tracks {
				track := object(value)
				if text_value(get(track, 'type')) == 'sub'
					&& text_value(get(track, 'external-filename')) == text_value(get(saved, 'path')) {
					a.try_set('sid', get(track, 'id'))
					break
				}
			}
		}
		else {}
	}
}
