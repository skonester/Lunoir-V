module main

import mpv
import os
import time

fn main() {
	if os.args.len != 2 {
		eprintln('usage: test_media <clip.mkv|tone.wav>')
		exit(2)
	}
	path := os.args[1]
	audio := path.to_lower().ends_with('.wav')
	m := mpv.new() or { panic(err) }
	defer { m.terminate_destroy() }
	for key, value in {
		'config':    'no'
		'vo':        'null'
		'ao':        'null'
		'terminal':  'no'
		'o':         path
		'of':        if audio {
			'wav'
		} else {
			'matroska'
		}
		'keep-open': 'no'
	} {
		m.set_option_string(key, value) or { panic(err) }
	}
	m.set_option_string(if audio { 'oac' } else { 'ovc' },
		if audio { 'pcm_s16le' } else { 'mjpeg' }) or { panic(err) }
	m.initialize() or { panic(err) }
	source := if audio {
		'av://lavfi:sine=frequency=440:duration=40'
	} else {
		'av://lavfi:testsrc=duration=40:size=320x240:rate=24'
	}
	m.command(['loadfile', source]) or { panic(err) }
	deadline := time.now().unix_milli() + 30000
	for time.now().unix_milli() < deadline {
		event := m.wait_event(0.05)
		if event.id == .end_file {
			if event.end_file().reason == .error { panic('Media fixture encoding failed') }
			if !os.is_file(path) { panic('Media fixture output is missing') }
			println(path)
			return
		}
	}
	panic('Media fixture encoding timed out')
}
