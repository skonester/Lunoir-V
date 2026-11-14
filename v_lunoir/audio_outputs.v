module main

import mpv
import x.json2

struct AudioOutputDevice {
	name        string
	description string
}

struct AudioDeviceResult {
	generation u64
	devices    []AudioOutputDevice
	error      string
}

struct AudioPendingOpen {
	paths  []string
	target string
	agent  string
}

struct AudioOutputs {
mut:
	devices        []AudioOutputDevice
	known          bool
	reading        bool
	worker         thread
	worker_started bool
	results        chan AudioDeviceResult = chan AudioDeviceResult{cap: 1}
	generation     u64
	restored       bool
	changing       bool
	selection      u64
	pending        string
	previous       string
	notice         string
	pending_open   AudioPendingOpen
}

fn parse_audio_devices(value json2.Any) ![]AudioOutputDevice {
	if value !is []json2.Any { return error('Invalid audio device list') }
	mut devices := [AudioOutputDevice{ name: 'auto' }]
	mut seen := {
		'auto': true
	}
	for item in list_value(value) {
		record := object(item)
		name := get(record, 'name')
		if name !is string { continue
		 }
		id := text_value(name)
		if id == '' || id in seen { continue
		 }
		seen[id] = true
		description := get(record, 'description')
		label := if description is string { text_value(description) } else { '' }
		devices << AudioOutputDevice{id, if label == '' { id } else { label }}
	}
	return devices
}

fn enumerate_audio_devices(parent &mpv.Mpv) ![]AudioOutputDevice {
	// This client has its own event queue. Discovery cannot consume playback
	// replies/observers, and its potentially slow AO read runs on the V worker.
	client := parent.create_weak_client('audio-devices')!
	defer { client.destroy() }
	return parse_audio_devices(node_value(client.get_property_node('audio-device-list')!))
}

fn audio_device_worker(parent &mpv.Mpv, results chan AudioDeviceResult, generation u64) {
	devices := enumerate_audio_devices(parent) or {
		results <- AudioDeviceResult{
			generation: generation
			error:      err.msg()
		}
		return
	}
	// enumerate_audio_devices has already destroyed its weak client here.
	results <- AudioDeviceResult{
		generation: generation
		devices:    devices
	}
}

fn (mut a App) start_audio_discovery(force bool) {
	if isnil(a.backend.handle) || a.audio_outputs.reading || a.audio_outputs.changing
		|| (a.audio_outputs.known && !force) {
		return
	}
	a.audio_outputs.reading = true
	a.audio_outputs.notice = ''
	a.audio_outputs.generation++
	a.audio_outputs.worker = spawn audio_device_worker(a.backend.handle, a.audio_outputs.results,
		a.audio_outputs.generation)
	a.audio_outputs.worker_started = true
}

fn (mut a App) poll_audio_devices() {
	if !a.audio_outputs.reading { return }
	select {
		result := <-a.audio_outputs.results {
			if result.generation != a.audio_outputs.generation { return }
			a.audio_outputs.worker.wait()
			a.audio_outputs.worker_started = false
			a.audio_outputs.reading = false
			a.accept_audio_devices(result)
		}
		else {}
	}
}

fn (mut a App) accept_audio_devices(result AudioDeviceResult) {
	a.audio_outputs.known = true
	if result.error != '' {
		log_native('Audio device discovery: ${result.error}')
		a.audio_outputs.notice = a.t.tr('audio.discoveryFailed')
	} else {
		a.audio_outputs.devices = result.devices.clone()
		// Restore a saved device only after discovery confirms it is present.
		// Refresh also catches a selected device that has been disconnected.
		saved := text_value(get(a.profile.settings, 'audioDevice'))
		current := text_value(get(a.properties, 'audio-device'))
		desired := if !a.audio_outputs.restored { saved } else { current }
		name := if desired == '' { 'auto' } else { desired }
		a.audio_outputs.restored = true
		if !a.audio_outputs.devices.any(it.name == name) {
			a.select_audio_output('auto')
			a.audio_outputs.notice = a.t.format('audio.unavailable', {
				'name': name
			})
		} else if name != current {
			a.select_audio_output(name)
		}
	}
	if a.panel_mode == 'settings' && a.settings_tab == 'playback' { a.panel_dirty = true }
}

