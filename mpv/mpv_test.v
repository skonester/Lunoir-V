module mpv

import os

// Synthetic test sources played through FFmpeg's lavfi, so the tests need no media files.
const test_video = 'av://lavfi:testsrc=duration=1:size=320x240:rate=25'
const test_video_long = 'av://lavfi:testsrc=duration=60:size=320x240:rate=25'

// headless returns an initialized instance with no audio or video output.
fn headless() &Mpv {
	m := new() or { panic(err) }
	m.set_option_string('vo', 'null') or { panic(err) }
	m.set_option_string('ao', 'null') or { panic(err) }
	m.initialize() or { panic(err) }
	return m
}

// wait_for waits up to 10 s for an event with the given id, handling hooks
// on the way, and fails on end_file or shutdown unless that is what is awaited.
fn wait_for(m &Mpv, id EventId) Event {
	for _ in 0 .. 200 {
		e := m.wait_event(0.05)
		if e.id == id {
			return e
		}
		match e.id {
			.hook {
				m.hook_continue(e.hook().id) or { panic(err) }
			}
			.end_file, .shutdown {
				panic('got ${e.id} while waiting for ${id}')
			}
			else {}
		}
	}
	panic('timed out waiting for ${id}')
}

fn test_lifecycle() {
	m := new()!
	assert m.api_version() >> 16 == 2
	m.set_option_string('vo', 'null')!
	m.set_option_string('ao', 'null')!
	m.initialize()!
	assert m.name() == 'main'
	assert m.id() > 0
	assert m.time_us() > 0
	assert m.time_ns() > m.time_us()
	m.terminate_destroy()
}

fn test_property_round_trip() {
	m := headless()
	defer {
		m.terminate_destroy()
	}
	m.set_property('pause', true)!
	assert m.get_property_flag('pause')! == true
	assert m.get_property('pause', .flag)! == Node(true)

	m.set_property('ab-loop-count', i64(3))!
	assert m.get_property_int('ab-loop-count')! == 3

	m.set_property('speed', 1.5)!
	assert m.get_property_double('speed')! == 1.5

	m.set_property('force-media-title', 'héllo')!
	assert m.get_property_string('force-media-title')! == 'héllo'
	assert m.get_property('force-media-title', .string)! == Node('héllo')

	// Composite values go through MPV_FORMAT_NODE.
	m.set_property('user-data/vmpv', {
		'list': Node([Node(i64(1)), Node('two')])
		'flag': Node(false)
	})!
	assert m.get_property_node('user-data/vmpv/list')! == Node([Node(i64(1)), Node('two')])
	m.del_property('user-data/vmpv')!
	m.get_property_node('user-data/vmpv') or {
		assert err is MpvError
		return
	}
	assert false, 'user-data/vmpv still exists after del_property'
}

fn test_string_accessors() {
	m := new()!
	m.set_option('force-media-title', 'via-option')!
	m.set_option_string('vo', 'null')!
	m.set_option_string('ao', 'null')!
	m.initialize()!
	defer {
		m.terminate_destroy()
	}
	assert m.get_property_string('force-media-title')! == 'via-option'
	m.set_property_string('force-media-title', 'via-string')!
	assert m.get_property_string('force-media-title')! == 'via-string'
	assert m.get_property_osd_string('force-media-title')! == 'via-string'
}

fn test_errors() {
	m := headless()
	defer {
		m.terminate_destroy()
	}
	m.get_property_double('no-such-property') or {
		assert err is MpvError
		if err is MpvError {
			assert err.kind() == .property_not_found
			assert err.code() == -8
			assert err.msg() == 'property not found'
		}
		return
	}
	assert false, 'expected an error'
}

fn test_events_hook_and_track_list() {
	m := new()!
	m.set_option_string('vo', 'null')!
	m.set_option_string('ao', 'null')!
	m.set_option_string('pause', 'yes')!
	m.request_log_messages('info')!
	m.observe_property(1, 'width', .int64)!
	m.hook_add(2, 'on_load', 0)!
	m.initialize()!
	defer {
		m.terminate_destroy()
	}
	m.command(['loadfile', test_video])!

	mut seen := map[EventId]int{}
	mut hook_before_load := false
	mut width := i64(0)
	mut entry_id := i64(-1)
	mut got_log := false
	for _ in 0 .. 200 {
		e := m.wait_event(0.05)
		seen[e.id]++
		match e.id {
			.start_file {
				entry_id = e.start_file().playlist_entry_id
			}
			.hook {
				h := e.hook()
				assert h.name == 'on_load'
				hook_before_load = seen[.file_loaded] == 0
				m.hook_continue(h.id)!
			}
			.property_change {
				p := e.property()
				assert e.reply_userdata == 1
				assert p.name == 'width'
				if p.data is i64 {
					width = p.data
				}
			}
			.log_message {
				l := e.log_message()
				got_log = got_log || (l.prefix != '' && l.text != '' && !l.text.ends_with('\n'))
			}
			else {}
		}

		if seen[.file_loaded] > 0 && width > 0 {
			break
		}
	}
	assert hook_before_load
	assert entry_id > 0
	assert got_log
	assert width == 320

	tracks := m.get_property_node('track-list')!
	assert tracks is []Node
	if tracks is []Node {
		assert tracks.len > 0
		first := tracks[0]
		assert first is map[string]Node
		if first is map[string]Node {
			assert first['type'] or { Node(NodeNone{}) } == Node('video')
		}
	}
	assert m.get_property_osd_string('width')! == '320'
}

