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
	'audio-codec-name', 'audio-params/channel-count']

struct MpvController {
mut:
	handle &mpv.Mpv = unsafe { nil }
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

fn (b &MpvController) command(args []json2.Any) !json2.Any {
	if isnil(b.handle) { return error('The playback backend is disconnected') }
	if args.len == 0 { return error('Empty playback command') }
	name := text_value(args[0])
	if name == 'get_property' && args.len > 1 {
		return node_value(b.handle.get_property_node(text_value(args[1]))!)
	}
	if name == 'set_property' && args.len > 2 {
		b.handle.set_property(text_value(args[1]), mpv_node(args[2]))!
		return json2.Null{}
	}
	if name == 'request_log_messages' && args.len > 1 {
		b.handle.request_log_messages(text_value(args[1]))!
		return json2.Null{}
	}
	return node_value(b.handle.command_node(mpv_node(args))!)
}

fn (b &MpvController) get_property(name string) json2.Any {
	if isnil(b.handle) { return json2.Null{} }
	return node_value(b.handle.get_property_node(name) or { return json2.Null{} })
}

fn (b &MpvController) set_property(name string, value json2.Any) ! {
	if isnil(b.handle) { return error('The playback backend is disconnected') }
	b.handle.set_property(name, mpv_node(value))!
}

fn (b &MpvController) events() []map[string]json2.Any {
	mut result := []map[string]json2.Any{}
	if isnil(b.handle) { return result }
	for _ in 0 .. 1000 {
		event := b.handle.wait_event(0)
		if event.id == .none { break
		 }
		result << object(node_value(event.to_node()))
	}
	return result
}

fn (mut b MpvController) close() {
	if !isnil(b.handle) {
		b.handle.terminate_destroy()
		b.handle = unsafe { nil }
	}
}
