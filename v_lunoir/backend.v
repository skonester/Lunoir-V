module main

import mpv
import os
import strconv
import x.json2

const observed_properties = ['pause', 'time-pos', 'duration', 'volume', 'mute', 'speed', 'filename',
	'media-title', 'metadata/by-key/uploader', 'eof-reached', 'ab-loop-a', 'ab-loop-b', 'seekable',
	'path', 'chapter', 'chapter-list', 'video-params/aspect', 'track-list', 'aid', 'sid',
	'audio-delay', 'sub-delay', 'sub-pos', 'sub-scale', 'container-fps', 'estimated-frame-count',
	'estimated-frame-number', 'video-params/gamma', 'video-params/w', 'video-params/h',
	'audio-codec-name', 'audio-params/channel-count', 'audio-device']

struct MpvController {
mut:
	handle     &mpv.Mpv = unsafe { nil }
	serial     u64      = u64(1) << 32
	active     MpvRequest
	queued     []MpvRequest
	replies    []map[string]json2.Any
	cancelling bool
}

// Observer ids occupy the low range. Requests use a separate, monotonically
// increasing range on each controller, including after it is reopened.
const max_mpv_requests = 256

struct MpvRequest {
	id       u64
	kind     string
	name     string
	args     []json2.Any
	value    json2.Any
	coalesce bool
}

fn mpv_api_label() string {
	version := mpv.client_api_version()
	return '${version >> 16}.${version & 0xffff}'
}

fn node_value(node mpv.Node) json2.Any {
	return match node {
		mpv.NodeNone {
			json2.Any(json2.Null{})
		}
		string {
			json2.Any(node)
		}
		bool {
			json2.Any(node)
		}
		i64 {
			json2.Any(node)
		}
		f64 {
			json2.Any(node)
		}
		[]u8 {
			json2.Any(node.bytestr())
		}
		[]mpv.Node {
			json2.Any(node.map(node_value(it)))
		}
		map[string]mpv.Node {
			mut result := map[string]json2.Any{}
			for key, value in node {
				result[key] = node_value(value)
			}
			json2.Any(result)
		}
	}
}

fn mpv_node(value json2.Any) mpv.Node {
	return match value {
		json2.Null {
			mpv.Node(mpv.NodeNone{})
		}
		string {
			mpv.Node(value)
		}
		bool {
			mpv.Node(value)
		}
		f64 {
			mpv.Node(value)
		}
		f32 {
			mpv.Node(f64(value))
		}
		[]json2.Any {
			mpv.Node(value.map(mpv_node(it)))
		}
		map[string]json2.Any {
			mut result := map[string]mpv.Node{}
			for key, child in value {
				result[key] = mpv_node(child)
			}
			mpv.Node(result)
		}
		else {
			mpv.Node(value.i64())
		}
	}
}

fn (mut b MpvController) start(wid voidptr, extra []string, observe bool) ! {
	b.handle = mpv.new()!
	mut initialized := false
	defer {
		if !initialized {
			b.handle.terminate_destroy()
			b.handle = unsafe { nil }
		}
	}
	options := ['no-config', 'idle=yes', 'keep-open=yes', 'no-osc', 'no-osd-bar', 'vo=gpu-next',
		'hwdec=auto', 'volume-max=150', 'input-default-bindings=no', 'input-vo-keyboard=no',
		'input-cursor=no', 'terminal=no']
	for option in options {
		b.option(option)!
	}
	if !isnil(wid) { b.handle.set_option_string('wid', strconv.format_uint(u64(wid), 10))! }
	for option in extra {
		b.option(option.trim_left('-'))!
	}
	if logfile := os.getenv_opt('LUNOIR_V_MPV_LOG') {
		b.handle.set_option_string('log-file', logfile)!
		b.handle.set_option_string('msg-level', 'all=warn,ytdl_hook=debug')!
	}
	b.handle.initialize()!
	initialized = true
	b.handle.request_log_messages('warn')!
	if observe {
		for i, name in observed_properties {
			b.handle.observe_property(u64(i + 1), name, .node)!
		}
		for i, name in diagnostic_properties {
			b.handle.observe_property(u64(1000 + i), name, .node)!
		}
	}
}

fn (b &MpvController) option(option string) ! {
	mut name, mut value := option.split_once('=') or { option, 'yes' }
	if name.starts_with('no-') {
		name = name[3..]
		value = 'no'
	}
	b.handle.set_option_string(name, value)!
}

fn (mut b MpvController) command(args []json2.Any) !u64 {
	if isnil(b.handle) { return error('The playback backend is disconnected') }
	if args.len == 0 { return error('Empty playback command') }
	name := text_value(args[0])
	if name == 'get_property' && args.len > 1 {
		return b.read_property(text_value(args[1]))
	}
	if name == 'set_property' && args.len > 2 {
		return b.set_property(text_value(args[1]), args[2])
	}
	if name == 'request_log_messages' && args.len > 1 {
		b.handle.request_log_messages(text_value(args[1]))!
		return 0
	}
	return b.enqueue(MpvRequest{ kind: 'command', name: name, args: args.clone() })
}

// Synchronous reads are reserved for explicit diagnostic snapshots/tests.
// Runtime UI code uses observers or read_property and handles its reply.
fn (b &MpvController) get_property(name string) json2.Any {
	if isnil(b.handle) { return json2.Null{} }
	return node_value(b.handle.get_property_node(name) or { return json2.Null{} })
}