fn test_end_file_eof() {
	m := headless()
	defer {
		m.terminate_destroy()
	}
	m.command(['loadfile', test_video])!
	e := wait_for(m, .file_loaded)
	assert e.id == .file_loaded
	for _ in 0 .. 200 {
		ev := m.wait_event(0.05)
		if ev.id == .end_file {
			ef := ev.end_file()
			assert ef.reason == .eof
			assert ef.error == 0
			return
		}
	}
	assert false, 'no end_file event'
}

fn test_client_message() {
	m := headless()
	defer {
		m.terminate_destroy()
	}
	m.command_string('script-message hello world')!
	e := wait_for(m, .client_message)
	assert e.client_message() == ['hello', 'world']
	assert e.to_node() == Node({
		'event': Node('client-message')
		'args':  Node([Node('hello'), Node('world')])
	})
}

fn test_commands_with_results() {
	m := headless()
	defer {
		m.terminate_destroy()
	}
	m.set_property('force-media-title', 'vmpv')!
	assert m.command_ret(['expand-text', '\${force-media-title}'])! == Node('vmpv')
	assert m.command_node([Node('expand-text'), Node('\${force-media-title}')])! == Node('vmpv')
	// Named arguments.
	assert m.command_node({
		'name': Node('expand-text')
		'text': Node('[\${force-media-title}]')
	})! == Node('[vmpv]')
	m.command(['no-such-command']) or {
		assert err is MpvError
		return
	}
	assert false, 'expected an error for an unknown command'
}

fn test_async() {
	m := headless()
	defer {
		m.terminate_destroy()
	}
	m.set_property_async(10, 'speed', 2.0)!
	m.get_property_async(11, 'speed', .double)!
	m.command_async(12, ['expand-text', 'async'])!
	m.command_node_async(13, [Node('expand-text'), Node('node-async')])!
	m.get_property_async(14, 'no-such-property', .double)!
	m.wait_async_requests()

	mut done := map[u64]bool{}
	for _ in 0 .. 100 {
		e := m.wait_event(0.05)
		match e.reply_userdata {
			10 {
				assert e.id == .set_property_reply
				e.check()!
			}
			11 {
				assert e.id == .get_property_reply
				assert e.property().data == Node(2.0)
			}
			12 {
				assert e.id == .command_reply
				assert e.command_reply() == Node('async')
			}
			13 {
				assert e.command_reply() == Node('node-async')
			}
			14 {
				assert e.error == int(ErrorCode.property_not_found)
				e.check() or { assert err is MpvError }
			}
			else {}
		}

		if e.reply_userdata in [u64(10), 11, 12, 13, 14] {
			done[e.reply_userdata] = true
		}
		if done.len == 5 {
			break
		}
	}
	assert done.len == 5, 'replies received: ${done.keys()}'
}

fn test_abort_async_command() {
	m := headless()
	defer {
		m.terminate_destroy()
	}
	// subprocess is abortable; a long-running ping/timeout keeps it busy.
	args := $if windows {
		[Node('ping'), Node('-n'), Node('30'), Node('127.0.0.1')]
	} $else {
		[Node('sleep'), Node('30')]
	}
	m.command_node_async(20, {
		'name':           Node('subprocess')
		'args':           Node(args)
		'playback_only':  Node(false)
		'capture_stdout': Node(true)
	})!
	// An abort that reaches mpv before the command has started is ignored,
	// so repeat it until the reply arrives.
	for _ in 0 .. 200 {
		m.abort_async_command(20)
		e := m.wait_event(0.05)
		if e.id != .command_reply {
			continue
		}
		assert e.reply_userdata == 20
		reply := e.command_reply()
		if reply is map[string]Node {
			assert reply['killed_by_us'] or { Node(false) } == Node(true)
		} else {
			assert false, 'unexpected reply ${reply}'
		}
		return
	}
	assert false, 'no command_reply after abort'
}

