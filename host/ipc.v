module main

import mpv
import sync
import sync.stdatomic

// One IPC client: its own mpv client handle (so observed properties, log
// requests and enabled events are per connection, as in mpv's ipc.c), a reader
// that answers requests, and an event thread that forwards events.
@[heap]
struct Session {
	pipe Pipe
	m    &mpv.Mpv
mut:
	wmu     &sync.Mutex                = sync.new_mutex()
	closing &stdatomic.AtomicVal[bool] = stdatomic.new_atomic(false)
}

// serve_client runs one IPC connection until either side closes it.
fn serve_client(core &mpv.Mpv, pipe Pipe, id int) {
	m := core.create_client('ipc-${id}') or {
		log_err('ipc: create_client failed: ${err}')
		pipe.close()
		return
	}
	mut s := &Session{
		pipe: pipe
		m:    m
	}
	trace('client ${id} connected')
	events := spawn s.forward_events()
	mut buf := []u8{len: 4096}
	mut line := []u8{}
	for !s.closing.load() {
		n := pipe.read(mut buf) or { break }
		for b in buf[..n] {
			if b == `\n` {
				s.handle_line(line.bytestr())
				line.clear()
			} else {
				line << b
			}
		}
	}
	s.closing.store(true)
	m.wakeup()
	events.wait()
	m.destroy()
	pipe.close()
	trace('client ${id} closed')
}

fn (mut s Session) send(n mpv.Node) {
	if n is map[string]mpv.Node {
		if e := n['error'] {
			if e != mpv.Node('success') {
				trace('<- error reply: ${json_encode(n)}')
			}
		}
	}
	text := json_encode(n) + '\n'
	s.wmu.lock()
	ok := s.pipe.write(text)
	s.wmu.unlock()
	if !ok {
		s.closing.store(true)
		s.m.wakeup()
		s.pipe.cancel()
	}
}

fn (mut s Session) forward_events() {
	for !s.closing.load() {
		e := s.m.wait_event(-1)
		match e.id {
			.none {}
			.shutdown {
				// The player is quitting: end the connection so the client sees EOF.
				s.closing.store(true)
				s.pipe.cancel()
			}
			.command_reply {
				s.send(reply(i64(e.reply_userdata), e.error, e.command_reply()))
			}
			else {
				s.send(e.to_node())
			}
		}
	}
}

fn reply(request_id i64, rc int, data mpv.Node) mpv.Node {
	return {
		'request_id': mpv.Node(request_id)
		'error':      mpv.Node(if rc >= 0 {
			'success'
		} else {
			mpv.error_string(rc)
		})
		'data':       data
	}
}

fn (mut s Session) handle_line(raw string) {
	text := raw.trim_space()
	if text == '' {
		return
	}
	// Lines that are not JSON are mpv input commands, answered with nothing.
	if !text.starts_with('{') {
		s.m.command_string(text) or { trace('text command failed: ${text}: ${err}') }
		return
	}
	msg := json_decode(text) or {
		trace('malformed JSON: ${err}')
		s.send(reply(0, int(mpv.ErrorCode.invalid_parameter), mpv.NodeNone{}))
		return
	}
	mut request_id := i64(0)
	mut async := false
	mut cmd := mpv.Node(mpv.NodeNone{})
	if msg is map[string]mpv.Node {
		if rid := msg['request_id'] {
			request_id = node_int(rid) or { 0 }
		}
		if a := msg['async'] {
			async = a is bool && a
		}
		cmd = msg['command'] or { mpv.Node(mpv.NodeNone{}) }
	}
	trace('-> ${text}')
	if async && !is_client_command(cmd) {
		s.m.command_node_async(u64(request_id), cmd) or {
			s.send(reply(request_id, err.code(), mpv.NodeNone{}))
		}
		return
	}
	result := s.execute(cmd) or {
		code := if err is mpv.MpvError { err.code } else { int(mpv.ErrorCode.invalid_parameter) }
		s.send(reply(request_id, code, mpv.NodeNone{}))
		return
	}
	s.send(reply(request_id, 0, result))
}

const client_commands = ['client_name', 'get_time_us', 'get_version', 'get_property',
	'get_property_string', 'set_property', 'set_property_string', 'observe_property',
	'observe_property_string', 'unobserve_property', 'request_log_messages', 'enable_event',
	'disable_event']

fn is_client_command(cmd mpv.Node) bool {
	if cmd is []mpv.Node && cmd.len > 0 {
		name := cmd[0]
		return name is string && name in client_commands
	}
	return false
}

// execute runs one command: the commands that act on this client's handle
// are handled here, like mpv's ipc.c, and the rest go to command_node.
fn (mut s Session) execute(cmd mpv.Node) !mpv.Node {
	if !is_client_command(cmd) {
		if cmd is mpv.NodeNone {
			return invalid()
		}
		return s.m.command_node(cmd)!
	}
	args := cmd as []mpv.Node
	name := args[0] as string
	match name {
		'client_name' {
			return s.m.name()
		}
		'get_time_us' {
			return s.m.time_us()
		}
		'get_version' {
			return i64(mpv.client_api_version())
		}
		'get_property' {
			return s.m.get_property_node(arg_str(args, 1)!)!
		}
		'get_property_string' {
			return s.m.get_property_string(arg_str(args, 1)!)!
		}
		'set_property' {
			if args.len != 3 {
				return invalid()
			}
			s.m.set_property(arg_str(args, 1)!, args[2])!
		}
		'set_property_string' {
			s.m.set_property_string(arg_str(args, 1)!, arg_str(args, 2)!)!
		}
		'observe_property', 'observe_property_string' {
			format := if name == 'observe_property' { mpv.Format.node } else { mpv.Format.string }
			s.m.observe_property(u64(arg_int(args, 1)!), arg_str(args, 2)!, format)!
		}
		'unobserve_property' {
			s.m.unobserve_property(u64(arg_int(args, 1)!))!
		}
		'request_log_messages' {
			s.m.request_log_messages(arg_str(args, 1)!)!
		}
		'enable_event', 'disable_event' {
			enable := name == 'enable_event'
			ev := arg_str(args, 1)!
			for id in event_ids {
				if ev == 'all' || id.name() == ev {
					s.m.request_event(id, enable)!
					if ev != 'all' {
						return mpv.NodeNone{}
					}
				}
			}
			if ev != 'all' {
				return invalid()
			}
		}
		else {}
	}

	return mpv.NodeNone{}
}

const event_ids = [mpv.EventId.shutdown, .log_message, .get_property_reply, .set_property_reply,
	.command_reply, .start_file, .end_file, .file_loaded, .idle, .tick, .client_message,
	.video_reconfig, .audio_reconfig, .seek, .playback_restart, .property_change, .queue_overflow,
	.hook]

fn invalid() mpv.MpvError {
	return mpv.MpvError{
		code: int(mpv.ErrorCode.invalid_parameter)
	}
}

fn arg_str(args []mpv.Node, i int) !string {
	if i < args.len {
		a := args[i]
		if a is string {
			return a
		}
	}
	return invalid()
}

fn arg_int(args []mpv.Node, i int) !i64 {
	if i < args.len {
		return node_int(args[i]) or { return invalid() }
	}
	return invalid()
}

fn node_int(n mpv.Node) ?i64 {
	return match n {
		i64 { n }
		f64 { i64(n) }
		else { none }
	}
}