fn (mut b MpvController) set_property(name string, value json2.Any) !u64 {
	if isnil(b.handle) { return error('The playback backend is disconnected') }
	// A slider can outpace the core. Replace an unsent write to the same
	// property, without crossing a command/read that depends on its value.
	for i := b.queued.len - 1; i >= 0; i-- {
		if b.queued[i].kind != 'set' || !b.queued[i].coalesce { break
		 }
		if b.queued[i].name == name {
			b.queued[i] = MpvRequest{
				...b.queued[i]
				value: value
			}
			return b.queued[i].id
		}
	}
	return b.enqueue(MpvRequest{ kind: 'set', name: name, value: value, coalesce: true })
}

// A write with completion-dependent profile work must keep its own reply.
fn (mut b MpvController) set_property_tracked(name string, value json2.Any) !u64 {
	if isnil(b.handle) { return error('The playback backend is disconnected') }
	return b.enqueue(MpvRequest{ kind: 'set', name: name, value: value })
}

fn (mut b MpvController) read_property(name string) !u64 {
	if isnil(b.handle) { return error('The playback backend is disconnected') }
	return b.enqueue(MpvRequest{ kind: 'get', name: name })
}

fn (mut b MpvController) enqueue(request MpvRequest) !u64 {
	if b.queued.len >= max_mpv_requests { return error('Too many pending playback requests') }
	b.serial++
	b.queued << MpvRequest{
		...request
		id: b.serial
	}
	b.send_next()
	return b.serial
}

fn mpv_reply(request MpvRequest, failure string, data json2.Any) map[string]json2.Any {
	return {
		'event':      json2.Any('backend-reply')
		'request_id': i64(request.id)
		'kind':       request.kind
		'name':       request.name
		'args':       request.args
		'error':      failure
		'data':       data
	}
}

// client.h permits async calls to be reordered. Keep one request in flight so
// option -> load, seek -> unpause, and attachment -> track read retain their
// original ordering, without waiting on the mpv core on the UI thread.
fn (mut b MpvController) send_next() {
	for b.active.id == 0 && b.queued.len > 0 {
		request := b.queued[0]
		b.queued.delete(0)
		b.active = request
		b.send_request(request) or {
			b.replies << mpv_reply(request, err.msg(), json2.Null{})
			b.active = MpvRequest{}
			continue
		}
	}
}

fn (b &MpvController) send_request(request MpvRequest) ! {
	match request.kind {
		'set' { b.handle.set_property_async(request.id, request.name, mpv_node(request.value))! }
		'get' { b.handle.get_property_async(request.id, request.name, .node)! }
		else { b.handle.command_node_async(request.id, mpv_node(request.args))! }
	}
}

fn (mut b MpvController) complete(id u64, failure string, data json2.Any) map[string]json2.Any {
	if id == 0 || id != b.active.id { return map[string]json2.Any{} }
	reply := mpv_reply(b.active, failure, data)
	b.active = MpvRequest{}
	b.cancelling = false
	return reply
}

fn (mut b MpvController) cancel_pending() {
	for request in b.queued {
		b.replies << mpv_reply(request, 'Playback request cancelled', json2.Null{})
	}
	b.queued.clear()
	b.cancelling = b.active.id != 0 && b.active.kind == 'command'
}

// Changing files must be able to interrupt a slow attachment/screenshot.
// Keep option writes: the next load still needs startup and quality settings.
fn (mut b MpvController) cancel_commands() {
	mut retained := []MpvRequest{}
	for request in b.queued {
		if request.kind == 'set' {
			retained << request
		} else {
			b.replies << mpv_reply(request, 'Playback request cancelled', json2.Null{})
		}
	}
	b.queued = retained
	b.cancelling = b.active.id != 0 && b.active.kind == 'command'
}

fn (mut b MpvController) events() []map[string]json2.Any {
	mut result := []map[string]json2.Any{}
	if isnil(b.handle) { return result }
	for _ in 0 .. 1000 {
		// Abort may arrive before mpv starts the command. Repeat until its reply
		// releases the active slot instead of assuming a single abort worked.
		if b.cancelling { b.handle.abort_async_command(b.active.id) }
		b.send_next()
		result << b.replies
		b.replies.clear()
		event := b.handle.wait_event(0)
		if event.id == .none { break
		 }
		if event.id in [.command_reply, .set_property_reply, .get_property_reply] {
			mut data := json2.Any(json2.Null{})
			if event.error >= 0 && !isnil(event.data) {
				if event.id == .command_reply { data = node_value(event.command_reply()) }
				if event.id == .get_property_reply { data = node_value(event.property().data) }
			}
			failure := if event.error < 0 { mpv.error_string(event.error) } else { '' }
			reply := b.complete(event.reply_userdata, failure, data)
			if reply.len > 0 { result << reply }
			continue
		}
		result << object(node_value(event.to_node()))
	}
	return result
}

fn (mut b MpvController) close() {
	b.queued.clear()
	b.replies.clear()
	b.active = MpvRequest{}
	b.cancelling = false
	if !isnil(b.handle) {
		b.handle.terminate_destroy()
		b.handle = unsafe { nil }
	}
}