fn test_unobserve_and_request_event() {
	m := headless()
	defer {
		m.terminate_destroy()
	}
	m.observe_property(5, 'speed', .double)!
	m.observe_property(5, 'pause', .flag)!
	assert m.unobserve_property(5)! == 2
	m.request_event(.client_message, false)!
	m.command_string('script-message ignored')!
	m.request_event(.client_message, true)!
	m.command_string('script-message seen')!
	e := wait_for(m, .client_message)
	assert e.client_message() == ['seen']
}

fn test_clients() {
	m := headless()
	defer {
		m.terminate_destroy()
	}
	c := m.create_client('second')!
	assert c.name() == 'second'
	assert c.id() != m.id()
	c.set_property('speed', 1.25)!
	assert m.get_property_double('speed')! == 1.25
	c.destroy()

	w := m.create_weak_client('weak')!
	assert w.name() == 'weak'
	assert w.get_property_double('speed')! == 1.25
	w.destroy()
}

fn test_load_config_file() {
	path := os.join_path(os.temp_dir(), 'vmpv_test_${os.getpid()}.conf')
	os.write_file(path, 'force-media-title=from-config\n')!
	defer {
		os.rm(path) or {}
	}
	m := new()!
	m.set_option_string('vo', 'null')!
	m.set_option_string('ao', 'null')!
	m.load_config_file(path)!
	m.initialize()!
	defer {
		m.terminate_destroy()
	}
	assert m.get_property_string('force-media-title')! == 'from-config'
	m.load_config_file(path + '.missing') or {
		assert err is MpvError
		return
	}
	assert false, 'expected an error for a missing config file'
}

@[heap]
struct Counter {
mut:
	hits int
}

fn count_wakeup(data voidptr) {
	mut c := unsafe { &Counter(data) }
	c.hits++
}

fn test_wakeup_callback() {
	m := headless()
	defer {
		m.terminate_destroy()
	}
	mut c := &Counter{}
	m.set_wakeup_callback(count_wakeup, c)
	m.command_string('script-message ping')!
	wait_for(m, .client_message)
	m.set_wakeup_callback(unsafe { nil }, unsafe { nil })
	assert c.hits > 0
	assert m.wakeup_pipe() >= 0
	m.wakeup()
	assert m.wait_event(1.0).id == .none
}

fn test_seek_and_playback_events() {
	m := headless()
	defer {
		m.terminate_destroy()
	}
	m.set_property('pause', true)!
	m.command(['loadfile', test_video_long])!
	wait_for(m, .file_loaded)
	m.command(['seek', '5', 'absolute'])!
	wait_for(m, .seek)
	wait_for(m, .playback_restart)
	assert m.get_property_double('time-pos')! >= 4.9
}

fn render_instance() &Mpv {
	m := new() or { panic(err) }
	m.set_option_string('vo', 'libmpv') or { panic(err) }
	m.set_option_string('ao', 'null') or { panic(err) }
	m.initialize() or { panic(err) }
	return m
}

fn test_render_sw() {
	m := render_instance()
	defer {
		m.terminate_destroy()
	}
	mut rc := m.new_render_context_sw()!
	defer {
		rc.free()
	}
	mut c := &Counter{}
	rc.set_update_callback(count_wakeup, c)
	m.command(['loadfile', test_video_long])!
	wait_for(m, .file_loaded)

	w, h, stride := 320, 240, 320 * 4
	mut buf := []u8{len: stride * h}
	// The first frames may be black; render until one has content.
	for _ in 0 .. 200 {
		if rc.update() & render_update_frame != 0 {
			rc.render_sw(w, h, stride, 'rgb0', mut buf)!
			if buf.any(it != 0) {
				rc.set_update_callback(unsafe { nil }, unsafe { nil })
				assert c.hits > 0
				return
			}
		}
		m.wait_event(0.05)
	}
	assert false, 'no non-black frame rendered'
}

fn test_render_sw_rejects_small_buffer() {
	m := render_instance()
	defer {
		m.terminate_destroy()
	}
	mut rc := m.new_render_context_sw()!
	defer {
		rc.free()
	}
	mut buf := []u8{len: 16}
	rc.render_sw(320, 240, 320 * 4, 'rgb0', mut buf) or {
		assert err is MpvError
		return
	}
	assert false, 'expected an error for a too-small buffer'
}

fn test_render_free_twice() {
	m := render_instance()
	defer {
		m.terminate_destroy()
	}
	mut rc := m.new_render_context_sw()!
	rc.free()
	rc.free()
}