fn (mut a App) select_audio_output(name string) {
	if a.audio_outputs.reading || a.audio_outputs.changing {
		a.notify(a.t.tr('audio.wait'))
		return
	}
	if name != 'auto' && !a.audio_outputs.devices.any(it.name == name) {
		a.notify(a.t.tr('audio.invalid'))
		return
	}
	id := a.backend.set_property_tracked('audio-device', name) or {
		a.notify(err.msg())
		return
	}
	a.audio_outputs.selection++
	a.audio_outputs.changing = true
	a.audio_outputs.pending = name
	a.audio_outputs.notice = ''
	current := text_value(get(a.properties, 'audio-device'))
	a.audio_outputs.previous = if current == '' { 'auto' } else { current }
	a.playback_actions[id] = PlaybackAction{
		kind:   'audio-output'
		token:  a.audio_outputs.selection
		target: name
	}
	if a.panel_mode == 'settings' && a.settings_tab == 'playback' { a.panel_dirty = true }
}

fn (mut a App) audio_output_reply(token u64, name string, failure string) {
	if token != a.audio_outputs.selection || !a.audio_outputs.changing { return }
	a.audio_outputs.changing = false
	a.audio_outputs.pending = ''
	if failure == '' {
		a.properties['audio-device'] = name
		a.queue_setting('audioDevice', name)
	} else {
		a.properties['audio-device'] = a.audio_outputs.previous
		a.try_set('audio-device', a.audio_outputs.previous)
		a.audio_outputs.notice = a.t.tr('audio.failed') + ': ' + failure
		log_native('Audio output ${name}: ${failure}')
		a.notify(a.audio_outputs.notice)
	}
	if a.panel_mode == 'settings' && a.settings_tab == 'playback' { a.panel_dirty = true }
}

fn (a &App) audio_output_ready() bool {
	if a.audio_outputs.changing { return false }
	preferred := text_value(get(a.profile.settings, 'audioDevice'))
	return preferred in ['', 'auto']
		|| (a.audio_outputs.known && (!a.audio_outputs.reading || a.audio_outputs.restored))
}

// Restore the output before the first file starts, without waiting on the UI
// thread or briefly sending the file to the default output during discovery.
fn (mut a App) defer_audio_open(paths []string, target string, agent string) bool {
	if a.audio_output_ready() { return false }
	a.audio_outputs.pending_open = AudioPendingOpen{
		paths:  paths.clone()
		target: target
		agent:  agent
	}
	return true
}

fn (mut a App) resume_audio_open() {
	if a.closed || !a.audio_output_ready() { return }
	pending := a.audio_outputs.pending_open
	a.audio_outputs.pending_open = AudioPendingOpen{}
	if pending.paths.len > 0 {
		a.open_paths(pending.paths)
	} else if pending.target != '' {
		a.open_target_path(pending.target, pending.agent)
	}
}

fn (mut o AudioOutputs) close() {
	if o.worker_started {
		o.worker.wait()
		o.worker_started = false
	}
	o.reading = false
	o.pending_open = AudioPendingOpen{}
}

fn (mut a App) audio_output_panel() []json2.Any {
	busy := a.audio_outputs.reading || a.audio_outputs.changing
	mut options := [
		a.ui.create('DropdownOption', {
			'key':  json2.Any('auto')
			'text': a.t.tr('audio.default')
		}),
	]
	for device in a.audio_outputs.devices {
		if device.name == 'auto' { continue
		 }
		options << a.ui.create('DropdownOption', {
			'key':  json2.Any(device.name)
			'text': device.description
		})
	}
	current := text_value(get(a.properties, 'audio-device'))
	selected := if a.audio_outputs.changing {
		a.audio_outputs.pending
	} else if current != '' {
		current
	} else {
		'auto'
	}
	mut choice := selected
	if selected != 'auto' && !a.audio_outputs.devices.any(it.name == selected) { choice = 'auto' }
	picker := a.ui.create('Dropdown', {
		'label':     json2.Any(a.t.tr('audio.device'))
		'value':     choice
		'options':   options
		'width':     272
		'text_size': 12
		'dense':     true
		'disabled':  busy
	})
	a.ui.bind(picker, 'select', 'audio_output_select', []json2.Any{})
	refresh := a.button(a.t.tr('audio.refresh'), 'audio_output_refresh', []json2.Any{})
	a.ui.set_id(get(object(refresh), '_i').int(), 'disabled', busy)
	mut body := [a.section(a.t.tr('audio.title')), picker, refresh,
		a.text(a.t.tr('audio.hint'), 11, '#92929C')]
	if a.audio_outputs.reading { body << a.text(a.t.tr('audio.scanning'), 11, '#92929C') }
	if a.audio_outputs.notice != '' { body << a.text(a.audio_outputs.notice, 11, '#92929C') }
	return body
}
